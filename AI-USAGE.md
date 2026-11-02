# AI Usage

## Tools

- Claude Code with Opus 5.5 + Ponytail ultra mode harness (to focus on engineering the most minimal solutions possible)
- Human verified generated files, tested golden rule manually
- 5B Cloudflare task manually set up, verified, and torn down

## Prompts that pushed things

1. *"Go through ASSIGNMENTS.md and analyze requirements"*: to dissect and find potential problems with given assignments:
Golden Rule implying `run-all.sh` runs on the host (so scripts must re-exec into the toolbox), conflict between "prefer spot" and
"always one on on-demand"
2. *"Host does not have Docker/k3d"*: led AI to read provided files to find static faults first, before I added Docker to its toolkit,
so it identified all 9 part 3 faults before confirming each on a real k3d cluster. That also steered the AI to design harness so that
host needs nothing but Docker
3. *"Make working notes in NOTES.md"*: end-to-end implementation gets journaled, so user can verify each step done by AI manually should
one wants to

## Where AI was wrong and how it's caught

- Mutable GitHub Action tags: first workflow draft used `actions/checkout@v7`-style tags -> Semgrep added next failed all findings, served
  as feedback for AI to pin tags to commit SHAs
- Runtime shell bugs:
(a) `if (bootstrap); then` disables `set -e` inside the subshell
-> failed `k3d cluster create` would have been reported as successful
-> fixed by running bootstrap as a child process
(b) drill's node-picker ended a `while` loop with `[ … ] && echo`
-> under `pipefail` aborts the script whenever the last pod isn't on spot
-> replaced with `grep -Fx`.
(c) Missing git remote kills `20-deploy.sh` silently before erroring
AI caught its own failures for (a) and (b), I read the deploy script and found it before running
- Predicted Part 3 symptoms didn't all match: from reading manifest, AI predicted image pull failing first and 16Gi request leaving pods `Pending`.
On the cluster, ConfigMap mount failed first (kubelet mounts volumes before pulling images) and 16Gi pods were scheduled because each k3d node
reported the host's 128GB of RAM
-> had to rerun each fault, rewrite TROUBLESHOOTING from real output, decide to keep the 16Gi fix for lower spec boxes
- Semgrep false positive in Quote service: it caught `math/rand` in Go code for picking a quote, which is appropriate here (faster + 
just need PRNG to pick from a few quotes, not trying to generate secrets) -> annotated `nosemgrep` with reason instead
