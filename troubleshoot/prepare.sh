#!/usr/bin/env sh
# DevOps Assignment — node preparation.
# Run ONCE after your cluster is up (call it from your compose bootstrap).
# Simulates our production nodepools on a local multi-node cluster:
#   - 2 spot nodes, 1 on-demand node (Part 2 placement)
#   - 1 GPU node, tainted (Part 3)
# Do NOT modify this script and do NOT remove the labels/taints it sets.
set -eu

# Worker nodes only (exclude control-plane / server nodes)
NODES=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.labels.node-role\.kubernetes\.io/control-plane}{"\n"}{end}' \
  | awk '$2 == "" {print $1}')

COUNT=$(echo "$NODES" | wc -l | tr -d ' ')
if [ "$COUNT" -lt 4 ]; then
  echo "ERROR: need at least 4 worker nodes (found $COUNT). Recreate your cluster with more agents (e.g. k3d cluster create --agents 4)." >&2
  exit 1
fi

i=0
for node in $NODES; do
  i=$((i + 1))
  case "$i" in
    1|2)
      echo "Labeling $node as SPOT"
      kubectl label node "$node" acme.io/capacity=spot --overwrite
      ;;
    3)
      echo "Labeling $node as ON-DEMAND"
      kubectl label node "$node" acme.io/capacity=on-demand --overwrite
      ;;
    4)
      echo "Labeling + tainting $node as GPU"
      kubectl label node "$node" acme.io/node-type=gpu --overwrite
      kubectl taint node "$node" nvidia.com/gpu=true:NoSchedule --overwrite
      ;;
    *)
      echo "Leaving extra node $node unlabeled"
      ;;
  esac
done

echo ""
echo "Node preparation done:"
kubectl get nodes -L acme.io/capacity -L acme.io/node-type
