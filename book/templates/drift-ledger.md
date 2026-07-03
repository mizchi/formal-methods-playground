# テンプレート: drift ledger

形式モデルがすでにある状態で、仕様・コード・モデル・ログの drift を確認するときの台帳。

```text
claim_id:
  安定した ID。例: AUTHZ-SETTINGS-001, POLICY-MISSING-001。

source_of_truth:
  docs / ADR / API contract / code-as-de-facto / incident decision / unresolved。

spec_delta:
  docs やドメインルールの変更。ファイル path と行番号があれば書く。

code_delta:
  実装、テスト、config、schema、migration、ログ、trace の変化。

model_delta:
  形式ファイル、harness、expected-result、CI path、tool pin の変化。

check_command:
  実行したコマンド、または対応する CI job / URL。

previous_machine_result:
  以前の SAT/UNSAT/trace/proof/CI status。不明なら unknown。

current_machine_result:
  今回の SAT/UNSAT/trace/proof/CI status。未実行なら not-run。

drift_class:
  spec-drift / code-drift / model-drift / harness-drift /
  decision-drift / coverage-gap。

primary_drift_reason:
  なぜその class が primary なのか。accepted domain rule から外れている面を
  1 つ選び、他の変更は driver / secondary note として分ける。

witness:
  最小の入力、relation instance、event trace、log trace、proof failure。

domain_wording:
  ドメインの人が判断できる言葉で、何が起きるかを書く。

domain_question:
  owner に聞く質問。定理ではなく業務判断として書く。

recommended_fix_target:
  spec / code / model / harness / domain decision / multiple。

lock_update:
  CI guard、expected-result 更新、path filter、docs 更新、trace replay など。

epistemic_status:
  machine-confirmed / log-confirmed / diff-inferred / not-run。
```

## ドメイン語への変換例

避ける:

```text
NonAdminNeverAtSettings が UNSAT から SAT になった。
```

使う:

```text
Support が read-only Settings を開ける新仕様になったため、
「Admin 以外は Settings に到達できない」という古いモデルは強すぎる。
Support の読み取り到達を例外として認め、write action 禁止は別 property に分けるか?
```

避ける:

```text
Authz model が stale。
```

使う:

```text
実装は missing policy を temporary fallback として許可している。
docs と Z3 model は missing policy を fail-close として拒否する契約のまま。
policy store が落ちたとき、export を許可してよいか?
```

## 修正先の書き方

```text
仕様が正しく、コードが drift:
  コードを直し、既存 model result を regression guard として維持する。

コードが意図通りで、仕様が古い:
  docs を更新し、model を新しい契約へ更新する。

モデル抽象が古い:
  domain claim を弱めず、state / relation / event の粒度を更新する。

harness だけが壊れた:
  property は変えず、parser / tool pin / expected result / CI を直す。

判断が未決:
  witness を保存し、domain owner への質問を出してから修正する。
```

## 最小記入例

```text
claim_id: PAYMENT-IDEMPOTENCY-001
source_of_truth: docs + incident decision
spec_delta: 変更なし。同じ requestId は external charge 最大 1 回。
code_delta: 未確認。
model_delta: P model は NoDoubleCharge を持つが incident trace replay は無い。
check_command: not-run; planned `p replay traces/incident-2026-06-28.log`
previous_machine_result: PChecker 0 safety violations
current_machine_result: not-run
drift_class: coverage-gap
primary_drift_reason: 実ログを model に replay する経路が無く、前回 green では incident を説明できない。
witness: req-9 が ch_1 と ch_2 の 2 回 ExternalCharge された。
domain_wording: retry 後に同じ requestId へ外部決済が二重に発行される。
domain_question: WorkerTimeout 後の retry は既存 charge を返すべきか、再 charge を許すのか。
recommended_fix_target: trace replay harness。code は追加調査。
lock_update: incident trace replay を CI に追加し、NoDoubleCharge の expected violation を固定する。
epistemic_status: log-confirmed + not-run
```
