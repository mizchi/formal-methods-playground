# 4. ツールごとにできること

ここでは、ツールをアプリケーションエンジニアの作業に対応させて見る。

一覧で比較したい場合は、[ツールの得意不得意マップ](tool-fit-map.md) を見る。
そこに選定フローと Mermaid 図もまとめている。

## Z3 / SMT-LIB

できること:

- 条件の矛盾検出
- bad input の存在確認
- old-vs-new の差分 witness
- config / validator / policy の CI check

向く対象:

- `isAllowed(user, action, resource)`
- `isValidConfig(config)`
- `routeFor(request)`
- `isEligible(user, campaign)`

苦手なこと:

- 時間を通じた retry / crash / liveness
- 大きな heap / IO / framework 込みの実装そのもの

## Alloy

できること:

- RBAC、tenant、ownership の関係モデル
- workflow の到達不能状態検査
- network reachability / graph reachability
- 小さい world での反例探索

向く対象:

- 「非 admin が settings に到達できない」
- 「別 tenant の resource を読めない」
- 「service A から DB に直接到達できない」

苦手なこと:

- fairness を含む liveness
- 大規模で長い trace の網羅

## FizzBee

できること:

- Python/Starlark 風の design pseudocode と `role` / RPC
- atomic、serial、parallel action の interleaving
- safety assertion、LTL subset、action/choice fairness
- state graph、sequence diagram、whiteboard による設計レビュー
- durable/ephemeral state と暗黙の fault injection
- 同じ model から model-based testing、確率・性能 modeling へ進む workflow

向く対象:

- distributed system / microservice の設計書
- retry、queue、RPC、gossip、replication、two-phase commit
- crash / message loss / network partition を含む failure design
- Python 風の擬似コードを設計の正本にして実装テストへ接続する場合

苦手なこと:

- 静的型を contract にしたい場合
- theorem proving、高度な refinement、成熟した module ecosystem
- 単純な predicate や relation だけの検査
- production implementation そのものの証明

## Quint

できること:

- sum type、record、map を使った型付き domain state
- `init` / `step` と `all` / `any` / `nondet` による実行可能な状態遷移
- safety invariant と fairness を含む liveness property
- REPL、run、test による例示と、TLC / Apalache backend による model check
- Choreo による distributed protocol scaffold
- ITF trace、Trace Explorer、Rust向けQuint Connectによるmodel-based testingへの接続

向く対象:

- order / job / session lifecycle
- saga、retry、timeout、queue、outbox
- application-level protocol contract
- state machine を実装から独立した domain DSL として維持する場合

苦手なこと:

- 単純な入力 predicate や構造だけの relation
- production implementation そのものの検証
- TLAPS を使う theorem proving や高度な TLA+ refinement

LLM Kit、Choreo、Connect、Trace Explorerの役割とproof boundaryは
[`Quintの周辺ツール`](../docs/quint-ecosystem.md)を参照する。

## TLA+

できること:

- action interleaving の網羅
- retry / timeout / crash / recover の safety
- eventual consistency や delivery の liveness
- queue / worker / state machine の trace 反例

向く対象:

- outbox pattern
- payment retry
- event sourcing
- actor mailbox
- leader election / distributed lock

苦手なこと:

- 単純な述語検査
- role / ownership の構造だけの問題

この repo では [`OrderCheckout`](../languages/fizzbee/README.md) を TLA+、Quint、FizzBee で
書き、同じ 20 の抽象状態と反例を比較している。Python 風の擬似コード・図・fault/MBT
workflow なら FizzBee、型検査・REPL・test なら Quint、既存 TLA+ ecosystem や TLAPS を
直接使うなら TLA+ が自然である。

## P

できること:

- typed message を持つ actor model
- state machine と monitor による safety check
- 実装に近い protocol model

向く対象:

- service 間 protocol
- device / driver / controller
- actor runtime に寄せた workflow

苦手なこと:

- 純粋な数式・設定矛盾だけの検査
- 汎用 theorem proving

## Dafny

できること:

- precondition / postcondition
- loop invariant
- ghost state
- sequential algorithm の正しさ

向く対象:

- parser / normalizer
- pricing / discount 計算
- validator
- business rule 関数

苦手なこと:

- distributed protocol
- production code をそのまま検査すること

## MoonBit `moon prove`

できること:

- MoonBit 関数の `proof_require` / `proof_ensure`
- loop invariant
- `.mbtp` の proof-only model
- data structure の representation invariant

向く対象:

- MoonBit で書いた validator / library
- domain operation
- finance rule
- data structure API

苦手なこと:

- Z3 のような `get-model` witness 取得
- TLA+ のような temporal interleaving

## Lean 4 / Rocq

できること:

- bounded scope ではない普遍定理
- 帰納的 data type 上の証明
- 数学的構造の証明
- 実装から独立した長寿命の proof artifact

向く対象:

- permission lattice の単調性
- protocol の数学的 lemma
- compiler / semantics
- concurrent separation logic が必要な低レイヤ

苦手なこと:

- アプリの config bug を素早く見つけること
- domain owner にそのまま見せる反例生成

repo 内の例:

- Lean: [`languages/lean/Rbac.lean`](../languages/lean/Rbac.lean)
- Rocq: [`languages/rocq/StackCompiler.v`](../languages/rocq/StackCompiler.v)
- Rocq negative control: [`languages/rocq/BrokenStackCompiler.v`](../languages/rocq/BrokenStackCompiler.v)
