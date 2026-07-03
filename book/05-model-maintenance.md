# 6. モデルを維持する

形式モデルは作った時点ではなく、仕様・コード・運用ログが変わった後も同じ
主張を表しているときに価値がある。

この章では、`仕様 - コード - モデル` の drift を見つけ、機械結果を
ドメインの言葉に戻して、どこを直すか決める流れを扱う。

## 何が drift するのか

維持対象は、形式ファイルだけではない。1 つの claim を、少なくとも次の
三面で追跡する。

| 面 | 見るもの | 例 |
| --- | --- | --- |
| 仕様 | docs、ADR、API contract、runbook、incident decision | 「policy missing は fail-close」 |
| コード | 実装、テスト、設定、schema、ログ、trace | `if (!policy) return allow()` |
| モデル | Z3/TLA+/P/Alloy/Dafny など、harness、期待結果、CI | `missingPolicy => allowed == false` |

drift の種類は 1 つに決めてから直す。

| drift class | 意味 | 修正の向き |
| --- | --- | --- |
| `spec-drift` | ドメインルールが変わったが、コードやモデルが追従していない | 仕様変更を受け入れるならコード/モデルを更新 |
| `code-drift` | 仕様とモデルは同じなのに、実装や設定の挙動が変わった | 意図でなければコードを直す |
| `model-drift` | 仕様とコードは新ルールに揃ったが、モデルが古い | 性質を弱めず、モデル抽象を更新 |
| `harness-drift` | CI、parser、tool pin、expected result が壊れた | property を変えずに harness を直す |
| `decision-drift` | 過去のドメイン判断が曖昧化または矛盾した | owner に再確認する |
| `coverage-gap` | claim が仕様・コード・モデルの一面にしか無い | model/test/docs/non-goal を追加 |

重要なのは「どのファイルが先に変わったか」ではない。
現在受け入れられているドメインルールから、どの面が外れているかを見る。

## AI がやること、人間がやること

AI に任せてよいのは、既存の材料を対応付け、機械結果を人間が読める形に
翻訳する作業である。

- docs / code / model / logs から claim を抜く
- claim に安定 ID を付ける
- どの checker / CI job / expected result が claim を守っているか探す
- `SAT`、`UNSAT`、反例 trace、proof failure、CI red をドメイン語に直す
- drift class と修正候補を台帳にする

人間が決めるべきなのは、正しさそのものである。

- そもそもその性質を保証したいのか
- 反例が business として許される例外なのか
- 仕様を直すのか、コードを直すのか、モデルを直すのか
- モデルの抽象粒度をどこまで細かくするのか
- 一時的な運用回避を契約として認めるのか

AI が「たぶん正しい」と言っても、solver / model checker / verifier が
確認していなければ machine-confirmed ではない。
人間が意図を決めていなければ、仕様として lock してはいけない。

## 維持の 1 周

```text
claim ID を選ぶ
  ↓
仕様・コード・モデル・ログを同じ claim に対応付ける
  ↓
既存の check command / CI job / expected result を確認する
  ↓
実行できるものは実行し、できないものは not-run として分ける
  ↓
drift class を 1 つ選ぶ
  ↓
機械結果や trace をドメイン語に翻訳する
  ↓
owner に「どこを正とするか」を確認する
  ↓
仕様 / コード / モデル / harness / CI / ledger を更新する
```

この流れでは、実行状態を混ぜない。

| status | 意味 |
| --- | --- |
| `machine-confirmed` | checker / verifier / CI が実際に判定した |
| `log-confirmed` | 本番ログや incident trace として観測済み |
| `diff-inferred` | diff から推測できるが、checker は未実行 |
| `not-run` | 実行すべき check がまだ走っていない |

`not-run` は失敗ではない。台帳に残し、次の lock 更新で CI や trace replay に
接続すればよい。

## ケース: config の fail-close が壊れた

仕様:

```text
policy document が missing / parse error / timeout の場合は fail-close。
fail-close とは対象 action を拒否すること。
```

Z3 model:

```text
missingPolicy => allowed == false
expected: UNSAT for missingPolicy && allowed
```

実装 diff:

```ts
const policy = await loadPolicy(user)
if (!policy) {
  return allow("temporary fallback")
}
return evaluate(policy, action)
```

ログ:

```text
user=U1 action=export policy=missing decision=allow reason=temporary fallback
```

台帳に戻すとこうなる。

```text
claim_id: POLICY-MISSING-001
source_of_truth: docs
spec_delta: 変更なし。missing policy は fail-close。
code_delta: missing policy を temporary fallback として allow している。
model_delta: 変更なし。Z3 は missingPolicy && allowed を forbid。
current_machine_result: not-run
drift_class: code-drift
witness: user=U1 action=export policy=missing decision=allow
domain_wording: policy が取れないユーザーが export を許可される。
domain_question: temporary fallback を正式仕様にするのか、fail-close に戻すのか。
recommended_fix_target: 意図しないなら code。意図するなら spec と model。
lock_update: Z3 check とこのログ trace を CI / regression guard に追加。
epistemic_status: log-confirmed + not-run
```

## ケース: モデルだけが古くなった

仕様が変わり、実装も追従した。

```text
Support は read-only Settings を開ける。
Support は write action はできない。
```

しかし既存モデルは次のままだった。

```text
assertion NonAdminNeverAtSettings:
  role != Admin => not Reachable(Settings)
```

CI は `role = Support`, `mode = readonly`, `screen = Settings` の witness を返す。
このとき、単に property を弱めて緑にしてはいけない。

ドメイン語ではこう言う。

```text
新仕様では Support の読み取り Settings 到達は許可された。
古い model は「Admin 以外は Settings に到達できない」と言っているため、
新仕様と実装に対して model が古い。
ただし write action 禁止は別 property として残す必要がある。
```

primary drift は `model-drift` であり、docs/code の変更は driver である。

## ケース: harness だけが壊れた

TLA+ / TLC の出力が次のように変わった。

```text
old: Model checking completed. No error has been found.
new: Finished in 3s at depth 12. No error has been found.
```

CI parser は古い文言だけを success とみなし、赤になった。
semantic result は同じく `No error has been found` である。

この場合、`NoDuplicateProcess` や `EventuallyProcessed` を変えない。
直すのは parser、expected result、tool pin、CI log parsing である。
drift class は `harness-drift` として扱う。

## 台帳を残す

維持作業の成果物は、説明文だけではなく台帳で残す。

- claim ID
- source of truth
- spec / code / model の delta
- check command
- previous / current machine result
- drift class
- witness
- domain wording
- domain question
- recommended fix target
- lock update
- epistemic status

テンプレートは [drift ledger template](templates/drift-ledger.md) に置く。
