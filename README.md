# benchmark-compare TOCTOU + cache-poisoning — LAB

Reproduces, in **your own repos**, the chain found in `angular/angular`
(`.github/workflows/benchmark-compare.yml` → `ci.yml` `publish-snapshots`). It uses a
**fictional canary (`LAB_CANARY_7F3A`)**, **no real secrets**, and **no network
callbacks**. Nothing here is ever run against angular/angular — only against your lab repos.

## What it models (1:1 with the real anti-pattern)
1. `issue_comment` trigger → the job runs on the **default branch** with no fork-approval gate.
2. The PR head SHA is resolved **live at run time** (GraphQL), not pinned to what the
   reviewer saw → a race window (~13 s measured on the real run 29689973609).
3. The job checks out the fork at that live SHA and **runs the fork's code**
   (`benchmarks/run.sh`) in a context that holds secrets + cache write access.
4. That code can write a cache entry under the **prefix restore-key**
   `bazel-cache-Linux-` that `publish-snapshots` later restores and **executes**, so
   attacker code lands in the job that holds the (fictional) publish token.

The lab proves **arbitrary code execution in each privileged context** (canary files
`LAB-PROOF.txt` / `LAB-POISON-PROOF.txt`). It deliberately does **not** read, hash or
exfiltrate any secret — once code runs in a secret-holding job, secret access is a
well-understood consequence and does not need to be demonstrated with real tokens.

## Files
- `.github/workflows/benchmark-compare.yml` — victim/maintainer workflow (stage 1).
- `benchmarks/run.sh` — benign runner shipped on main (attacker overwrites it).
- `attacker/malicious-run.sh` — canary-only payload delivered on the raced commit.
- `attacker/race.sh` — attacker driver: watch PR, force-push on `/benchmark-compare `.
- `.github/workflows/cache-producer.yml` — stage 2a: write poisoned entry under prefix.
- `.github/workflows/publish-snapshots.yml` — stage 2b: restore + execute (holds token).

## Setup (two repos you own)
Maintainer/victim = `FazeMike1/benchmark-toctou-lab`. Attacker fork =
`mikethebest11-blip/benchmark-toctou-lab`.

1. Create `FazeMike1/benchmark-toctou-lab`, push this `lab/` content to `main`.
   (If `benchmarks/run.sh`, `attacker/*.sh` land without the executable bit, run
   `git update-index --chmod=+x benchmarks/run.sh attacker/malicious-run.sh attacker/race.sh`
   and push — the workflow also `chmod +x`es the runner itself, so this is cosmetic.)
2. On the victim repo set:
   - **Variable** `TEAM_MEMBERS` = `FazeMike1` (the "team" allowed to trigger).
   - **Secrets** `BENCH_RESULTS_TOKEN`, `BENCH_MEMBERSHIP_TOKEN`, `SNAPSHOT_BUILDS_TOKEN`
     = any **fictional** string such as `LAB_CANARY_7F3A_fake` (never a real PAT).
3. Fork to `mikethebest11-blip/benchmark-toctou-lab`, create branch `attack`, open an
   innocuous PR to the victim's `main`.

## Prerequisite: both repos PUBLIC
The vuln's precondition is that the fork is public (forks of a public repo are public),
so the victim's GITHUB_TOKEN can check it out. With private repos the checkout step fails
with `repository: null/null` / auth error. Make both public first (run in your own shell):
```
gh repo edit FazeMike1/benchmark-toctou-lab --visibility public --accept-visibility-change-consequences
gh repo edit mikethebest11-blip/benchmark-toctou-lab --visibility public --accept-visibility-change-consequences
```

## Run — stage 1 (TOCTOU code-exec)
IMPORTANT (Git Bash): prefix commands that pass `/benchmark-compare` with
`MSYS_NO_PATHCONV=1` or Git Bash rewrites the leading `/` into a Windows path and the
job's `if:` never matches.

Manual, deterministic race (no background poller needed, the 13 s window is wide):
```
# 1) attacker clone on 'attack', malicious commit staged locally but UNPUSHED
cd <attacker-clone>
git checkout attack && git reset --hard origin/attack
cp attacker/malicious-run.sh benchmarks/run.sh && git add benchmarks/run.sh && git commit -m "bench tweak"
# 2) member posts trigger, THEN attacker pushes within the 13 s window:
MSYS_NO_PATHCONV=1 gh api -X POST repos/FazeMike1/benchmark-toctou-lab/issues/1/comments -f body='/benchmark-compare main'   # as FazeMike1
git push -f origin attack                                                                                                     # as mikethebest11-blip
```
Or just use the driver: `VICTIM=FazeMike1/benchmark-toctou-lab PR=1 BRANCH=attack ./attacker/race.sh`
(run as the attacker; post the comment as FazeMike1 in another shell).

The victim workflow resolves the attacker's live SHA and runs it. Expect `LAB-PROOF.txt` /
`LAB_CANARY_7F3A executed` in the job log of the `benchmark-compare (LAB)` run.

## Run — stage 2 (cache poisoning → publish-snapshots)
1. Attacker code (stage 1) or the `cache-producer` workflow writes the poisoned entry
   under `bazel-cache-Linux-POISON-*`.
2. Trigger `publish-snapshots` (push to `main` or dispatch). Its prefix restore-key
   `bazel-cache-Linux-` serves the poisoned bazelisk, which runs in the job holding
   `SNAPSHOT_BUILDS_TOKEN`. Expect `LAB-POISON-PROOF.txt`.

## Caveats still to validate before any report
- GitHub Actions cache **immutability per key** and cross-ref scope rules: confirm the
  poisoned entry is actually served to the consumer in your lab (eviction / key-miss
  timing may matter; see Cacheract-style research).
- Scope/permissions of the real `BENCH_*` and `SNAPSHOT_BUILDS_GITHUB_TOKEN` — the lab
  does not assume any specific scope.
- OSS-VRP acceptance of a "team-member-triggered + TOCTOU" path (rules list TOCTOU as a
  valid bypass; the member-trigger precondition is the weakest link).
