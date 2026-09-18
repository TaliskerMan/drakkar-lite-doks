#!/usr/bin/env bash
#
# enable_tls.sh -- turn on HTTPS for Drakkar Lite.
#
#   source ~/Sharkbite/env.sh && cd $REPO
#   scripts/enable_tls.sh
#
# Rehearsal against Let's Encrypt staging (effectively unlimited rate limits,
# browser will not trust the result):
#
#   STAGING=1 scripts/enable_tls.sh
#
# Every step is idempotent and nothing here deletes anything. The script stops
# at the first failed precondition with a named cause, because the expensive
# failure mode is burning a Let's Encrypt rate limit on a request that was
# never going to succeed.
#
# See 04_HTTPS_SETUP.md for the design and the rejected alternatives.

set -euo pipefail

HOST="${HOST:-drakkar.nordheim.online}"
NS="${NS:-drakkar}"
STAGING="${STAGING:-0}"
CM_NS="${CM_NS:-cert-manager}"
# Pinned empty on purpose: resolved to the newest 1.21.x from the chart repo
# below. Override to pin explicitly, e.g. CM_VERSION=v1.21.1
CM_VERSION="${CM_VERSION:-}"
CM_MINOR="${CM_MINOR:-1.21}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname -- "$SCRIPT_DIR")"

bold=$'\033[1m'; red=$'\033[31m'; green=$'\033[32m'; yellow=$'\033[33m'; off=$'\033[0m'
step() { printf '\n%s==> %s%s\n' "$bold" "$1" "$off"; }
ok()   { printf '  %s[ ok ]%s %s\n'   "$green"  "$off" "$1"; }
warn() { printf '  %s[warn]%s %s\n'   "$yellow" "$off" "$1"; }
die()  { printf '\n%s[stop]%s %s\n\n' "$red"    "$off" "$1" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || die "$1 is not installed. $2"; }

# ---------------------------------------------------------------- preflight 1
step "1/7  Cluster and Gateway"

need kubectl "Install it from https://dl.k8s.io/release/stable.txt (no snap on this box)."
need helm    "Install it with: curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
need curl    "apt install curl"
need openssl "apt install openssl"

kubectl cluster-info >/dev/null 2>&1 \
  || die "kubectl cannot reach a cluster. Run: doctl kubernetes cluster kubeconfig save \${CLUSTER:-drakkar-demo}"
ok "kubectl reaches $(kubectl config current-context)"

kubectl get namespace "$NS" >/dev/null 2>&1 \
  || die "Namespace '$NS' does not exist. Deploy the app first: kubectl apply -k k8s"

LB_ADDR="$(kubectl -n "$NS" get gateway drakkar -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || true)"
[ -n "$LB_ADDR" ] \
  || die "Gateway 'drakkar' has no address yet. Check: kubectl -n $NS describe gateway drakkar"
ok "Gateway address is $LB_ADDR"

# ---------------------------------------------------------------- preflight 2
step "2/7  DNS"

resolved=""
if command -v dig >/dev/null 2>&1; then
  resolved="$(dig +short A "$HOST" @1.1.1.1 | grep -E '^[0-9.]+$' | head -1 || true)"
else
  warn "dig not found (apt install dnsutils) -- falling back to getent, which uses your local resolver"
  resolved="$(getent ahostsv4 "$HOST" | awk 'NR==1{print $1}' || true)"
fi

[ -n "$resolved" ] \
  || die "$HOST does not resolve. Add the A record at Cloudflare (04_HTTPS_SETUP.md §3), then re-run."

if [ "$resolved" != "$LB_ADDR" ]; then
  case "$resolved" in
    104.*|172.6[4-9].*|172.7[0-1].*|188.114.*|190.93.*|197.234.*|198.41.*)
      die "$HOST resolves to $resolved, which is a Cloudflare proxy address, but the load balancer is $LB_ADDR.
       The orange cloud is on. Cloudflare -> DNS -> the 'drakkar' record -> Edit ->
       set Proxy status to 'DNS only' (grey cloud). Takes effect in seconds." ;;
    *)
      die "$HOST resolves to $resolved, but the load balancer is $LB_ADDR.
       Update the A record at Cloudflare. Do not force past this -- the ACME
       challenge would be answered by whatever is at $resolved, not by you." ;;
  esac
fi
ok "$HOST -> $resolved (matches the load balancer)"

# ---------------------------------------------------------------- preflight 3
step "3/7  CAA records"

if command -v dig >/dev/null 2>&1; then
  caa="$(dig +short CAA "${HOST#*.}" @1.1.1.1 || true)"
  if [ -z "$caa" ]; then
    ok "No CAA record on ${HOST#*.} -- any CA may issue"
  elif printf '%s' "$caa" | grep -q 'letsencrypt.org'; then
    ok "CAA present and allows letsencrypt.org"
  else
    die "A CAA record on ${HOST#*.} does not list letsencrypt.org:
$caa
       Let's Encrypt will refuse to issue. Add: 0 issue \"letsencrypt.org\""
  fi
else
  warn "Skipping CAA check (dig not installed)"
fi

# ---------------------------------------------------------------- preflight 4
step "4/7  Port 80 reachable from the internet"

code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 "http://$HOST/" || echo 000)"
[ "$code" != "000" ] \
  || die "http://$HOST/ did not answer. The HTTP-01 challenge is served over plain HTTP on
       port 80, so this listener must stay open. Check: kubectl -n $NS get gateway drakkar"
ok "http://$HOST/ answered $code"

# ---------------------------------------------------------------- cert-manager
step "5/7  cert-manager"

helm repo add jetstack https://charts.jetstack.io --force-update >/dev/null
helm repo update jetstack >/dev/null

if [ -z "$CM_VERSION" ]; then
  CM_VERSION="$(helm search repo jetstack/cert-manager --versions 2>/dev/null \
    | awk 'NR>1 && $1=="jetstack/cert-manager" {print $2}' \
    | grep -E "^v?${CM_MINOR//./\\.}\." | head -1 || true)"
  [ -n "$CM_VERSION" ] \
    || die "Could not resolve a cert-manager ${CM_MINOR}.x chart version.
       Pin one explicitly: CM_VERSION=v1.21.1 scripts/enable_tls.sh"
fi
ok "Installing cert-manager $CM_VERSION"

# config.enableGatewayAPI is the supported flag since cert-manager 1.16; without
# it cert-manager ignores Gateways entirely and the HTTP-01 solver never fires.
# The chart validates the whole `config` block, so apiVersion and kind have to
# be set alongside it.
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace "$CM_NS" --create-namespace \
  --version "$CM_VERSION" \
  --set crds.enabled=true \
  --set config.apiVersion="controller.config.cert-manager.io/v1alpha1" \
  --set config.kind="ControllerConfiguration" \
  --set config.enableGatewayAPI=true \
  --wait --timeout 5m

kubectl -n "$CM_NS" rollout status deploy/cert-manager --timeout=180s
kubectl -n "$CM_NS" rollout status deploy/cert-manager-webhook --timeout=180s
ok "cert-manager is running"

# ---------------------------------------------------------------- issuers
step "6/7  Issuers and certificate"

kubectl apply -f "$ROOT/k8s-tls/clusterissuer.yaml"

if [ "$STAGING" = "1" ]; then
  ISSUER="letsencrypt-staging"
  warn "STAGING=1 -- the browser will NOT trust this certificate. Re-run without it for the real one."
else
  ISSUER="letsencrypt-prod"
fi

# The webhook can take a few seconds to start serving after rollout.
for _ in $(seq 1 30); do
  kubectl get clusterissuer "$ISSUER" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null \
    | grep -q True && break
  sleep 2
done
kubectl get clusterissuer "$ISSUER" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null \
  | grep -q True \
  || die "ClusterIssuer $ISSUER is not Ready. Check: kubectl describe clusterissuer $ISSUER"
ok "ClusterIssuer $ISSUER is Ready"

# Apply the Certificate ALONE, before the overlay. The :443 listener must not
# exist until the Secret does, or the Gateway sits at ResolvedRefs: False.
tmp_cert="$(mktemp)"
trap 'rm -f "$tmp_cert"' EXIT
sed "s/name: letsencrypt-prod/name: $ISSUER/" "$ROOT/k8s-tls/certificate.yaml" > "$tmp_cert"
kubectl apply -f "$tmp_cert"

printf '  waiting for issuance (usually 30-90s) ...\n'
if ! kubectl -n "$NS" wait --for=condition=Ready certificate/drakkar-tls --timeout=300s; then
  printf '\n%sIssuance did not complete. The cause is almost always the challenge:%s\n' "$bold" "$off" >&2
  kubectl -n "$NS" describe certificate drakkar-tls | tail -20 >&2 || true
  kubectl -n "$NS" get challenge -o wide >&2 2>/dev/null || true
  kubectl -n "$NS" describe challenge 2>/dev/null | grep -A2 -i 'reason\|message' | head -20 >&2 || true
  die "See 04_HTTPS_SETUP.md §6. The 'reason' field on the Challenge is specific."
fi
ok "Certificate issued into secret/drakkar-tls"

# ---------------------------------------------------------------- listener
step "7/7  :443 listener and redirect"

kubectl apply -k "$ROOT/k8s-tls"

# The overlay must not own the Certificate -- if it did, this apply would reset
# issuerRef to letsencrypt-prod and silently re-issue against the production CA
# during a STAGING=1 rehearsal. k8s-tls/kustomization.yaml excludes it; this is
# the belt-and-braces check that it stayed excluded.
actual_issuer="$(kubectl -n "$NS" get certificate drakkar-tls \
  -o jsonpath='{.spec.issuerRef.name}' 2>/dev/null || true)"
if [ "$actual_issuer" != "$ISSUER" ]; then
  die "After applying the overlay the Certificate's issuer is '$actual_issuer',
       but this run asked for '$ISSUER'. Something re-applied certificate.yaml.
       Check that k8s-tls/kustomization.yaml does NOT list certificate.yaml."
fi
ok "Certificate issuer still $ISSUER after the overlay"

for _ in $(seq 1 30); do
  kubectl -n "$NS" get gateway drakkar -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null \
    | grep -q True && break
  sleep 2
done
kubectl -n "$NS" get gateway drakkar -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null \
  | grep -q True \
  || die "Gateway is not Programmed. Check: kubectl -n $NS describe gateway drakkar"
ok "Gateway programmed with listeners: $(kubectl -n "$NS" get gateway drakkar -o jsonpath='{range .spec.listeners[*]}{.name}:{.port} {end}')"

printf '\n%sHTTPS is on.%s Verify with:\n\n' "$green$bold" "$off"
printf '    scripts/tls_check.sh %s\n' "$HOST"
printf '    scripts/tls_check.sh %s | tee docs/results/tls-check.txt\n\n' "$HOST"
if [ "$STAGING" = "1" ]; then
  printf '%sThis was a STAGING run.%s Before the real one:\n' "$yellow$bold" "$off"
  printf '    kubectl -n %s delete secret drakkar-tls\n    scripts/enable_tls.sh\n\n' "$NS"
fi
