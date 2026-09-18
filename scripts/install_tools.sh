#!/usr/bin/env bash
#
# install_tools.sh -- install the CLI tools enable_tls.sh needs, on Pop!_OS.
#
#   scripts/install_tools.sh
#
# Installs kubectl, helm and dnsutils from apt repositories. No snap (this box
# has none) and no piping a remote script into bash.
#
# kubectl's version is NOT hardcoded. The pkgs.k8s.io apt repository is split
# per minor version, so the script asks doctl what the cluster actually runs and
# subscribes to the matching repo. kubectl is supported within one minor version
# of the API server in either direction; matching exactly avoids the question.
#
# Safe to re-run. Everything here is idempotent.

set -euo pipefail

CLUSTER="${CLUSTER:-drakkar-demo}"
# Fallback only, used if doctl can't tell us. Override with K8S_MINOR=1.34
K8S_MINOR="${K8S_MINOR:-}"

bold=$'\033[1m'; red=$'\033[31m'; green=$'\033[32m'; yellow=$'\033[33m'; off=$'\033[0m'
step() { printf '\n%s==> %s%s\n' "$bold" "$1" "$off"; }
ok()   { printf '  %s[ ok ]%s %s\n' "$green"  "$off" "$1"; }
warn() { printf '  %s[warn]%s %s\n' "$yellow" "$off" "$1"; }
die()  { printf '\n%s[stop]%s %s\n\n' "$red"  "$off" "$1" >&2; exit 1; }

[ "$(id -u)" -ne 0 ] || die "Run this as your normal user, not root. It calls sudo where it needs to."

# ------------------------------------------------------------ shadowed binary
step "Checking for an existing kubectl"

if command -v kubectl >/dev/null 2>&1; then
  existing="$(command -v kubectl)"
  warn "kubectl is already on PATH at $existing"
  printf '      version: %s\n' "$(kubectl version --client -o yaml 2>/dev/null | awk -F': ' '/gitVersion/{print $2; exit}')"
  case "$existing" in
    /usr/bin/kubectl) ok "That is the apt location; this script will just update it." ;;
    *) warn "That is NOT the apt location. After this script installs /usr/bin/kubectl,
      $existing will still win if its directory comes first in PATH.
      Remove it, or make sure /usr/bin precedes it." ;;
  esac
else
  ok "No kubectl on PATH"
fi

# --------------------------------------------------------------------- doctl
step "Installing doctl"

# DigitalOcean ships doctl as a GitHub release tarball, not an apt package.
# The latest tag is resolved by following the /releases/latest redirect, which
# needs no API token and no jq.
if command -v doctl >/dev/null 2>&1; then
  ok "doctl already installed: $(doctl version 2>/dev/null | head -1)"
else
  sudo apt-get update -qq
  sudo apt-get install -y -qq curl ca-certificates

  latest_url="$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/digitalocean/doctl/releases/latest)"
  DOCTL_VER="${latest_url##*/v}"
  printf '%s' "$DOCTL_VER" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' \
    || die "Could not resolve the latest doctl version (got '$DOCTL_VER').
       Download it by hand from https://github.com/digitalocean/doctl/releases
       and: tar xf doctl-*.tar.gz && sudo install -m 0755 doctl /usr/local/bin/doctl"
  ok "Latest doctl is v$DOCTL_VER"

  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  base="https://github.com/digitalocean/doctl/releases/download/v$DOCTL_VER"
  tarball="doctl-$DOCTL_VER-linux-amd64.tar.gz"

  curl -fsSL -o "$tmp/$tarball"      "$base/$tarball"
  curl -fsSL -o "$tmp/checksums.txt" "$base/doctl-$DOCTL_VER-checksums.sha256" 2>/dev/null \
    || curl -fsSL -o "$tmp/checksums.txt" "$base/doctl-$DOCTL_VER-checksums.txt" 2>/dev/null \
    || true

  if [ -s "$tmp/checksums.txt" ]; then
    ( cd "$tmp" && grep " $tarball\$" checksums.txt | sha256sum -c - ) \
      || die "Checksum mismatch on $tarball. Do not install it."
    ok "Checksum verified"
  else
    warn "No checksum file published for this release -- skipping verification"
  fi

  tar -xzf "$tmp/$tarball" -C "$tmp" doctl
  sudo install -m 0755 "$tmp/doctl" /usr/local/bin/doctl
  ok "doctl installed to /usr/local/bin/doctl"
fi

# ----------------------------------------------------------------------- auth
step "Checking the DigitalOcean API token"

if ! doctl account get >/dev/null 2>&1; then
  die "doctl is installed but not authenticated.

       Run this yourself -- it prompts for your DigitalOcean API token, which is
       a secret and is not something to paste into a chat:

         doctl auth init

       A token with read+write scope: https://cloud.digitalocean.com/account/api/tokens
       Then re-run: scripts/install_tools.sh"
fi
ok "Authenticated as $(doctl account get --format Email --no-header 2>/dev/null)"

# --------------------------------------------------------------- which minor
step "Deciding which kubectl minor version to install"

if [ -z "$K8S_MINOR" ]; then
  raw="$(doctl kubernetes cluster get "$CLUSTER" --format Version --no-header 2>/dev/null || true)"
  # e.g. "1.33.1-do.0" -> "1.33"
  K8S_MINOR="$(printf '%s' "$raw" | grep -oE '^[0-9]+\.[0-9]+' || true)"
  if [ -n "$K8S_MINOR" ]; then
    ok "Cluster '$CLUSTER' runs $raw -> installing kubectl v$K8S_MINOR"
  else
    printf '\n  Clusters visible on this account:\n'
    doctl kubernetes cluster list --format Name,Version,Status 2>/dev/null | sed 's/^/    /'
    die "Cluster '$CLUSTER' was not found on this account.
       If it is listed above under another name: CLUSTER=<name> scripts/install_tools.sh
       If the list is empty, the cluster no longer exists and the deployment
       needs rebuilding before any of the TLS work can proceed."
  fi
fi

# ------------------------------------------------------------------- kubectl
step "Installing kubectl v$K8S_MINOR"

sudo apt-get update -qq
sudo apt-get install -y -qq apt-transport-https ca-certificates curl gnupg

sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/v$K8S_MINOR/deb/Release.key" \
  | sudo gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
sudo chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v$K8S_MINOR/deb/ /" \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list >/dev/null
sudo chmod 644 /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update -qq
sudo apt-get install -y -qq kubectl
ok "kubectl $(kubectl version --client -o yaml 2>/dev/null | awk -F': ' '/gitVersion/{print $2; exit}')"

# ------------------------------------------------------------------- the rest
# Installed BEFORE helm on purpose: these come from the distro mirrors that are
# already working, so a problem fetching helm cannot leave them missing.
step "Supporting tools"

sudo apt-get install -y -qq dnsutils openssl ca-certificates
ok "dig and openssl present (enable_tls.sh uses both for its preflight checks)"

# ---------------------------------------------------------------------- helm
step "Installing helm"

# Helm's apt repo at baltocdn.com has been observed failing TLS verification
# ("unable to get local issuer certificate") on networks where github.com and
# pkgs.k8s.io verify fine. Rather than debug someone else's CDN chain, take the
# official tarball from get.helm.sh -- the same pattern doctl already uses
# successfully above, with a published checksum to verify.
if command -v helm >/dev/null 2>&1; then
  ok "helm already installed: $(helm version --short 2>/dev/null)"
else
  htmp="$(mktemp -d)"
  # Replaces the doctl trap, so clean up both temp dirs here.
  trap 'rm -rf "$htmp" "${tmp:-}"' EXIT

  HELM_VER="${HELM_VER:-$(curl -fsSL --max-time 30 https://get.helm.sh/helm-latest-version || true)}"
  printf '%s' "$HELM_VER" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+$' \
    || die "Could not resolve the latest helm version (got '${HELM_VER:-<empty>}').

       If this is another TLS verification failure, check the system trust store first:
         sudo update-ca-certificates
         curl -v https://get.helm.sh/helm-latest-version 2>&1 | grep -i 'issuer\\|subject\\|SSL'

       Or pin a version and re-run:  HELM_VER=v3.16.4 scripts/install_tools.sh"
  ok "Latest helm is $HELM_VER"

  arch="$(dpkg --print-architecture)"   # amd64 / arm64
  htar="helm-$HELM_VER-linux-$arch.tar.gz"

  curl -fsSL --max-time 120 -o "$htmp/$htar"     "https://get.helm.sh/$htar"
  curl -fsSL --max-time 30  -o "$htmp/$htar.sha256sum" "https://get.helm.sh/$htar.sha256sum" || true

  if [ -s "$htmp/$htar.sha256sum" ]; then
    ( cd "$htmp" && awk '{print $1"  '"$htar"'"}' "$htar.sha256sum" | sha256sum -c - ) \
      || die "Checksum mismatch on $htar. Do not install it."
    ok "Checksum verified"
  else
    warn "No checksum published -- skipping verification"
  fi

  tar -xzf "$htmp/$htar" -C "$htmp"
  sudo install -m 0755 "$htmp/linux-$arch/helm" /usr/local/bin/helm
  ok "helm $(helm version --short 2>/dev/null) installed to /usr/local/bin/helm"
fi

# ------------------------------------------------------------------------ k6
step "Installing k6"

# Phase 9 drills 9.8 and 9.9 need this -- it produces the only performance
# numbers that go in the deck and the QBR.
#
# k6 publishes an apt repo at dl.k6.io, but it needs a key fetched from an
# Ubuntu keyserver, and keyservers fail in exactly the annoying intermittent way
# that costs twenty minutes. The GitHub release tarball is the same pattern that
# already worked here for doctl and helm, so use that.
if command -v k6 >/dev/null 2>&1; then
  ok "k6 already installed: $(k6 version 2>/dev/null | head -1)"
else
  ktmp="$(mktemp -d)"
  trap 'rm -rf "$ktmp" "${htmp:-}" "${tmp:-}"' EXIT

  K6_VER="${K6_VER:-}"
  if [ -z "$K6_VER" ]; then
    k6_url="$(curl -fsSLI -o /dev/null -w '%{url_effective}' --max-time 30 \
      https://github.com/grafana/k6/releases/latest || true)"
    K6_VER="${k6_url##*/}"
  fi
  printf '%s' "$K6_VER" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+$' \
    || die "Could not resolve the latest k6 version (got '${K6_VER:-<empty>}').
       Pin one and re-run:  K6_VER=v1.3.0 scripts/install_tools.sh
       Releases: https://github.com/grafana/k6/releases"
  ok "Latest k6 is $K6_VER"

  karch="$(dpkg --print-architecture)"        # amd64 / arm64
  kdir="k6-$K6_VER-linux-$karch"

  curl -fsSL --max-time 120 -o "$ktmp/$kdir.tar.gz" \
    "https://github.com/grafana/k6/releases/download/$K6_VER/$kdir.tar.gz"

  tar -xzf "$ktmp/$kdir.tar.gz" -C "$ktmp"
  sudo install -m 0755 "$ktmp/$kdir/k6" /usr/local/bin/k6
  ok "k6 $(k6 version 2>/dev/null | head -1) installed to /usr/local/bin/k6"
fi

# -------------------------------------------------------------------- wire up
step "Next: point kubectl at the cluster"

cat <<EOF

  doctl kubernetes cluster kubeconfig save $CLUSTER
  kubectl get nodes
  kubectl -n drakkar get gateway drakkar

Then pick the HTTPS work back up:

  source ~/Sharkbite/env.sh && cd \$REPO
  STAGING=1 scripts/enable_tls.sh

EOF
