#!/usr/bin/env bash
# install ArgoCD and let it sync chart/ from this repo; ends with a curl through the ingress
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
wait_bootstrap

# the Application must point at a public repo; default to the origin of this clone (https form)
# read .git directly so the toolbox doesn't need git (+100 MB with perl)
REPO_URL=${REPO_URL:-$(awk '/^\[remote "origin"\]/{f=1; next} /^\[/{f=0} f && $1 == "url" {print $3}' /work/.git/config 2>/dev/null \
  | sed -E 's#^git@([^:]+):#https://\1/#' || true)}
# branch name, or the commit sha on a detached HEAD (ArgoCD accepts both)
REVISION=${REVISION:-$(sed 's#^ref: refs/heads/##' /work/.git/HEAD 2>/dev/null || echo HEAD)}
[ -n "$REPO_URL" ] || { echo "no git remote 'origin' found; set REPO_URL=https://github.com/<you>/<repo>" >&2; exit 1; }

log "installing ArgoCD"
helm repo add argo https://argoproj.github.io/argo-helm --force-update >/dev/null
helm upgrade --install argocd argo/argo-cd --version 10.11.6 \
  --namespace argocd --create-namespace \
  --set dex.enabled=false --set notifications.enabled=false \
  --wait --timeout 10m

log "applying Application: $REPO_URL @ $REVISION"
sed -e "s#REPO_URL#${REPO_URL}#" -e "s#REVISION#${REVISION}#" /work/argocd/quote-api.yaml | kubectl apply -f -

log "waiting for ArgoCD to sync and the app to become healthy"
kubectl -n argocd wait application/quote-api --for=jsonpath='{.status.sync.status}'=Synced --timeout=300s
kubectl -n argocd wait application/quote-api --for=jsonpath='{.status.health.status}'=Healthy --timeout=300s
# HPA starts the deployment at 1 replica and scales to minReplicas shortly after; it may be higher on a re-run
MIN=$(kubectl -n quote get hpa quote-api -o jsonpath='{.spec.minReplicas}')
for i in $(seq 90); do
  READY=$(kubectl -n quote get deployment quote-api -o jsonpath='{.status.readyReplicas}')
  [ "${READY:-0}" -ge "$MIN" ] && break
  [ "$i" = 90 ] && { echo "only ${READY:-0} of $MIN replicas ready after 180s" >&2; exit 1; }
  sleep 2
done
kubectl -n quote rollout status deployment/quote-api --timeout=180s

log "placement (at 3 replicas, expect 2 on spot and 1 on on-demand)"
kubectl -n quote get pods -o wide -l app.kubernetes.io/name=quote-api
kubectl get nodes -L acme.io/capacity -L acme.io/node-type

log "curl through ingress"
for i in $(seq 30); do
  curl -fsS "http://${LB}/api/quote" && echo && break
  [ "$i" = 30 ] && { echo "ingress never answered" >&2; exit 1; }
  sleep 2
done

echo "from the host: curl http://localhost:${HOST_PORT:-8080}/api/quote"
