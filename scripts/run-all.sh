#!/usr/bin/env bash
# run every numbered script in order from the host; each one re-execs itself inside the toolbox
set -euo pipefail
cd "$(dirname "$0")"

for s in 00-cluster.sh 20-deploy.sh 25-reclaim-drill.sh 30-troubleshoot.sh 50-validate-tf.sh 51-validate-karpenter.sh; do
  printf '\n\033[1;32m######## %s ########\033[0m\n' "$s"
  ./"$s"
done

if [ -z "${IN_TOOLBOX:-}" ]; then
  printf '\n\033[1;32m######## curl from the host ########\033[0m\n'
  curl -fsS "http://localhost:${HOST_PORT:-8080}/api/quote"
  echo
fi
echo "all scripts passed"
