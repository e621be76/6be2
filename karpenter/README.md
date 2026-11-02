# Part 5a: Karpenter for GPU inference

API: `karpenter.sh/v1` NodePool and `karpenter.k8s.aws/v1` EC2NodeClass, checked against the
**v1.15.1** CRDs (latest release when written). `scripts/51-validate-karpenter.sh` installs those CRDs into
the local cluster and runs `kubectl apply --dry-run=server`, so the API server validates the schema and the CEL rules.

| File | What |
|---|---|
| `gpu-nodeclass.yaml` | AL2023 (NVIDIA variant picked automatically), 200Gi gp3 root for model images, IMDSv2 with hop limit 1 |
| `gpu-nodepools.yaml` | `gpu-spot` (weight 100) and `gpu-on-demand` (weight 10), same shape, `nvidia.com/gpu=true:NoSchedule` taint, `WhenEmpty` consolidation, business-hours disruption freeze, GPU/CPU/memory limits |
| `inference-deployment.yaml` | example workload: toleration + selector, `karpenter.sh/do-not-disrupt`, grace period sized to the 2-minute spot notice |

Why `WhenEmpty`: `WhenEmptyOrUnderutilized` would bin-pack by evicting running inference pods to save a node.
For GPU nodes that means dropped requests and minutes of model reload. Nodes are reclaimed only once empty;
`do-not-disrupt` additionally protects pods from drift/expiry replacements.

## Spot vs on-demand for AI inference

Spot GPUs are typically 60–70% cheaper, but an instance can be reclaimed with two minutes' notice, and
inference pods have slow cold starts (pulling multi-GB images and loading weights into GPU memory can take
longer than the notice period). Spot fits horizontally scaled, stateless inference behind a load balancer, where
losing one replica only lowers capacity. Run enough replicas spread over several instance families/AZs, set
`terminationGracePeriod` so in-flight requests drain, and keep image/weight caching warm so replacements come
up fast. Latency-SLO-critical or single-replica models, long-running batch jobs without checkpoints, and scarce
instance types (where spot capacity simply isn't there) belong on on-demand. The setup here does both: spot is tried first
(weight 100), on-demand is the automatic fallback when spot capacity is unavailable, with a smaller cap so the
expensive path can't run away.
