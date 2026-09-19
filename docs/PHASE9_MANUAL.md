# Phase 9: the drills to watch live

Everything else in Phase 9 is automated — run `scripts/phase9.sh` for those.
These four you should sit and watch, because the *timeline* is the evidence and
you'll need to narrate it in the QBR and the deck.

Open two terminals. Start both with:

```bash
source ~/Sharkbite/env.sh && cd "$REPO"
export LB_IP=134.199.251.181
```

> Anything in `<angle brackets>` is a placeholder — substitute the real value.

---

## 9.6 · Node drain (upgrade simulation)

Proves the PDB and `maxUnavailable: 0` keep the app serving while a node goes
away — the same thing that happens during a real Kubernetes upgrade.

**Terminal A** — start the probe first:

```bash
scripts/rollout_check.sh http://$LB_IP 180 | tee docs/results/drain.txt
```

**Terminal B** — wait about 10 seconds, then pick the node running the most API
pods and drain it:

```bash
kubectl -n drakkar get pods -l app=drakkar-api -o wide

NODE=<node-name-from-above>
kubectl drain "$NODE" --ignore-daemonsets --delete-emptydir-data --timeout=180s \
  | tee docs/results/drain-events.txt

# Watch the pods reschedule onto the surviving node
kubectl -n drakkar get pods -o wide -w
```

Let the probe in Terminal A finish, then bring the node back:

```bash
kubectl uncordon "$NODE"
kubectl -n drakkar get pods -o wide | tee -a docs/results/drain-events.txt
```

**What good looks like:** `Done: N OK, 0 failed`. At least one API pod and one
web pod stay Ready throughout — that's the PodDisruptionBudget doing its job.

**Write down:** how long the drain took, whether any request failed (should be
zero), and how quickly pods rescheduled.

---

## 9.7 · HPA scale-out

The headline scalability evidence. You want the timeline, not just the endpoint.

**Terminal A** — start the watch before any load:

```bash
kubectl -n drakkar get hpa -w | tee docs/results/hpa-watch.txt
```

**Terminal B**:

```bash
scripts/load.sh 4 240
```

Then, once you see replicas climbing past 3:

```bash
scripts/collect_evidence.sh under-load
kubectl -n drakkar top pods | tee docs/results/top-under-load.txt
```

Leave the watch running for about 5 minutes *after* the load job ends so you
capture the scale-down too. Stop it with Ctrl-C.

**What good looks like:** 2 → up to 5 replicas, then back to 2 roughly a minute
after load stops. Node pool may go 2 → 3.

**Write down:** seconds from load start to the first new pod Ready; peak replica
count; seconds from load end to scale-down. The `hpa-watch.txt` timestamps give
you all three.

---

## 9.8 · Performance baseline (2 pods)

Make sure the cluster is back at 2 API replicas and idle before you start —
otherwise this isn't a baseline.

```bash
kubectl -n drakkar get hpa   # confirm REPLICAS is 2

command -v k6 >/dev/null || echo "k6 not installed — see 02_DEPLOYMENT_PLAN.md §Phase 0"

k6 run -e BASE=http://$LB_IP \
  --summary-export=docs/results/k6-read-baseline.json \
  scripts/k6-read.js | tee docs/results/k6-read-baseline.txt
```

**Target:** p95 under 300 ms, error rate under 1%.

**Write down the real numbers** — p50, p95, p99, requests/second, error rate.
Don't round them into the deck from memory; the plan is explicit that you only
claim what you measured.

---

## 9.9 · Performance while scaled out

```bash
scripts/load.sh 4 420

# Wait until the HPA shows 4–5 replicas
kubectl -n drakkar get hpa -w

# Then, with the load still running:
k6 run -e BASE=http://$LB_IP \
  --summary-export=docs/results/k6-read-scaled.json \
  scripts/k6-read.js | tee docs/results/k6-read-scaled.txt
```

**What this shows:** the comparison is the point. More replicas absorbing
background CPU load should hold p95 near baseline rather than degrading — that's
your scalability story in one chart.

**Write down:** the same five numbers, side by side with 9.8.

---

## 9.13 · Console screenshots

Save these next to `docs/results/` — the deck needs them and they can't be
captured from the CLI:

- [ ] DOKS **Insights** — CPU and memory across the scale-out window
- [ ] **Load balancer** — healthy nodes, plus throughput graphs during the k6 run
- [ ] **Database metrics** — connections (should stay ≤ 15 at 5 pods) and CPU
- [ ] **Container Registry** — both repos at `v0.1.0`, with image sizes
- [ ] **Billing** — month-to-date spend, and confirm the $50 credit appears
      under Billing → Credits
- [ ] **Spend alert** — confirm the 40/70/90% alert exists

---

## Closing out Phase 9

Phase 9 is done when every drill has a file or a screenshot, and these numbers
are written into your notes:

| Metric | Value |
|---|---|
| p50 / p95 / p99, baseline | |
| Requests/second, baseline | |
| Error rate, baseline | |
| p50 / p95 / p99, scaled | |
| Requests/second, scaled | |
| Scale-out: load start → new pod Ready | |
| Peak replicas | |
| Scale-down time after load | |
| Failed requests during rollout | should be 0 |
| Failed requests during drain | should be 0 |

Then:

```bash
git add docs/results docs/PHASE9_MANUAL.md scripts/phase9.sh
git commit -m "Phase 9: drill evidence and performance baselines"
git push
```

**Demo note for the walkthrough:** a browser reload signs you out, because the
web client holds the token in memory only. Use the ↻ button in the contacts list
to watch "served by" change while staying signed in. Worth saying out loud — the
API is stateless and sessions live in Postgres; persisting the token client-side
is a deliberate future change, not an oversight.
