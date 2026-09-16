#!/usr/bin/env bash
# One-shot build check for Drakkar Lite. Run it before the first deploy and
# after any code change. It never touches DigitalOcean.
#
#   scripts/verify_build.sh                 # Dart + Flutter + Docker images + manifests
#   SKIP_DOCKER=1 scripts/verify_build.sh   # skip the image builds
#   E2E=1 scripts/verify_build.sh           # also run the stack with docker compose
#                                           # and the tenant-isolation test
#
# Works on Linux (bash 4+) and macOS (bash 3.2). Output from each step is
# saved in .verify/<step>.log; the summary at the end lists what failed.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
ROOT="$(pwd)"
LOGS="$ROOT/.verify"
mkdir -p "$LOGS"

PASSED=""
FAILED=""
SKIPPED=""

step() { # step <name> <command...>
  local name="$1"; shift
  local log
  log="$LOGS/$(printf '%s' "$name" | tr ' /:' '___').log"
  printf '▶ %-38s ' "$name"
  if "$@" >"$log" 2>&1; then
    echo "ok"
    PASSED="$PASSED\n  ✔ $name"
  else
    echo "FAILED  (see ${log#$ROOT/})"
    tail -n 15 "$log" | sed 's/^/      /'
    FAILED="$FAILED\n  ✘ $name  →  ${log#$ROOT/}"
  fi
}

skip() { printf '▶ %-38s skipped (%s)\n' "$1" "$2"; SKIPPED="$SKIPPED\n  – $1: $2"; }
have() { command -v "$1" >/dev/null 2>&1; }

echo "Drakkar Lite build check — $(date)"
echo "Repo: $ROOT"
for tool in dart flutter docker kubectl; do
  if have "$tool"; then printf '  %-8s %s\n' "$tool" "$(command -v "$tool")"; else printf '  %-8s MISSING\n' "$tool"; fi
done
echo

# ---------------------------------------------------------------- Dart ------
if have dart; then
  dart --version 2>&1 | head -1
  step "core: pub get"        bash -c 'cd core && dart pub get'
  step "core: analyze"        bash -c 'cd core && dart analyze'
  step "core: test"           bash -c 'cd core && dart test'
  step "server: pub get"      bash -c 'cd server && dart pub get'
  step "server: analyze"      bash -c 'cd server && dart analyze'
  step "server: test"         bash -c 'cd server && dart test'
  step "server: compile exe"  bash -c 'cd server && dart compile exe bin/server.dart -o "$0/server-native"' "$LOGS"
else
  skip "dart steps" "dart not installed"
fi

# ------------------------------------------------------------- Flutter ------
if have flutter; then
  flutter --version 2>&1 | head -1
  if [ ! -f web/web/index.html ]; then
    # Adds only the missing web scaffold (web/web/index.html, icons, manifest);
    # existing files such as lib/main.dart are left alone.
    step "web: flutter create (scaffold)" bash -c 'cd web && flutter create --platforms=web --project-name drakkar_web .'
  fi
  step "web: pub get"         bash -c 'cd web && flutter pub get'
  step "web: analyze"         bash -c 'cd web && flutter analyze --no-fatal-infos'
  step "web: test"            bash -c 'cd web && flutter test'
  # --no-web-resources-cdn bundles CanvasKit into the build, so the app does
  # not depend on a Google CDN at runtime.
  step "web: build web"       bash -c 'cd web && flutter build web --release --no-web-resources-cdn'
else
  skip "flutter steps" "flutter not installed"
fi

# -------------------------------------------------------------- Docker ------
if [ "${SKIP_DOCKER:-0}" = "1" ]; then
  skip "docker images" "SKIP_DOCKER=1"
elif ! have docker; then
  skip "docker images" "docker not installed"
else
  # DOKS nodes are x86-64. On an x86-64 Linux host this is a native build;
  # on Apple Silicon buildx cross-builds.
  step "image: drakkar-api (amd64)" docker buildx build --platform linux/amd64 \
    -f server/Dockerfile -t drakkar-api:verify --load .
  if [ -d web/build/web ]; then
    step "image: drakkar-web (amd64)" docker buildx build --platform linux/amd64 \
      -t drakkar-web:verify --load web
  else
    skip "image: drakkar-web" "web/build/web missing (flutter build web failed or skipped)"
  fi
  if docker image inspect drakkar-api:verify >/dev/null 2>&1; then
    step "image: api size + arch" bash -c \
      'docker image inspect drakkar-api:verify --format "{{.Architecture}} {{.Size}} bytes" && test "$(docker image inspect drakkar-api:verify --format "{{.Architecture}}")" = amd64'
  fi
fi

# ----------------------------------------------------------- Manifests ------
if have kubectl; then
  step "k8s: kustomize k8s"          bash -c 'kubectl kustomize k8s >"$0/rendered-k8s.yaml"' "$LOGS"
  step "k8s: kustomize k8s/migrate"  bash -c 'kubectl kustomize k8s/migrate >"$0/rendered-migrate.yaml"' "$LOGS"
  if grep -q YOUR_REGISTRY k8s/kustomization.yaml k8s/migrate/kustomization.yaml; then
    echo "  note: kustomizations still say YOUR_REGISTRY — run scripts/set_registry.sh <registry> <tag> before deploying"
  fi
else
  skip "k8s manifests" "kubectl not installed"
fi

# ----------------------------------------------------------------- E2E ------
if [ "${E2E:-0}" = "1" ]; then
  if have docker && [ -d web/build/web ]; then
    step "e2e: compose up"   docker compose up -d --build
    step "e2e: isolation"    bash -c 'for i in $(seq 1 30); do curl -fsS -o /dev/null http://localhost:${API_PORT:-8080}/readyz && break; sleep 2; done; scripts/isolation_demo.sh http://localhost:${WEB_PORT:-8081}'
    step "e2e: api metrics"  bash -c 'curl -fsS http://localhost:${API_PORT:-8080}/metrics | grep -q drakkar_http_requests_total'
    step "e2e: compose down" docker compose down -v
  else
    skip "e2e" "needs docker and a web build"
  fi
fi

echo
echo "================ Summary ================"
[ -n "$PASSED" ]  && printf "Passed:%b\n" "$PASSED"
[ -n "$SKIPPED" ] && printf "Skipped:%b\n" "$SKIPPED"
if [ -n "$FAILED" ]; then
  printf "FAILED:%b\n" "$FAILED"
  echo "Fix the failures above (see 01_CODE_FIXES.md §5 for likely causes), then re-run."
  exit 1
fi
echo "All checks passed."
