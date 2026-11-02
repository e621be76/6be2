# sourced by every numbered script: re-exec inside the toolbox when called from the host
if [ -z "${IN_TOOLBOX:-}" ]; then
  cd "$(dirname "$0")/.."
  tty=-T
  [ -t 0 ] && [ -t 1 ] && tty=
  exec docker compose exec $tty toolbox "/work/scripts/$(basename "$0")" "$@"
fi

set -euo pipefail

CLUSTER=quote
LB=k3d-${CLUSTER}-serverlb
export KUBECONFIG=/root/.kube/config

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

wait_bootstrap() {
  for _ in $(seq 120); do
    [ -f /tmp/bootstrap-done ] && return 0
    [ -f /tmp/bootstrap-failed ] && { echo "cluster bootstrap failed, see: docker compose logs toolbox" >&2; exit 1; }
    sleep 5
  done
  echo "timed out waiting for cluster bootstrap, see: docker compose logs toolbox" >&2
  exit 1
}
