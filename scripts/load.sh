#!/usr/bin/env bash
# Generates CPU load on the API from inside the cluster so the HPA scales out.
# Login attempts for a non-existent email still run a bcrypt check (so timing
# doesn't reveal which accounts exist); that makes them CPU-heavy, and they
# never trigger an account lockout.
# Usage: scripts/load.sh [workers] [seconds]      (defaults: 4 workers, 180 s)
# Watch:  kubectl -n drakkar get hpa,pods -w
set -euo pipefail
cd "$(dirname "$0")/.."

WORKERS="${1:-4}"
DURATION="${2:-180}"

kubectl -n drakkar delete job drakkar-load --ignore-not-found --wait=true >/dev/null
sed -e "s/__WORKERS__/${WORKERS}/g" -e "s/__DURATION__/${DURATION}/g" k8s/tools/load-job.yaml \
  | kubectl -n drakkar apply -f -

echo "Load running: ${WORKERS} workers for ${DURATION}s."
echo "Watch:      kubectl -n drakkar get hpa,pods -w"
echo "Stop early: kubectl -n drakkar delete job drakkar-load"
