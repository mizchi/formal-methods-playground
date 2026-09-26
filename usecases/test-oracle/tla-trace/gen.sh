#!/usr/bin/env bash
# TLC の反例を取り直す (nix develop の中で実行する)
set -euo pipefail
cd "$(dirname "$0")"
for name in late blocking; do
  (cd ../../../languages/tla && tlc -config "IdempotentRetry_${name}.cfg" IdempotentRetry.tla) > "${name}.out" 2>&1 || true
done
