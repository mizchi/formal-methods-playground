#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# Only the verdict lines are compared; get-value witnesses may vary by Z3 version.
actual="$(z3 -smt2 targeting.smt2 | grep -E '^(sat|unsat)$')"
expected="$(printf 'unsat\nunsat\nunsat\nsat\nunsat\nunsat\nsat\nunsat\nsat')"

if [[ "$actual" != "$expected" ]]; then
  printf 'unexpected z3 result for usecases/campaign-targeting/targeting.smt2\n' >&2
  printf 'expected:\n%s\n' "$expected" >&2
  printf 'actual:\n%s\n' "$actual" >&2
  exit 1
fi

printf '%s\n' "$actual"
