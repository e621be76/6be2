#!/usr/bin/env bash
# Part 5a: install the Karpenter v1 CRDs (CRDs only, no controller) and server-side dry-run the
# NodePools/EC2NodeClass, so the API server checks schema and CEL rules against the real API
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
wait_bootstrap

log "installing Karpenter CRDs 1.15.1"
helm template karpenter-crd oci://public.ecr.aws/karpenter/karpenter-crd --version 1.15.1 \
  | kubectl apply --server-side --force-conflicts -f -
kubectl wait --for=condition=Established crd/nodepools.karpenter.sh crd/ec2nodeclasses.karpenter.k8s.aws --timeout=60s

log "server-side dry-run"
kubectl apply --dry-run=server -f /work/karpenter/gpu-nodeclass.yaml -f /work/karpenter/gpu-nodepools.yaml
