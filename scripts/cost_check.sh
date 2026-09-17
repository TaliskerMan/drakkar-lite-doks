#!/usr/bin/env bash
# Budget guard for the Drakkar Lite demo. Lists every billable resource,
# estimates the current burn rate, and compares month-to-date usage with
# the credit you're working within.
#
# Usage: scripts/cost_check.sh            (BUDGET defaults to 50)
#        BUDGET=50 SPENT_BEFORE=0 scripts/cost_check.sh
#   SPENT_BEFORE = month-to-date usage that was already there before this
#                  project started (so it isn't counted against the demo).
#
# Prices are DigitalOcean list prices checked 2026-09-15; adjust below if they change.
set -uo pipefail

BUDGET="${BUDGET:-50}"
SPENT_BEFORE="${SPENT_BEFORE:-0}"
CLUSTER="${CLUSTER:-drakkar-demo}"

NODE_HR=0.03571      # s-2vcpu-4gb ($24/mo)
NLB_HR=0.02232       # network load balancer, 1 node ($15/mo)
PG_HR=0.02254        # db-s-1vcpu-1gb, 1 node ($15.15/mo)
DOCR_HR=0.00694      # registry Basic ($5/mo, prorated daily)

echo "== Billable resources ($(date '+%a %b %d %H:%M'))"
echo "-- Kubernetes clusters";  doctl kubernetes cluster list --format Name,Region,Version,Status,NodePools 2>/dev/null || echo "   (none or doctl not authenticated)"
echo "-- Node pools ($CLUSTER)"; doctl kubernetes cluster node-pool list "$CLUSTER" --format Name,Size,Count,AutoScale,MinNodes,MaxNodes 2>/dev/null || echo "   (cluster not found)"
echo "-- Load balancers";        doctl compute load-balancer list --format Name,IP,Status 2>/dev/null
echo "-- Databases";             doctl databases list --format Name,Engine,Size,NumNodes,Status 2>/dev/null
echo "-- Volumes (should be empty)"; doctl compute volume list --format Name,Size,DropletIDs 2>/dev/null
echo "-- Droplets (should only be cluster nodes)"; doctl compute droplet list --format Name,Size,Status 2>/dev/null
echo "-- Registry";              doctl registry get 2>/dev/null || echo "   (none)"

nodes=0
if command -v kubectl >/dev/null 2>&1; then
  nodes=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
fi
lbs=$(doctl compute load-balancer list --format ID --no-header 2>/dev/null | grep -c . || true)
dbs=$(doctl databases list --format ID --no-header 2>/dev/null | grep -c . || true)
reg=$(doctl registry get --format Name --no-header 2>/dev/null | grep -c . || true)

burn=$(awk -v n="$nodes" -v l="$lbs" -v d="$dbs" -v r="$reg" \
  -v nh="$NODE_HR" -v lh="$NLB_HR" -v ph="$PG_HR" -v rh="$DOCR_HR" \
  'BEGIN{printf "%.4f", n*nh + l*lh + d*ph + r*rh}')

mtd=$(doctl balance get --format MonthToDateUsage --no-header 2>/dev/null | tr -d ' $' || echo 0)
mtd=${mtd:-0}

awk -v b="$burn" -v m="$mtd" -v s="$SPENT_BEFORE" -v B="$BUDGET" \
    -v n="$nodes" -v l="$lbs" -v d="$dbs" -v r="$reg" 'BEGIN{
  used = m - s; if (used < 0) used = 0
  left = B - used
  printf "\n== Burn rate: %d node(s), %d LB, %d DB, %d registry  ->  $%.3f/hour  ($%.2f/day)\n", n, l, d, r, b, b*24
  printf "== Month-to-date usage: $%.2f   (counted against budget: $%.2f of $%.2f)\n", m, used, B
  if (b > 0) printf "== At this rate the remaining $%.2f lasts about %.1f days\n", left, left/(b*24)
  if (used >= 0.8*B)      print "!! OVER 80% OF BUDGET: tear down now (02_DEPLOYMENT_PLAN.md Phase 12)"
  else if (used >= 0.5*B) print "!  Over 50% of budget: plan the teardown date"
  else                    print "OK: within budget"
  if (l > 1) print "!  More than one load balancer: delete the Plan B LB when it is not in use"
  if (n > 2) print "!  More than 2 nodes: fine during a scale test, but it should drop back to 2 when idle"
}'
