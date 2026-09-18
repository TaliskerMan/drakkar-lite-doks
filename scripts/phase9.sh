#!/usr/bin/env bash
# Phase 9 unattended drills for the Drakkar Lite DOKS case study.
#
# Runs the drills that don't need you watching, in order, writing every result
# into docs/results/. The drills you SHOULD watch happen live -- node drain,
# HPA scale-out and the two k6 runs -- are in docs/PHASE9_MANUAL.md.
#
# Usage:
#   source ~/Sharkbite/env.sh && cd "$REPO"
#   scripts/phase9.sh                 # every unattended drill, in order
#   scripts/phase9.sh 9.2 9.4         # only these
#   scripts/phase9.sh --list          # show what it can run
#
# Env: NS (default drakkar), CLUSTER (default drakkar-demo),
#      BASE  (full origin, e.g. https://drakkar.nordheim.online -- wins if set)
#      LB_IP (auto-detected from the Gateway; used only when BASE is unset)
#
# Safe to re-run. Each drill overwrites its own files; collect_evidence.sh
# snapshots are timestamped, so they accumulate rather than clobber.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

NS="${NS:-drakkar}"
CLUSTER="${CLUSTER:-drakkar-demo}"
RESULTS="docs/results"
mkdir -p "$RESULTS"

ALL_DRILLS=(9.1 9.2 9.3 9.4 9.5 9.10 9.11 9.12)
FAILED=()

# --- preflight ---------------------------------------------------------------

for bin in kubectl curl; do
  command -v "$bin" >/dev/null 2>&1 || { echo "Missing required tool: $bin" >&2; exit 1; }
done

# BASE wins if set, so the drills can run over HTTPS:
#
#     BASE=https://drakkar.nordheim.online scripts/phase9.sh
#
# That is the point of running them again after 04_HTTPS_SETUP.md -- the p95 and
# requests/second numbers should include TLS termination, because that is what
# the demo actually serves. Falls back to http://$LB_IP when BASE is unset.
if [[ -z "${BASE:-}" ]]; then
  if [[ -z "${LB_IP:-}" ]]; then
    LB_IP=$(kubectl -n "$NS" get gateway drakkar -o jsonpath='{.status.addresses[0].value}' 2>/dev/null)
  fi
  if [[ -z "${LB_IP:-}" ]]; then
    cat >&2 <<'EOF'
Neither BASE nor LB_IP is set, and the Gateway reports no address.
Set one and re-run:

    export BASE=https://drakkar.nordheim.online     # preferred, post-TLS
    export LB_IP=134.199.251.181                    # plain HTTP fallback
EOF
    exit 1
  fi
  BASE="http://$LB_IP"
fi

# Fail fast on a typo'd or unreachable BASE rather than 8 drills deep.
if ! curl -sS -o /dev/null --max-time 15 "$BASE/" 2>/dev/null; then
  echo "Cannot reach $BASE -- check the host, or fall back to http://\$LB_IP" >&2
  exit 1
fi

# --- cluster health gate -----------------------------------------------------
#
# Added 2026-09-18 after a real miss. Every new API pod was stuck in
# InvalidImageName (a kustomization still saying YOUR_REGISTRY got applied),
# while the previous ReplicaSet kept serving. The app looked fine and the
# rollout, self-heal and rollback drills all recorded "0 failed" -- because
# nothing ever actually rolled. The drills measured a deployment that could not
# move and called it zero-downtime.
#
# So: refuse to produce evidence from a cluster that is not actually healthy.
# Override with SKIP_HEALTH_GATE=1 if you are deliberately drilling a broken
# state.
if [[ "${SKIP_HEALTH_GATE:-0}" != "1" ]]; then
  bad=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null \
        | grep -Ev '\s(Running|Completed)\s' || true)
  if [[ -n "$bad" ]]; then
    {
      echo "Refusing to run: pods in $NS are not healthy."
      echo
      echo "$bad"
      echo
      echo "InvalidImageName / ErrImagePull almost always means a kustomization"
      echo "still has a placeholder. Check and fix with:"
      echo
      echo "    grep -n newName k8s/kustomization.yaml k8s/migrate/kustomization.yaml"
      echo "    scripts/set_registry.sh \$REG \$TAG"
      echo "    kubectl apply -k k8s-tls"
      echo
      echo "Then confirm before re-running:"
      echo "    kubectl -n $NS rollout status deploy/drakkar-api --timeout=180s"
    } >&2
    exit 1
  fi

  for d in drakkar-api drakkar-web; do
    want=$(kubectl -n "$NS" get deploy "$d" -o jsonpath='{.spec.replicas}' 2>/dev/null)
    have=$(kubectl -n "$NS" get deploy "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
    if [[ -z "$want" || "${have:-0}" != "$want" ]]; then
      echo "Refusing to run: deploy/$d has ${have:-0}/${want:-?} replicas ready." >&2
      echo "Let the rollout finish, or investigate, before collecting evidence." >&2
      exit 1
    fi
  done
  echo "Health gate: all pods Running, both deployments fully rolled out."
fi

hr() {
  printf '\n========================================================\n'
  printf '  %s\n' "$1"
  printf '========================================================\n'
}

note() { printf '  %s\n' "$*"; }

# --- drills ------------------------------------------------------------------

drill_9_1() { # Baseline snapshot
  hr "9.1  Baseline snapshot (idle)"
  SPENT_BEFORE=0 scripts/cost_check.sh 2>&1 | tee "$RESULTS/cost-idle.txt"
  scripts/collect_evidence.sh idle
}

drill_9_2() { # Load balancing
  hr "9.2  Load balancing across pods"
  local out="$RESULTS/load-balancing.txt"
  {
    echo "\$ curl -s -D - $BASE/v1/auth/me  (x12, showing x-served-by)"
    echo
    for _ in $(seq 12); do
      curl -s -D - -o /dev/null --max-time 5 "$BASE/v1/auth/me" \
        | tr -d '\r' | awk -F': ' 'tolower($1)=="x-served-by"{print $2}'
    done
  } > "$out" 2>&1
  cat "$out"
  note "Distinct pods that answered: $(tail -n +3 "$out" | sort -u | grep -c . || echo 0)"
}

drill_9_3() { # Tenant isolation
  hr "9.3  Tenant isolation"
  scripts/isolation_demo.sh "$BASE" 2>&1 | tee "$RESULTS/isolation.txt"
}

drill_9_4() { # Zero-downtime rollout
  hr "9.4  Zero-downtime rollout"
  local out="$RESULTS/rollout-restart.txt"
  kubectl -n "$NS" get pods -l app=drakkar-api -o wide > "$RESULTS/rollout-pods-before.txt" 2>&1

  note "Starting the request probe (120s)..."
  scripts/rollout_check.sh "$BASE" 120 > "$out" 2>&1 &
  local probe=$!
  sleep 12

  note "Restarting deploy/drakkar-api..."
  { echo; echo "--- rollout restart at $(date +%T) ---"; } >> "$out"
  kubectl -n "$NS" rollout restart deploy/drakkar-api 2>&1 | tee -a "$out"
  kubectl -n "$NS" rollout status deploy/drakkar-api --timeout=180s 2>&1 | tee -a "$out"

  wait "$probe"
  kubectl -n "$NS" get pods -l app=drakkar-api -o wide > "$RESULTS/rollout-pods-after.txt" 2>&1
  tail -3 "$out"
}

drill_9_5() { # Self-healing
  hr "9.5  Self-healing"
  local out="$RESULTS/self-heal.txt"

  note "Starting the request probe (90s)..."
  scripts/rollout_check.sh "$BASE" 90 > "$out" 2>&1 &
  local probe=$!
  sleep 10

  local victim
  victim=$(kubectl -n "$NS" get pod -l app=drakkar-api -o name | head -1)
  note "Deleting $victim"
  { echo; echo "--- deleted $victim at $(date +%T) ---"; } >> "$out"
  kubectl -n "$NS" delete "$victim" --wait=false 2>&1 | tee -a "$out"

  # Watch the replacement come back while the probe keeps running.
  {
    for _ in $(seq 25); do
      date +%T
      kubectl -n "$NS" get pods -l app=drakkar-api -o wide
      echo
      sleep 3
    done
  } > "$RESULTS/self-heal-pods.txt" 2>&1 &
  local watcher=$!

  wait "$probe"
  kill "$watcher" 2>/dev/null
  wait "$watcher" 2>/dev/null
  tail -3 "$out"
}

drill_9_10() { # Rollback
  hr "9.10  Rollback"
  local out="$RESULTS/rollback.txt"
  {
    echo "--- history before ---"
    kubectl -n "$NS" rollout history deploy/drakkar-api
    echo
    echo "--- rollout undo at $(date +%T) ---"
    kubectl -n "$NS" rollout undo deploy/drakkar-api
    echo
    kubectl -n "$NS" rollout status deploy/drakkar-api --timeout=180s
    echo
    echo "--- history after ---"
    kubectl -n "$NS" rollout history deploy/drakkar-api
    echo
    kubectl -n "$NS" get pods -l app=drakkar-api -o wide
  } > "$out" 2>&1
  cat "$out"
}

drill_9_11() { # Logs and metrics
  hr "9.11  Logs and metrics"
  kubectl -n "$NS" logs deploy/drakkar-api --tail=40 > "$RESULTS/api-logs.txt" 2>&1
  note "Wrote $RESULTS/api-logs.txt"

  kubectl -n "$NS" port-forward deploy/drakkar-api 9090:8080 >/dev/null 2>&1 &
  local pf=$!
  sleep 5
  if curl -fsS --max-time 10 http://localhost:9090/metrics > "$RESULTS/api-metrics.txt" 2>&1; then
    note "Wrote $RESULTS/api-metrics.txt ($(wc -l < "$RESULTS/api-metrics.txt" | tr -d ' ') lines)"
  else
    note "Metrics scrape failed -- check that the API exposes /metrics on 8080"
  fi
  kill "$pf" 2>/dev/null
  wait "$pf" 2>/dev/null
  # `wait` on a process we just SIGTERM'd returns 143, which would make this
  # function look like a failed drill even when both files were written.
  # Report on the artifacts instead.
  [[ -s "$RESULTS/api-logs.txt" && -s "$RESULTS/api-metrics.txt" ]]
}

drill_9_12() { # Database proof: RLS enabled and forced
  hr "9.12  Database proof (row-level security)"
  local out="$RESULTS/rls.txt"
  local url
  url=$(kubectl -n "$NS" get secret drakkar-db -o jsonpath='{.data.MIGRATOR_DATABASE_URL}' 2>/dev/null | base64 -d)
  if [[ -z "$url" ]]; then
    echo "Could not read MIGRATOR_DATABASE_URL from the drakkar-db Secret." | tee "$out"
    return 1
  fi

  local sql="select relname, relrowsecurity, relforcerowsecurity from pg_class where relname in ('contacts','audit_logs');"

  kubectl delete pod pgcheck -n default --ignore-not-found --wait=true >/dev/null 2>&1
  # URL and query go in via --env so neither is echoed into the results file.
  kubectl run pgcheck -n default --rm -i --restart=Never --image=postgres:17-alpine \
    --env="PGURL=$url" --env="SQL=$sql" -- \
    sh -c 'psql "$PGURL" -c "$SQL"' \
    > "$out" 2>&1
  cat "$out"
  note "Both tables should show t | t"
}

# --- runner ------------------------------------------------------------------

run_drill() {
  local d="$1"
  local fn="drill_${d//./_}"
  if ! declare -F "$fn" >/dev/null; then
    echo "Unknown drill: $d (try --list)" >&2
    return 1
  fi
  if ! "$fn"; then
    FAILED+=("$d")
    note "!! $d reported a problem"
  fi
}

if [[ "${1:-}" == "--list" ]]; then
  cat <<'EOF'
Unattended drills in this script:
  9.1   Baseline snapshot (cost + collect_evidence idle)
  9.2   Load balancing across pods
  9.3   Tenant isolation
  9.4   Zero-downtime rollout
  9.5   Self-healing
  9.10  Rollback
  9.11  Logs and metrics
  9.12  Database proof (RLS)

Watch these live instead -- see docs/PHASE9_MANUAL.md:
  9.6   Node drain
  9.7   HPA scale-out
  9.8   k6 performance baseline
  9.9   k6 while scaled out
EOF
  exit 0
fi

DRILLS=("$@")
[[ ${#DRILLS[@]} -eq 0 ]] && DRILLS=("${ALL_DRILLS[@]}")

echo "Target:  $BASE"
echo "Cluster: $CLUSTER   Namespace: $NS"
echo "Drills:  ${DRILLS[*]}"

START=$SECONDS
for d in "${DRILLS[@]}"; do
  run_drill "$d"
done

hr "Phase 9 unattended drills complete ($((SECONDS - START))s)"
if [[ ${#FAILED[@]} -gt 0 ]]; then
  echo "Reported problems: ${FAILED[*]}"
else
  echo "No drill reported a problem."
fi
echo
echo "Files now in $RESULTS:"
ls -1 "$RESULTS" | sed 's/^/  /'
echo
echo "Next: the live drills in docs/PHASE9_MANUAL.md (drain, HPA, k6),"
echo "then commit docs/results/."
