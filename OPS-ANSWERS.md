# Part 7: Ops Answers

## 1. EKS 1.33 -> 1.35, zero downtime

EKS upgrades the control plane one minor at a time. Kubelet may stay behind the API server by up to 3 minors
-> nodes can stay on 1.33 until control plane is on 1.35, then we roll out once

1. **Prep (per upgrade cycle):** EKS Upgrade Insights + `kubent`/`pluto` for removed APIs; check every controller and webhook (ingress, cert-manager, Karpenter...) for a release that supports 1.35; PDBs exist and allow at least 1 disruption; rehearse on staging
2. **Control plane:** 1.33 -> 1.34 (in-place, API stays available; clients may see brief reconnects)
3. **Add-ons:** upgrade to their 1.34-compatible versions: vpc-cni first, then kube-proxy (never newer than the control plane), CoreDNS, EBS/EFS CSI
4. Repeat 2–3 for 1.35
5. **Data plane:** with Karpenter, bump the EC2NodeClass AMI alias; drift replaces nodes within the disruption budgets. With managed node groups, do a surge update. Spot pools first, on-demand and stateful last
6. Bump tooling, remove deprecated-API shims

**Top 3 risks**
- **Removed or changed APIs / incompatible operators:** a webhook that fails on the new API server can block all writes. Mitigation: scan beforehand, upgrade operators first, `failurePolicy: Ignore` on non-critical webhooks
- **Drains causing downtime:** workloads without PDBs or with a single replica, PDBs that block drains (`maxUnavailable: 0`), EBS-backed pods that can only reschedule in the same AZ. Mitigation: audit PDBs and replicas, surge capacity per AZ
- **Networking add-on regressions:** vpc-cni IP exhaustion while surging (2x pods for a while), CoreDNS config changes. Mitigation: check free subnet IPs/prefix delegation; watch DNS error rate and pod `ContainerCreating` counts during rollout

## 2. Spot reclaims paging at 3

Spot nodes going away is expected, approach this from the user impact perspective:

- **Handle the interruption properly:** Karpenter's interruption queue (or the Node Termination Handler) cordons and drains on the 2-minute notice, so the node leaves cleanly and the Node object is deleted. That alone removes most "unreachable" noise
- **Split by capacity type:** `KubeNodeUnreachable` for `acme.io/capacity=on-demand` (and control-plane-critical nodes) still pages, after `for: 5m`. For spot: inhibit via Alertmanager when a `SpotInterruptionReceived` alert (from the Karpenter metric) exists for the same node; otherwise route to a ticket with `for: 15m` (a reclaimed node is normally deleted well within that)
- **Alerts that should page regardless of cause:** SLOs (error ratio / latency), `kube_deployment_status_replicas_unavailable > 0 for 10m` on tier-1 services, pods `Pending` > 10m (no capacity to replace), fleet-level alert like ">30% of spot capacity lost in 10 min" (likely problem with AZ)

-> Reclaim = no page; real failure (on-demand node down, replicas not recovering, users affected) pages

## 3. Cloudflare mobile Core Web Vitals diagnosis

1. **Inspect LCP:** CrUX/PageSpeed field data + a WebPageTest mobile run. See if TTFB (origin/cache) or rendering (JS/CSS, hero images) takes more time, should only fix caching if TTFB gets a big share of time
2. **Check Cloudflare HTML processing:**
   `curl -sI -H 'User-Agent: <mobile UA>' https://site/ | grep -iE 'cf-cache-status|cache-control|age|set-cookie|vary|cf-ray'`
   - `cf-cache-status: DYNAMIC` -> Cloudflare doesn't cache HTML by default; there must be a Cache Rule ("eligible for cache") for HTML paths
   - `MISS` every time / `Age` always 0 -> cached but likely split by key that varies (query strings, cookies, device type)
   - `BYPASS` -> the origin sent `Set-Cookie`, or `Cache-Control: private/no-store`, or a rule bypasses on a cookie
3. **Review rules:** later cache rule matches override earlier ones, leftover legacy Page Rules, "Bypass cache on cookie", cache key settings (device type, query string), Edge TTL "respect origin" vs override. Check on cache analytics (hit ratio for `text/html`)
4. **Check origin:** see origin headers: if it sends `Cache-Control: no-cache` from web framework, session cookies on anonymous pages. Check origin TTFB on cache miss, uncached visitors will hit that time
5. **Fix/monitor/verify:** make anonymous HTML cacheable (`s-maxage` + `stale-while-revalidate`, or an edge TTL in a Cache Rule, bypassing only on a real session cookie), purge on deploy; monitor LCP over the campaign period. Optimize hero image: `fetchpriority=high`, right size, use WebP if rendering costs time in step #1

## 4. EKS secret management

| | **External Secrets Operator + AWS Secrets Manager** | **Sealed Secrets / SOPS in git** |
|---|---|---|
| Source of truth | Secrets Manager (per account/region) | encrypted blobs in GitOps repo |
| Rotation | Rotate in AWS (incl. managed RDS rotation); ESO refreshes on an interval | re-encrypt + commit + sync for every rotation |
| Multi-cluster | each cluster reads the same secret by name with its own IAM role | per-cluster controller keys (Sealed) or KMS key management (SOPS) |
| Access control and audit | IAM per service account (EKS Pod Identity), CloudTrail per read | whoever can decrypt; git history keeps secrets forever |
| Failure mode | AWS API outage -> existing k8s Secrets keep working, only refresh stops | controller key loss -> nothing can be decrypted |

**Pick: ESO + Secrets Manager + EKS Pod Identity** 
For a startup with several production clusters:
 * Centralizes secret rotation + scoped access per apps + free auditing
 * GitOps repo only needs to hold `ExternalSecret` references
 * Reduce chance of someone accidentally committing secrets, especially when working hard and tired
