# Final Cost Analysis for Nordheim Online’s Drakkar Lite Cluster

Nordheim Online has requested that the deployment of Drakkar Lite achieve four pillars of value. Those pillars are:

1. Scalability: Handle growing workloads as they onboard new users.
2. Performance: Optimize the system to deliver fast response times.
3. Reliability: Ensure high application availability with minimal downtime.
4. Cost Optimization: Avoid unnecessary Cloud costs while maintaining performance.

In the proof-of-concept deployment, we have built a highly available, auto-scaling cluster that is load-balanced, performant, reliable, and cost-conscious, as this is a single-developer company with a tight budget for the SaaS application's deliverables.

Drakkar Lite is a proof of concept, the initial part of the plan to develop a larger SaaS presence. Recognizing the need to maintain cost controls for our client, I have analyzed the expected costs herein and can project current and projected operating costs. An exact accounting of the costs to date is provided herein.

## Costs to Date

Drakkar Lite is deployed on a two (2) node (2 CPU + 4GB) Cluster with a High Availability Control Plane, one (1) DigitalOcean Load Balancer, one (1) PostgreSQL DB node (1 CPU, 1GB), and one (1) Registry. The system is designed to Autoscale as necessary, up to a maximum of 3 nodes in the cluster. The application is available for review at <https://drakkar.nordheim.online>.

Of the $55.00 USD credits, the costs to date amount to $8.32 USD, or roughly $2.77/day. However, we have recently added the High Availability Control Plane for better control, bringing the expected daily cost to $4.16/day.

Given this, the POC credit is expected to be exhausted in 11.22 days. If the intent is to redeploy an actual non-POC, the system should be torn down within 10 days to ensure there are no additional costs to Nordheim Online.

## Projected and Potential Operating Costs

The monthly operating cost of the system as built, at DigitalOcean list prices, is:

| Resource | Specification | Monthly (USD) |
| --- | --- | --- |
| Kubernetes control plane | High Availability (99.95% SLA) | $40.00 |
| Worker nodes | 2 × s-2vcpu-4gb at $24.00 | $48.00 |
| Load Balancer | 1 node, created by the cluster Gateway | $15.00 |
| Managed PostgreSQL | db-s-1vcpu-1gb, 1 node | $15.15 |
| Container Registry | Basic | $5.00 |
| TLS certificate and DNS | Let’s Encrypt, Cloudflare DNS | $0.00 |
| **Baseline total** |  | **$123.15** |
| Third node (autoscaling, when busy) | 1 × s-2vcpu-4gb | +$24.00 |
| **Maximum as built** | 3 nodes | **$147.15** |

The projected operating costs for the system as built are therefore roughly $125 USD/month. That amounts to an estimated annualized cost between $1,500 and $1,766 USD/annum: the lower figure is the two-node baseline, and the upper figure assumes the autoscaler holds the third node all year. These costs are estimates and do not account for the system's growth rate or adoption by large numbers of users.

A conservative estimate of the system growth at a modest 10% would increase the budget modestly, but if the system were to suddenly grow at an exponential rate, then the estimates would be far below any actual costs.

Strictly for illustrative purposes, assuming a 40% growth in expenditure driven by elevated user engagement—which correlates with anticipated recurring revenue—the business could project annual operational expenses between $2,100 and $2,472 USD.

This projection represents a rough estimate rather than a binding quote, as future resource requirements cannot be definitively forecasted at this stage. Given that knowledge, a conservative estimate would allocate additional budget for operational costs. A 50% increase over the highest projected growth ($2,472 x 1.5 = $3,708 USD) here would prevent any unnecessary budget pain from becoming a surprise expense.

## How the Build Addresses Costs

Drakkar Lite is built on a 2-node Kubernetes Cluster that autoscales up to 3 nodes (max). For most user organizations, this should be sufficient. A single load balancer serves both the web pages and the API, keeping the system available to users in the event of a single-node failure. Adding load balancer nodes would add redundancy at the front door but would increase operating expenses.

The PostgreSQL DBMS node is a single node, as this should be sufficient to handle the projected size of organizations that would use the SaaS system for contact management. Costs for additional nodes are not shown, but adding a second (standby) node is expected to increase monthly operating expenses.

Integrating the High Availability Control Plane means that service disruptions trigger provider credits for Nordheim Online if DigitalOcean fails to satisfy its 99.95% uptime SLA. Organizations that forgo this control plane configuration receive no guarantee of service availability. DigitalOcean now enables the HA Control Plane by default on new clusters, and once enabled it cannot be turned off.

Additionally, the HA Control Plane keeps the Kubernetes API available during DigitalOcean’s platform maintenance and upgrades. Combined with the rolling updates and disruption budgets built into Drakkar Lite, this allows Nordheim Online to upgrade without downtime.

Lastly, the HA Control Plane ensures the following will continue to be available for Nordheim Online's clients:

* Autoscaling - will continue to work
* CI/CD pipelines will not fail (\*Note: we did not implement this here, due to company request, as GitHub Actions have become an unwanted expense)
* Self-healing - will continue to work as the HA Control Plane can reschedule activities to ensure continuous operations

The HA Control Plane is not free; it costs $40/month per cluster. It is the largest single cost addition to operational costs. However, the operational security provided by choosing the HA Control Plane is a wise choice when considering the actual costs of downtime in not only financial cost, but the operational, reputational, and business costs of an unavailable product with no SLA guarantees.

## Cost Conscious Decisions

Looking at the build out, we find that the product build out allows for operational growth and usage:

```
kubectl top nodes
NAME             CPU(cores)   CPU(%)   MEMORY(bytes)   MEMORY(%)
default-3y8xdn   123m         6%       1115Mi          37%
default-3y8xv9   104m         5%       1002Mi          33%
```

Memory is not taxed, and the system is not under any load at present. I do not recommend any immediate changes to the system build.

The system is securely served over SSL/TLS at <https://drakkar.nordheim.online>. An A record in Cloudflare DNS (DNS only, not proxied) points the name at the DigitalOcean Load Balancer. A free Let’s Encrypt certificate, obtained and automatically renewed by cert-manager within the cluster, secures the connection at the cluster’s Gateway. No paid certificate, DNS move to DigitalOcean, or additional load balancer was required, so there is no additional cost to Nordheim Online.

## Conclusion

By right-sizing the Proof-of-Concept deployment, Nordheim Online has built a scaled model of what can work for the production application. It is cost-effective, avoids overbuilding, and meets the deployment objectives. Trade-offs, where made, were thoughtfully addressed and delivered to meet the demands of the business. I look forward to your questions and discussion over the build as delivered.
