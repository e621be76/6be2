#!/usr/bin/env bash
# simulate a spot reclaim: drain a spot node running the app while a curl loop hits the ingress,
# show pods rescheduling, then uncordon (also on failure/ctrl-c). Fails if any request failed
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
wait_bootstrap

NS=quote
SEL=app.kubernetes.io/name=quote-api

pods() { kubectl -n "$NS" get pods -l "$SEL" -o wide --sort-by=.spec.nodeName; }

pod_nodes() { kubectl -n "$NS" get pods -l "$SEL" -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}'; }
nodes_in() { kubectl get nodes -l "acme.io/capacity=$1" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'; }

NODE=$(pod_nodes | grep -Fx -f <(nodes_in spot) | head -n1 || true)
[ -n "$NODE" ] || { echo "no app pod on a spot node; run 20-deploy.sh first" >&2; exit 1; }

LOOP=
cleanup() {
  if [ -n "$LOOP" ]; then kill "$LOOP" 2>/dev/null || true; fi
  log "uncordon $NODE"
  kubectl uncordon "$NODE"
}
trap cleanup EXIT

log "before: pods per node (reclaiming spot node $NODE)"
pods

log "starting curl loop through the ingress"
RESULTS=$(mktemp)
(
  while :; do
    code=$(curl -s -o /dev/null -m 2 -w '%{http_code}' "http://${LB}/api/quote" || true)
    echo "$code" >>"$RESULTS"
    sleep 0.2
  done
) &
LOOP=$!
sleep 3

log "draining $NODE (respects the PDB, like a 2-minute spot notice handled by a termination handler)"
kubectl drain "$NODE" --ignore-daemonsets --delete-emptydir-data --timeout=180s

log "waiting for replacements"
kubectl -n "$NS" rollout status deployment/quote-api --timeout=180s
sleep 5
kill $LOOP 2>/dev/null || true
wait $LOOP 2>/dev/null || true

log "after: pods per node ($NODE is cordoned)"
pods

TOTAL=$(wc -l <"$RESULTS" | tr -d ' ')
FAILED=$(grep -vc '^200$' "$RESULTS" || true)
log "requests during drill: $TOTAL, non-200: $FAILED"
sort "$RESULTS" | uniq -c

OD=$(pod_nodes | grep -cFx -f <(nodes_in on-demand) || true)
log "replicas on on-demand: $OD"

[ "$FAILED" = 0 ] && [ "$OD" -ge 1 ] || { echo "DRILL FAILED" >&2; exit 1; }
echo "DRILL PASSED"
