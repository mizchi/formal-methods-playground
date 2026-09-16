#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

actual="$(z3 -smt2 languages/z3/schema_evolution.smt2)"
expected="$(printf 'sat\nsat\nunsat\nunsat\nsat\nunsat')"

if [[ "$actual" != "$expected" ]]; then
  printf 'unexpected z3 result for languages/z3/schema_evolution.smt2\n' >&2
  printf 'expected:\n%s\n' "$expected" >&2
  printf 'actual:\n%s\n' "$actual" >&2
  exit 1
fi

printf '%s\n' "$actual"
