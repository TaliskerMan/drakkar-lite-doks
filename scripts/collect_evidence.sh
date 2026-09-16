#!/usr/bin/env bash
# Saves a snapshot of the cluster and DigitalOcean resources for the deck,
# the cost analysis and the QBR.
# Usage: scripts/collect_evidence.sh <label>
#   e.g. scripts/collect_evidence.sh idle
#        scripts/collect_evidence.sh under-load
# Env: CLUSTER (default drakkar-demo), NS (default drakkar)
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
LABEL="${1:-snapshot}"
CLUSTER="${CLUSTER:-drakkar-demo}"
NS="${NS:-drakkar}"
OUT="docs/results/$(date +%Y%m%d-%H%M%S)-$LABEL"
mkdir -p "$OUT"

run() { # run <file> <command...>
  local file="$1"; shift
  { echo "\$ $*"; echo; "$@"; } >"$OUT/$file" 2>&1 || echo "  (command failed; see $OUT/$file)"
}

run nodes.txt          kubectl get nodes -o wide
run top-nodes.txt      kubectl top nodes
run pods.txt           kubectl -n "$NS" get pods -o wide
run top-pods.txt       kubectl -n "$NS" top pods
run hpa.txt            kubectl -n "$NS" describe hpa drakkar-api
run pdb.txt            kubectl -n "$NS" get pdb
run deployments.txt    kubectl -n "$NS" get deploy -o wide
run services.txt       kubectl -n "$NS" get svc -o wide
run gateway.txt        kubectl -n "$NS" get gateway,httproute -o wide
run events.txt         kubectl -n "$NS" get events --sort-by=.lastTimestamp
run rollout.txt        kubectl -n "$NS" rollout history deploy/drakkar-api
run requests.txt       kubectl -n "$NS" get pods -o custom-columns='POD:.metadata.name,CPU_REQ:.spec.containers[*].resources.requests.cpu,MEM_REQ:.spec.containers[*].resources.requests.memory,MEM_LIM:.spec.containers[*].resources.limits.memory,NODE:.spec.nodeName'
run do-cluster.txt     doctl kubernetes cluster get "$CLUSTER"
run do-nodepools.txt   doctl kubernetes cluster node-pool list "$CLUSTER"
run do-lbs.txt         doctl compute load-balancer list
run do-databases.txt   doctl databases list
run do-registry.txt    doctl registry repository list-v2
run do-balance.txt     doctl balance get

echo "Saved $(ls "$OUT" | wc -l | tr -d ' ') files to $OUT"
