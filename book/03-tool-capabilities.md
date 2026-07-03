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
