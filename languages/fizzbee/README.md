# FizzBee: 実行可能な distributed design document

[`OrderCheckout.fizz`](OrderCheckout.fizz) は、
[`../tla/OrderCheckout.tla`](../tla/OrderCheckout.tla) と
[`../quint/OrderCheckout.qnt`](../quint/OrderCheckout.qnt) と同じ checkout lifecycle を
FizzBee で書いた probe である。

FizzBee は Starlark/Python 風の imperative syntax で、action、role、RPC、collection を
設計擬似コードに近い形で書く model checker である。atomic action だけでなく、yield を
含む serial action、role ごとの fairness、durable/ephemeral state、暗黙の fault injection を
持つため、分散システムの設計レビューと相性がよい。

## 検査する claim

- safety: cart に未知の商品が入らない
- safety: `refunded` flag は `REFUNDED` state でだけ立つ
- liveness: `PAYMENT_PENDING` は fair な決済 action によっていつか解消する
- negative control: unpaid cancel で `refunded = True` にすると invariant が破れる
- negative control: fairness がなければ pending のまま stutter できる

## 実行

```sh
nix develop
just check-fizzbee
```

個別に実行する場合:

```sh
fizz languages/fizzbee/OrderCheckout.fizz
```

FizzBee v0.5.2 の CLI は assertion 違反時にも終了コード `0` を返すため、
[`check-fizzbee.sh`](../../scripts/check-fizzbee.sh) は `FAILED:` と assertion 名を検査する。
正常モデルは 20 unique states を探索する。これは同じ抽象状態を使う TLA+/Quint probe と
一致する。

## TLA+、Quint、FizzBee の使い分け

| 観点 | FizzBee | Quint | TLA+ |
| --- | --- | --- | --- |
| 記法 | Python/Starlark 風の imperative design pseudocode | 型付きの式・action | 論理式を直接記述 |
| 状態型 | dynamic。enum は文字列の sugar | sum type、record、map を静的検査 | 通常は集合と `TypeOK` で記述 |
| 非 atomic 処理 | serial/parallel block の yield を直接記述 | action を小さい遷移へ分割 | action を小さい遷移へ分割、または PlusCal |
| 分散システム | role、RPC、channel、durable/ephemeral state、fault injection | 抽象 state/action contract | 任意の抽象 state/action と明示的な failure model |
| correctness | safety、LTL subset、fairness | safety/liveness、TLC/Apalache | safety/liveness、TLC/Apalache/TLAPS |
| 設計レビュー | state graph、sequence diagram、whiteboard | REPL、run、test、trace | Toolbox、TLC trace |
| 実装との接続 | 別配布の FizzBee MBT adapter | model から実装 contract を参照 | trace validation などを別途構築 |
| ecosystem | 新しく発展中。制約を確認して採用 | TLA ecosystem へ変換可能 | 最も成熟し、module・proof 資産が豊富 |

選択基準は次の通り。

- 設計書を Python 風の擬似コード、role/RPC、図としてレビューし、そのまま MBT や
  fault/performance model へ伸ばしたいなら FizzBee。
- 型付き domain contract と TLA semantics、REPL/test、TLC/Apalache を重視するなら Quint。
- TLAPS、高度な refinement、PlusCal、既存 module/tooling を重視するなら TLA+。

FizzBee は TLA+ の全用途を置き換えるものではない。一方、application/distributed-system の
設計 DSL としては、TLA+ より実装者が読みやすい擬似コードと可視化を正本にできる。

## 公式資料

- [Quick Start](https://fizzbee.io/design/tutorials/quick-start/)
- [Getting Started](https://fizzbee.io/design/tutorials/getting-started/)
- [Implicit Fault Injection](https://fizzbee.io/design/tutorials/fault-injection/)
- [Current Limitations](https://fizzbee.io/design/tutorials/limitations/)
- [Model-Based Testing](https://fizzbee.io/testing/)
