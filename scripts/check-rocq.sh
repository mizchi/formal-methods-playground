#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
rocq_dir="$repo_root/languages/rocq"

cd "$rocq_dir"

if grep -Eq '^[[:space:]]*(Admitted\.|Axiom[[:space:]])' Rbac.v StackCompiler.v; then
  echo "Rocq positive probes must not rely on Admitted or Axiom" >&2
  exit 1
fi

rocq compile Rbac.v
rocq compile StackCompiler.v

broken_output="$(mktemp)"
trap 'rm -f "$broken_output"' EXIT

if rocq compile BrokenStackCompiler.v >"$broken_output" 2>&1; then
  echo "expected BrokenStackCompiler.v to fail, but Rocq accepted it" >&2
  exit 1
fi

if ! grep -Fq 'Some [0]' "$broken_output" ||
   ! grep -Fq 'Some [3]' "$broken_output"; then
  echo "BrokenStackCompiler.v failed without the expected 0-versus-3 witness" >&2
  cat "$broken_output" >&2
  exit 1
fi

echo "Rocq positive checks passed: RBAC monotonicity and compiler correctness"
echo "Rocq negative control passed: reversed subtraction produced Some [0], expected Some [3]"
