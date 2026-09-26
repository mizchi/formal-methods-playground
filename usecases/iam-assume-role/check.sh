#!/usr/bin/env bash
# Terraform の IAM 定義 -> plan JSON -> Alloy の事実 -> 検査、を 2 つの設定で回す。
# plan.json は保存してあるので、tofu (または terraform) が無くても検査だけは回せる。
#   ./check.sh          保存済みの plan.json で検査する (alloy6 が要る)
#   ./check.sh --plan   tofu で plan.json を作り直してから検査する
set -euo pipefail
cd "$(dirname "$0")"
TF="${TF:-tofu}"
for dir in escalates fixed; do
  if [[ "${1:-}" == "--plan" ]]; then
    (cd "$dir" && "$TF" init -input=false >/dev/null && AWS_EC2_METADATA_DISABLED=true "$TF" plan -input=false -refresh=false -out=plan.bin >/dev/null && "$TF" show -json plan.bin > plan.json)
  fi
  python3 extract.py "$dir/plan.json" > iam_facts.als
  echo "== $dir"
  # alloy6 exec は、check が反例を見つけると 0 以外で終わるので、出力だけを見る
  out="$(alloy6 exec -f --command '*' iam_check.als 2>&1 || true)"
  grep -E 'SAT|UNSAT' <<<"$out"
done
rm -f iam_facts.als
