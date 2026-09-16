#!/usr/bin/env bash
# Points both kustomizations at your DigitalOcean Container Registry and tag.
# Usage: scripts/set_registry.sh <registry-name> <tag>
#   e.g. scripts/set_registry.sh sharkbite v0.1.0
set -euo pipefail
cd "$(dirname "$0")/.."
REG="${1:?usage: set_registry.sh <registry-name> <tag>}"
TAG="${2:?usage: set_registry.sh <registry-name> <tag>}"

for f in k8s/kustomization.yaml k8s/migrate/kustomization.yaml; do
  python3 - "$f" "$REG" "$TAG" <<'PY'
import re, sys
path, reg, tag = sys.argv[1:]
text = open(path).read()
text = re.sub(r"newName: registry\.digitalocean\.com/[^/\s]+/", f"newName: registry.digitalocean.com/{reg}/", text)
text = re.sub(r"newTag: \S+", f"newTag: {tag}", text)
open(path, "w").write(text)
PY
  echo "updated $f"
done
grep -n -E 'newName|newTag' k8s/kustomization.yaml k8s/migrate/kustomization.yaml
