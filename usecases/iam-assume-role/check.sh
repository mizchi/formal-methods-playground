#!/usr/bin/env bash
# Terraform IAM definitions -> plan JSON -> Alloy facts -> checks, for two configurations.
# plan.json is committed, so the checks run without tofu (or terraform).
#   ./check.sh          check against the committed plan.json (needs alloy6 and python3)
#   ./check.sh --plan   regenerate plan.json with tofu first
set -euo pipefail
cd "$(dirname "$0")"
TF="${TF:-tofu}"
trap 'rm -f iam_facts.als' EXIT

expect() {
  local dir="$1" command="$2" verdict="$3" out="$4"
  if ! grep -Eq "[[:space:]]${command}[[:space:]].*[[:space:]]${verdict}$" <<<"$out"; then
    echo "Expected ${verdict} for ${dir} :: ${command}" >&2
    exit 1
  fi
}

for dir in escalates fixed; do
  if [[ "${1:-}" == "--plan" ]]; then
    (cd "$dir" && "$TF" init -input=false >/dev/null && AWS_EC2_METADATA_DISABLED=true "$TF" plan -input=false -refresh=false -out=plan.bin >/dev/null && "$TF" show -json plan.bin > plan.json)
  fi
  python3 extract.py "$dir/plan.json" > iam_facts.als
  echo "== $dir"
  # alloy6 exec exits non-zero when a check finds a counterexample, so judge by the output.
  out="$(alloy6 exec -f --command '*' iam_check.als 2>&1 || true)"
  grep -E 'SAT|UNSAT' <<<"$out"
  if [[ "$dir" == escalates ]]; then
    expect "$dir" NoEscalation SAT "$out"
  else
    expect "$dir" NoEscalation UNSAT "$out"
  fi
  expect "$dir" EntryReachesOtherRoles SAT "$out"
done
