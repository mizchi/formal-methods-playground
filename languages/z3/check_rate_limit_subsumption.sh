#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

actual="$(z3 -smt2 languages/z3/rate_limit_subsumption.smt2)"
expected="$(printf 'unsat\nunsat\nsat')"

if [[ "$actual" != "$expected" ]]; then
  printf 'unexpected z3 result for languages/z3/rate_limit_subsumption.smt2\n' >&2
  printf 'expected:\n%s\n' "$expected" >&2
  printf 'actual:\n%s\n' "$actual" >&2
  exit 1
fi

printf '%s\n' "$actual"
