#!/usr/bin/env bash
# Benign benchmark runner shipped on the maintainer repo's main branch.
# The attacker's raced commit REPLACES this file with attacker/malicious-run.sh.
set -euo pipefail
echo "[benchmarks] running comparison for: ${1:-<none>}"
echo "[benchmarks] (benign) no results"

# benign tweak for benchmark comparison
