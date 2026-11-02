# Part 4: GitLab CI -> GitHub Actions

`ci/legacy.gitlab-ci.yml` -> `.github/workflows/ci.yml`

## Changes

| Legacy | Now | Why |
|---|---|---|
| AWS access keys hardcoded in `variables:` | Removed, no use | Secrets in git = BAD. If later AWS is needed, use GitHub OIDC -> `aws-actions/configure-aws-credentials` assuming role |
| `sonar_check` with `allow_failure: true`, only on master, no gate wait | `sast` job: Semgrep with `--error` on every PR and push, required before image job | Scan has to be meaningful, why bother scanning if failures are fine? Semgrep needs no server or token for public repos and can scan rendered Helm chart |
| `npm test \|\| echo "tests flaky"` | `go vet` + `go test -race`, failure = job fails | Original can cause regressions, flaky tests should be fixed/quarantined instead of ignored globally |
| `node:16`, `docker:20.10`, `sonar-scanner 4.6`, `bitnami/kubectl:1.24` | Pin to commit SHA of current versions | Original uses EOL images, mutable tags = vulnerable to supply chain attacks. Semgrep's `github-actions` ruleset enforces SHA pins too |
| `npm install` | Go modules (no deps) | Reproducible builds (the npm equivalent would be `npm ci`) |
| `docker login -p $PASSWORD`, privileged docker-in-docker | `docker/login-action` with the job's `GITHUB_TOKEN`, BuildKit via `docker/build-push-action` | No password on the command line, no privileged service container, layer cache via `type=gha` |
| Push only `:latest` | `:sha-<short>` (immutable, deployed) + `:latest` (convenience) | `latest` can't be rolled back or audited + creating avenue for supply chain hijacks |
| `deploy_prod`: manual `kubectl set image` with a long-lived kubeconfig secret | `bump-chart` job commits the new tag to `chart/values.yaml`; ArgoCD syncs it | CI never holds cluster credentials. git is now deploy log, easy rollback with `git revert` |
| `only: master` everywhere | `pull_request` runs test/scan/build (no push); `push` to `main` also publishes | Catch problems in review instead of after merging |
| (new) | Trivy gate on fixable HIGH/CRITICAL in the image (bonus) | Catches vulnerable base images and Go stdlib versions before publishing with checksum-verified Trivy release binary (bad memories from hijacked GH Action incident) |
| (new) | `terraform fmt/validate` + `helm lint` | We have validators/linters for Terraform/Helm, why not? |
| (new) | Per-job `permissions:` (default `contents: read`) | Least privilege principle for `GITHUB_TOKEN`. Only image job can write packages and only bump-chart can push |

Skipped: bonus cosign signing task, I need to read up closely on it before deciding whether to go for it

## Migrating GitLab CI variables/secrets in a real project

1. List all variables: export project, group and instance variables (`GET /projects/:id/variables`, `GET /groups/:id/variables`). Record `protected` flag, `masked` flag and the environment scope of each variable
2. Remove keys replaced by OIDC: replace cloud keys (AWS, GCP, Azure) with OIDC federation and short-lived role credentials, replace registry passwords with `GITHUB_TOKEN` for GHCR, revoke old keys
3. Map secret scopes:
   - Put group variables into organization secrets, limit access to only necessary repos
   - Put protected/environment-scoped variables into environment secrets, add protection rules (required reviewers, branch limits)
4. Keep non-secret configuration in GitHub `vars` so they can be read in logs should an engineer need to
5. Load secrets into GitHub from a safe workstation with `gh secret set <NAME> --env <prod> < file` to avoid printing secrets to stdout
6. Rotate each secret at cutover, revoke old secret after the first successful run. DO NOT send live values through chat or tickets
