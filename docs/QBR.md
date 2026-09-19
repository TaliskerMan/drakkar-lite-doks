# Drakkar Lite on DigitalOcean: Quarterly Business Review

**Customer:** Nordheim Online  
**Prepared by:** Chuck Talk, Technical Account Manager  
**Review period:** Proof of concept, September 16–19, 2026  
**Application:** <https://drakkar.nordheim.online>

## 1. Executive summary

- **Objective.** Prove that Drakkar Lite can run on DigitalOcean Kubernetes and meet Nordheim Online's four goals: scalability, performance, reliability and cost optimization.
- **Result.** The application is live over HTTPS on a two-node, autoscaling DOKS cluster with a high-availability control plane and a private managed PostgreSQL database. Every test run so far passed with zero failed requests.
- **Cost.** The build runs at $123.15 a month at list prices (about $4.16 a day), rising to at most $147.15 if the third node runs all month.

### Headline numbers

| Measure | Result | Evidence |
| --- | --- | --- |
| Response time, p95 | **132 ms** (target: under 300 ms). Median 84 ms, p90 124 ms. | k6-read-baseline.txt |
| Throughput | **39.9 requests/second** sustained, 50 simulated users for 5 minutes, 12,074 requests | k6-read-baseline.json |
| Error rate | **0.00%** (0 of 12,074 requests failed; 100% of checks passed) | k6-read-baseline.txt |
| Autoscaling (HPA) | **2 → 5 API pods** (the maximum) on the first scaling decision after load began, and back to 2 after the load stopped | hpa-watch.txt |
| Zero-downtime rollout | **275 requests, 0 failed** while every API pod was replaced | rollout-restart.txt |
| Self-healing | **205 requests, 0 failed** while a running pod was deleted and replaced | self-heal.txt |
| Node drain (upgrade simulation) | **Pending.** Not yet run. | To be captured |
| Monthly run rate | **$123.15/month** baseline; $147.15 maximum as built | Cost Analysis; cost-2026-09-18.txt |

## 2. What was delivered

- **DOKS cluster** (Kubernetes 1.36, New York region) with a **high-availability control plane** and 2 worker nodes that autoscale to 3.
- **Application:** 2 web pods and 2–5 API pods behind one DigitalOcean Load Balancer, created by a Kubernetes Gateway that routes `/v1/*` to the API and everything else to the web pages.
- **HTTPS:** a free Let's Encrypt certificate that cert-manager renews automatically. Plain HTTP redirects to HTTPS.
- **Database:** DigitalOcean Managed PostgreSQL, reachable only from the cluster over the private network, with encrypted connections and daily backups.
- **Tenant isolation:** each customer organization sees only its own data, enforced by the database itself.
- **Documentation:** setup guide, cost analysis and architecture diagram in the project repository.

## 3. Scorecard against the four goals

| Goal | Status | What the evidence shows | Open items |
| --- | --- | --- | --- |
| **Scalability** | Met | Under load, API CPU reached 866% of its request and the autoscaler went from 2 to 5 pods at once. It held at 5 while load continued and returned to 2 when load ended (hpa-watch.txt). The node pool is set to grow from 2 to 3 nodes. | Record how many seconds the scale-out takes. The third node has not yet been triggered in a test. |
| **Performance** | Met | p95 of 132 ms against a 300 ms target, 39.9 requests/second, 0% errors, over HTTPS with 50 simulated users (k6-read-baseline). | Capture p99 and a second run while scaled out to 5 pods. |
| **Reliability** | Met, one test pending | • Zero failed requests during a full rollout (275 OK) and during pod deletion (205 OK).<br>• Rollback to the previous version succeeded (rollback.txt).<br>• Disruption budgets keep at least 1 API and 1 web pod running (pdb.txt).<br>• HA control plane is on (do-cluster.txt). | Node-drain test not yet run. Both API pods were seen on the same node in two snapshots (see Recommendation R3). |
| **Cost optimization** | Met | At idle, nodes use 5–6% CPU and about a third of their memory; each API pod uses about 1 millicore and 11 MiB. One load balancer serves both tiers, and HTTPS added $0 (top-nodes.txt, top-pods.txt, Cost Analysis). | Consider right-sizing once real traffic data exists (R11). |
| *Security (supporting)* | Met | • All 13 HTTPS checks passed, including TLS 1.1 refused and HTTP redirecting (tls-check.txt).<br>• Row-level security is enabled and enforced on contacts and audit logs (rls.txt).<br>• Tenant isolation test passed (isolation.txt). | Recommendations R6–R8. |

## 4. Recommendations

Each item below is a decision for Nordheim Online. Nothing that adds cost will be switched on without your approval. Items marked **$0** use features already included in the current plan.

| # | Recommendation | Why it matters | Monthly cost | Suggested timing |
| --- | --- | --- | --- | --- |
| R1 | **HTTPS: closed.** Let's Encrypt certificate with automatic renewal, HTTP redirects to HTTPS. | The app is no longer served over plain HTTP. | $0 | Done Sept 18 |
| R2 | **Keep the HA control plane.** | It gives a 99.95% uptime SLA with service credits and keeps cluster management available during DigitalOcean maintenance. It is already on and cannot be turned off. | $40 (already in the run rate) | No decision needed |
| R3 | **Spread API pods reliably across nodes.** Make the spread rule required rather than preferred, and add the same rule for the web pods. | Two snapshots show both API pods on one node. If that node failed, the API would briefly be down. | $0 | Next release |
| R4 | **Finish the evidence set:** node-drain test, timed scale-out, p99, and a performance run while scaled out. | Confirms upgrade safety and gives a baseline for future reviews. | $0 | This week |
| R5 | **Add a database standby node.** This requires moving from the 1 GiB plan to a 2 GiB primary with a matching standby. | The database is the one component with no failover today. A standby takes over automatically if the primary fails. | About +$45 (from $15.15 to about $60) | Before the first paying customers |
| R6 | **Enable a PgBouncer connection pool** (DigitalOcean's built-in connection pooling). | The current plan allows 22 connections. Five API pods use 15, so raising the pod limit beyond 5 needs pooling first. | $0 | Before raising the pod limit |
| R7 | **Add Kubernetes NetworkPolicies** so each component accepts traffic only from the components that need it. | Limits how far a compromised pod could reach. | $0 | Next quarter |
| R8 | **Manage secrets outside the cluster.** Options: Sealed Secrets (encrypted secrets stored in Git, $0), or the External Secrets Operator connected to a secrets manager (the provider may charge). | Database passwords are currently created by hand. This makes rotation and rebuilds repeatable. | $0 (Sealed Secrets) or provider pricing | Next quarter |
| R9 | **Choose a CI/CD approach.** Not implemented, at Nordheim Online's request. Options: <br>a. Keep the current scripted manual releases.<br>b. GitHub Actions: standard runners are free for public repositories, and private repositories get a monthly allowance of free minutes.<br>c. A self-hosted runner on a machine you already own. | Automated builds and releases remove manual steps, which is where most release mistakes happen. | $0 for a, b (public repo) or c | Your choice; no change until approved |
| R10 | **Turn on alerting and scheduled upgrades.** DigitalOcean Monitoring alerts on node CPU and memory, plus certificate-expiry and uptime checks. Enable automatic Kubernetes patch upgrades in a chosen maintenance window (currently off). | Problems are found by alerts, not by customers, and security patches stay current. | $0 for Monitoring alerts; check pricing for uptime checks | Next month |
| R11 | **Review node size once real traffic exists.** Smaller s-2vcpu-2gb nodes would save $12 a month. | Idle usage is low, but memory would be tighter on 2 GB nodes. Decide from production data, not idle data. | Saves $12 | After 30 days of real use |

### Cost impact of the recommendations

| Scenario | Monthly (list price) |
| --- | --- |
| Current build, no changes | $123.15 (max $147.15 with the third node) |
| Approve all $0 items (R3, R4, R6, R7, R8 with Sealed Secrets, R9 a/b/c, R10 alerts) | $123.15 (no change) |
| Also approve the database standby (R5) | About $168 (max about $192 with the third node) |

## 5. Risks and mitigations

| Risk | What to watch | Mitigation | Status |
| --- | --- | --- | --- |
| Plain HTTP endpoint | — | Let's Encrypt via cert-manager, HTTP redirects to HTTPS | **Closed Sept 18** |
| Single database node | Database health alerts | Standby node (R5); daily backups with point-in-time recovery are already included | Open, awaiting decision |
| Running out of database connections | Connections approaching 22 | Pod limit held at 5 (15 connections); PgBouncer before raising it (R6) | Controlled |
| Both API pods on one node | Pod placement after rollouts | Required spread rule (R3) | Open, $0 fix |
| Manually managed secrets | Rotation audits | Sealed Secrets or External Secrets (R8) | Open |
| Manual releases | Failed or inconsistent deployments | Scripted release steps in the setup guide today; CI/CD by choice (R9) | Accepted by customer |
| Kubernetes version drift | DigitalOcean upgrade notices | Automatic patch upgrades in a maintenance window (R10); disruption budgets already in place | Open, $0 fix |
| Certificate renewal failure | Certificate "Ready" status, days to expiry | cert-manager renews at about day 60 of 90; add an expiry alert (R10) | Low |
| Traffic spike beyond 5 pods and 3 nodes | Autoscaler at its maximum, p95 rising | Raise the limits after R6, within an agreed budget | Monitored |

## 6. Decisions requested from Nordheim Online

1. Approve the $0 improvements: R3, R4, R6, R7, R10 alerts.
2. Choose a secrets approach (R8) and a CI/CD approach (R9), or keep the current manual process.
3. Decide whether and when to add the database standby (R5, about +$45/month).
4. Confirm the monthly budget ceiling for autoscaling. The current cap is 3 nodes, $147.15.

## 7. Next 90 days

| When | Activity |
| --- | --- |
| Weeks 1–2 | Complete the evidence set (R4); fix pod spreading (R3); turn on alerts and the maintenance window (R10) |
| Month 1 | Connection pool (R6); NetworkPolicies (R7); implement the chosen secrets approach (R8) |
| Month 2 | Implement the chosen CI/CD approach (R9); database standby if approved (R5) |
| Month 3 | Review 30+ days of real usage, right-size (R11), and hold the next business review |
