#!/usr/bin/env bash
# Part 3: apply broken-app.yaml once (first run only, to show the broken state), apply fixed-app.yaml,
# wait for rollouts, then run the provided verify.sh
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
wait_bootstrap

NS=troubleshoot
T=/work/troubleshoot

# re-applying the broken file on re-runs would roll the fixed pods back, so only do it on a fresh cluster
if ! kubectl get namespace "$NS" >/dev/null 2>&1; then
  log "applying broken-app.yaml as provided"
  kubectl apply -f "$T/broken-app.yaml"
  sleep 20
  log "broken state"
  kubectl -n "$NS" get pods -o wide
  kubectl -n "$NS" get endpoints web-svc
fi

log "applying fixed-app.yaml"
kubectl apply -f "$T/fixed-app.yaml"

# verify.sh only waits 60s per rollout; a cold image pull can take longer than that
kubectl -n "$NS" rollout status deployment/web --timeout=300s
kubectl -n "$NS" rollout status deployment/ai-inference --timeout=300s
kubectl -n "$NS" get pods -o wide

log "running troubleshoot/verify.sh"
sh "$T/verify.sh"
