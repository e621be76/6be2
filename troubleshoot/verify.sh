#!/usr/bin/env sh
# DevOps Assignment — Part 3 verifier.
# Run after applying your fixes. Prints PASS only when everything is healthy.
set -u

NS=troubleshoot
DIR=$(dirname "$0")
fail() { echo "FAIL: $1"; exit 1; }

echo "[1/7] default-deny NetworkPolicy must still exist (deleting it is not a fix)..."
kubectl get networkpolicy default-deny -n "$NS" >/dev/null 2>&1 \
  || fail "NetworkPolicy 'default-deny' not found in namespace '$NS'"

echo "[2/7] Node labels and taints must be untouched (fixing the nodes is not a fix)..."
SPOT_COUNT=$(kubectl get nodes -l acme.io/capacity=spot --no-headers 2>/dev/null | wc -l | tr -d ' ')
OD_COUNT=$(kubectl get nodes -l acme.io/capacity=on-demand --no-headers 2>/dev/null | wc -l | tr -d ' ')
GPU_NODE=$(kubectl get nodes -l acme.io/node-type=gpu -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
[ "$SPOT_COUNT" -ge 2 ] || fail "expected >=2 nodes labeled acme.io/capacity=spot (found $SPOT_COUNT)"
[ "$OD_COUNT" -ge 1 ] || fail "expected >=1 node labeled acme.io/capacity=on-demand (found $OD_COUNT)"
[ -n "$GPU_NODE" ] || fail "no node labeled acme.io/node-type=gpu"
kubectl get node "$GPU_NODE" -o jsonpath='{.spec.taints[*].key}' | grep -q "nvidia.com/gpu" \
  || fail "GPU node '$GPU_NODE' lost its nvidia.com/gpu taint (removing taints is not a fix)"

echo "[3/7] Deployment 'web' must be fully rolled out..."
kubectl rollout status deployment/web -n "$NS" --timeout=60s \
  || fail "deployment/web is not ready"

echo "[4/7] Deployment 'ai-inference' must be fully rolled out..."
kubectl rollout status deployment/ai-inference -n "$NS" --timeout=60s \
  || fail "deployment/ai-inference is not ready (Pending? check scheduling: selector + taint)"

echo "[5/7] ai-inference pod must be running ON the GPU node..."
AI_NODE=$(kubectl get pods -n "$NS" -l app=ai-inference -o jsonpath='{.items[0].spec.nodeName}' 2>/dev/null)
[ "$AI_NODE" = "$GPU_NODE" ] \
  || fail "ai-inference is on '$AI_NODE', expected GPU node '$GPU_NODE'"

echo "[6/7] Service must have ready endpoints..."
ENDPOINTS=$(kubectl get endpoints web-svc -n "$NS" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null)
[ -n "$ENDPOINTS" ] || fail "Service 'web-svc' has no endpoints (selector/targetPort?)"

echo "[7/7] In-cluster smoke test through the Service..."
kubectl delete job smoke-test -n "$NS" --ignore-not-found >/dev/null 2>&1
kubectl apply -f "$DIR/smoke-job.yaml" >/dev/null || fail "could not apply smoke-job.yaml"
i=0
while [ "$i" -lt 30 ]; do
  COND=$(kubectl get job smoke-test -n "$NS" -o jsonpath='{range .status.conditions[?(@.status=="True")]}{.type}{" "}{end}' 2>/dev/null)
  case "$COND" in
    *Complete*) break ;;
    *Failed*)
      echo "--- smoke-test logs ---"
      kubectl logs job/smoke-test -n "$NS" --tail=20 2>/dev/null || true
      fail "smoke test failed (check NetworkPolicy/DNS/Service path)"
      ;;
  esac
  sleep 2
  i=$((i + 1))
done
case "$COND" in
  *Complete*) : ;;
  *)
    echo "--- smoke-test logs ---"
    kubectl logs job/smoke-test -n "$NS" --tail=20 2>/dev/null || true
    fail "smoke test did not complete within 60s (check NetworkPolicy/DNS/Service path)"
    ;;
esac

echo ""
echo "PASS"
