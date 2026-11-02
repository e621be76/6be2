# Part 3: Troubleshooting

`troubleshoot/broken-app.yaml` had **9 independent faults** across the `web` Deployment, its Service,
the `ai-inference` Deployment and the NetworkPolicy setup

Most faults are consequential of their previous faults so they had to be fixed in order. I checked the
cluster after each fix before continuing
---

## web Deployment

### 1. ConfigMap name typo
- **Symptom:** both pods stuck in `ContainerCreating`
- **Diagnose:**
  ```bash
  kubectl -n troubleshoot describe pod -l app=web | grep -A2 Events   # or the events list above
  kubectl -n troubleshoot get configmap
  ```
  ```
  FailedMount  MountVolume.SetUp failed for volume "html" : configmap "web-conf" not found
  NAME         DATA
  web-config   1
  ```
- **Root cause:** the volume references `web-conf`; the ConfigMap is `web-config`. kubelet mounts volumes *before* pulling images -> fault #2
- **Fix:** `configMap.name: web-config`

### 2. Non-existing nginx image tag
- **Symptom:** new pod screams `ErrImagePull` -> `ImagePullBackOff`
- **Diagnose:** `kubectl -n troubleshoot describe pod <pod> | grep -A3 Failed`
  ```
  Failed to pull image "nginx:1.25.99": rpc error: code = NotFound desc = failed to pull and unpack image
  "docker.io/library/nginx:1.25.99": failed to resolve reference ...
  ```
- **Root cause:** `nginx:1.25.99` never existed, latest `1.25` was `1.25.5`
- **Fix:** use real `nginx:1.29.8-trixie` image tag pin

### 3. Probes checking on the wrong port
- **Symptom:** container starts, never becomes Ready, restarts every few seconds, then `CrashLoopBackOff`
- **Diagnose:**
  ```bash
  kubectl -n troubleshoot get pods -l app=web          # 0/1 Running, RESTARTS 2 (9s ago)
  kubectl -n troubleshoot describe pod <pod> | grep Unhealthy
  ```
  ```
  Liveness probe failed: Get "http://10.42.1.6:8080/": dial tcp 10.42.1.6:8080: connect: connection refused
  Readiness probe failed: Get "http://10.42.1.6:8080/": dial tcp 10.42.1.6:8080: connect: connection refused
  ```
- **Root cause:** both probes target `8080`; stock `nginx` listens on `80`
- **Fix:** probes on port `80`

### 4. Memory request of 16Gi can crash with `Insufficient memory`
- **Symptom:**
    - My dev machine: works because I have 128GB of memory
    - On a 8/16GB box: `Pending` with `Insufficient memory`.
- **Diagnose:**
  ```bash
  kubectl get nodes -o custom-columns=NODE:.metadata.name,ALLOCATABLE_MEM:.status.allocatable.memory
  ```
  ```
  k3d-quote-agent-0    131572488Ki     # every k3d node reports the *whole host's* RAM (125 GB here)
  ```
- **Root cause:** `requests.memory: 16Gi` is excessive for a static nginx page. k3d nodes advertise all host memory -> scheduler
can work with this excessive request, but a 16GB and lower box can't fit this request in. Excessive memory usage is wasteful and
likely to break CI boxes/smaller hosts; costly as well, memory is expensive nowadays
- **Fix:** `32Mi` request / `64Mi` limit, nginx is very efficient especially when serving a single static file

## web-svc Service

### 5. Selector doesn't match pods
- **Symptom:** Ready pods, but the Service has no endpoints
- **Diagnose:**
  ```bash
  kubectl -n troubleshoot get endpointslices -l kubernetes.io/service-name=web-svc
  kubectl -n troubleshoot get svc web-svc -o jsonpath='{.spec.selector}'
  kubectl -n troubleshoot get pods --show-labels
  ```
  ```
  web-svc-8cxpv   IPv4   <unset>   <unset>
  {"app":"webapp"}
  web-694cc5d858-6w9bx   app=web,pod-template-hash=694cc5d858
  ```
- **Root cause:** selector `app: webapp` vs pod label `app: web`
- **Fix:** selector `app: web`

### 6. targetPort points at a closed port
- **Symptom:** endpoints exist but connections are refused. After fixing #5 fixed EndpointSlice shows `PORTS 8080`
- **Diagnose:** the smoke Job and a throwaway client:
  ```bash
  kubectl -n troubleshoot get endpointslices -l kubernetes.io/service-name=web-svc   # PORTS 8080
  kubectl -n troubleshoot logs job/smoke-test
  ```
  ```
  curl: (7) Failed to connect to web-svc.troubleshoot.svc.cluster.local port 80 after 0 ms: Couldn't connect to server
  ```
- **Root cause:** `targetPort: 8080`; nginx listens on 80
- **Fix:** `targetPort: 80`

## ai-inference Deployment

### 7 + 8. Wrong selector key, no toleration for GPU taint
- **Symptom:** just `Pending` since starting
- **Diagnose:**
  ```bash
  kubectl -n troubleshoot get events --field-selector reason=FailedScheduling
  kubectl get nodes -L acme.io/node-type
  kubectl get node -l acme.io/node-type=gpu -o jsonpath='{.items[0].spec.taints}'
  ```
  ```
  0/5 nodes are available: 1 node(s) had untolerated taint(s), 4 node(s) didn't match Pod's node affinity/selector.
  [{"effect":"NoSchedule","key":"nvidia.com/gpu","value":"true"}]
  ```
  Scheduler reports both filters at once, have to read which node actually fails which filter because GPU node is
  excluded first by selector, then by taint
- **Root cause:** #7 selector is `node-type: gpu`, but `prepare.sh` labels `acme.io/node-type=gpu`, so no node matches.
  #8 GPU node is tainted `nvidia.com/gpu=true:NoSchedule`, and pod has no toleration
- **Fix:** use both `nodeSelector: {acme.io/node-type: gpu}` + toleration for `nvidia.com/gpu=true:NoSchedule` so that
  pod can get onto GPU node and selector can keep it off other nodes. After fixing: pod lands on `k3d-quote-agent-3`

## NetworkPolicy

### 9. `default-deny` with no allow rules
- **Symptom:** after fixing all previous problems, `verify.sh` step 7 (smoke Job) fails
- **Diagnose:** tested each rule in isolation with a client carrying the smoke Job's label:
  ```bash
  kubectl -n troubleshoot get networkpolicy           # only default-deny (podSelector {}, Ingress+Egress, no rules)
  kubectl -n troubleshoot run t --rm -i --restart=Never --image=curlimages/curl:8.7.1 --labels=app=smoke-client \
    --command -- sh -c 'curl -sS -m5 http://web-svc'
  ```
  | Policies | Result |
  |---|---|
  | `default-deny` only | `Failed to connect ... port 80 after 1 ms` (rejected by web's ingress) |
  | + DNS egress | same |
  | + DNS + egress to web | same: web's own ingress still denies |
  | + ingress on web from smoke-client | `TROUBLESHOOT-OK` |

  **Gotcha:** with only `default-deny`, client still resolved `web-svc` but failed DNS resolution a bit later:
  ```
  Address: 10.43.202.253                                   # first lookup, right after pod start
  ---after 20s
  ;; connection timed out; no servers could be reached    # same lookup once kube-router has synced
  ```
  k3s kube-router enforces a new pod's rules a few seconds after it starts -> some early traffic may slip through.
  DNS resolution may slip through before `default-deny` is enforced. If not careful, someone diagnosing this would
  see it work accidentally and get puzzled as to why it fails later
- **Root cause:** `default-deny` selects every pod and denies all ingress & egress
- **Fix:** add more policies on top of `default-deny`:
  - `smoke-client-allow-dns`: smoke-client -> `kube-system/k8s-app=kube-dns` on 53/UDP+TCP
  - `smoke-client-allow-web`: smoke-client -> `app=web` on 80/TCP
  - `web-allow-smoke-client`: `app=web` <- smoke-client on 80/TCP

  Ports are pod port (80), not Service port, because policies are evaluated after kube-proxy's DNAT
  Kubelet probes keep working under `default-deny` because kube-router allows traffic from a pod's own node

---

## Verification

```
$ ./scripts/30-troubleshoot.sh
...
[5/7] ai-inference pod must be running ON the GPU node...
[6/7] Service must have ready endpoints...
[7/7] In-cluster smoke test through the Service...

PASS
```

## Tiny issue found in provided package

`verify.sh` waits for only 60s per rollout; on a cold cluster nginx pull can exceed that. `30-troubleshoot.sh` waits up to 300s before calling `verify.sh`; I kept both of them unmodified
