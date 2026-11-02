#!/usr/bin/env bash
# delete the k3d cluster, then stop the toolbox; run from the host
set -euo pipefail
cd "$(dirname "$0")/.."
# k3d node containers are attached to the compose network, so they must go before `compose down`
docker compose exec -T toolbox k3d cluster delete quote || true
docker compose down
