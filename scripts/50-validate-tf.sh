#!/usr/bin/env bash
# Part 5b: terraform fmt -check, init -backend=false, validate for the Cloudflare config (no credentials needed)
# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

cd /work/terraform
# keep provider downloads out of the bind-mounted repo (would be root-owned on the host)
export TF_DATA_DIR=/tmp/tf-data

log "terraform fmt -check"
terraform fmt -check -recursive -diff
log "terraform init -backend=false"
terraform init -backend=false -input=false -lockfile=readonly
log "terraform validate"
terraform validate
