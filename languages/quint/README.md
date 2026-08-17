# Quint と TLA+ の対比: OrderCheckout

[`OrderCheckout.qnt`](OrderCheckout.qnt) は、
[`../tla/OrderCheckout.tla`](../tla/OrderCheckout.tla) と同じ checkout workflow を
Quint で書いた probe である。

```text
Cart -> PaymentPending -> Paid -> Shipped
  |           |            |        |
  |           +-> Cart     +--------+-> Refunded
  |           +-> Cancelled
  +-> Cancelled
```

検査する claim も揃えている。

- safety: cart に未知の商品が入らない
- safety: `refunded` flag は `Refunded` state でだけ立つ
- liveness: `PaymentPending` は fairness の下でいつか解消する
- negative control: 壊れた cancel 遷移なら safety 違反の trace が出る
- negative control: fairness を外すと stuttering による liveness 違反が出る

## 実行

Nix dev shell には Quint と、Quint の TLC backend が使う TLA+ tools が入る。

```sh
nix develop
just check-quint
```

個別に試すなら次の通り。

```sh
quint typecheck languages/quint/OrderCheckout.qnt

quint verify languages/quint/OrderCheckout.qnt \
  --backend tlc \
  --main OrderCheckout \
  --invariant typeOk,refundedOnlyInRefundedState \
  --temporal paymentResolves
```

`just check-quint` はさらに `--step brokenStep` を指定する。これは cart の cancel 時に
誤って `refunded = true` にする negative control であり、
`refundedOnlyInRefundedState` 違反を見つけたときにテスト成功となる。
同様に `paymentResolvesWithoutFairness` が liveness 違反になることも確認する。

## 同じモデルの書き方

### 型と初期状態

TLA+ では値の集合と `TypeOK` を仕様中に書く。

```tla
States == {"cart", "paymentPending", "paid", "shipped", "refunded", "cancelled"}

TypeOK ==
    /\ state \in States
    /\ cart \subseteq Items
    /\ refunded \in BOOLEAN

Init ==
    /\ state = "cart"
    /\ cart = {}
    /\ refunded = FALSE
```

Quint では state の選択肢と変数型を宣言する。`OrderState` と `bool` の整合性は
`quint typecheck` が静的に検査するため、動的な `typeOk` は cart の domain だけを扱う。

```quint
type OrderState = Cart | PaymentPending | Paid | Shipped | Refunded | Cancelled

var state: OrderState
var cart: Set[str]
var refunded: bool

action init = all {
  state' = Cart,
  cart' = Set(),
  refunded' = false,
}
```

### action と非決定性

TLA+ の conjunction、disjunction、existential choice は、Quint ではそれぞれ
`all`、`any`、`nondet` になる。

```tla
AddItem(i) ==
    /\ state = "cart"
    /\ i \notin cart
    /\ cart' = cart \union {i}
    /\ UNCHANGED <<state, refunded>>

Next ==
    \/ \E i \in Items : AddItem(i)
    \/ Checkout
    \/ PaymentSucceeded
```

```quint
action addItem(candidate: str): bool = all {
  state == Cart,
  not(candidate.in(cart)),
  state' = state,
  cart' = cart.union(Set(candidate)),
  refunded' = refunded,
}

action step = {
  nondet candidate = items.oneOf()
  any { addItem(candidate), checkout, paymentSucceeded }
}
```

Quint の `x' = value` も imperative assignment ではなく、TLA+ と同じく
次状態の `x` に対する制約である。この例では state の対応を読み比べやすくするため、
変化しない変数も明示的に自己代入している。

### liveness と fairness

TLA+ は fairness を `Spec` に、検査対象を `.cfg` の `PROPERTY` に分けている。

```tla
Spec ==
    /\ Init
    /\ [][Next]_vars
    /\ WF_vars(PaymentSucceeded)
    /\ WF_vars(PaymentFailed)
    /\ WF_vars(PaymentTimeout)

PaymentResolves ==
    (state = "paymentPending") ~> (state \in {"paid", "cart", "cancelled"})
```

Quint では fairness assumption と leads-to を1つの temporal property に書ける。

```quint
temporal paymentResolves =
  and {
    paymentSucceeded.weakFair(vars),
    paymentFailed.weakFair(vars),
    paymentTimeout.weakFair(vars),
  }
    implies (state == PaymentPending leadsTo state.in(Set(Paid, Cart, Cancelled)))
```

fairness を外すと、`PaymentPending` で永遠に stutter する実行が許されるため、
どちらの表現でも liveness は成立しない。

## 使い分け

| 観点 | Quint | TLA+ |
| --- | --- | --- |
| semantics | TLA に基づく | TLA+ 本体 |
| 書き味 | 型付き、`all` / `any`、関数型言語に近い | 論理式を直接書く |
| 型エラー | `quint typecheck` で早く検出 | 通常は `TypeOK` と TLC で検出 |
| 対話的な探索 | REPL、run、test | Toolbox、TLC trace、PlusCal など |
| この例の model check | Quint から TLA+ に変換し TLC で検査 | TLC が `.tla` / `.cfg` を直接検査 |
| 高度な証明 | TLA+ に変換して既存 toolchain を使う | TLAPS などを直接使う |

最初の状態機械を application engineer が読み書きするなら Quint は入りやすい。
既存の TLA+ module、PlusCal、TLAPS、細かな TLC 設定を活かすなら TLA+ を直接使う。
この2ファイルは semantics の優劣ではなく、同じ問いに対する surface と workflow の
違いを比較するために置いている。

## 周辺tool

Quint LLM Kit、Choreo、Quint Connect、ITF出力、Quint Trace Explorerを含むlifecycleと
それぞれの信頼境界は、
[Quintの周辺ツール](../../docs/quint-ecosystem.md)に整理した。
[公式2PCを使った実動評価](../../docs/quint-ecosystem-evaluation.md)では、ChoreoからITFを生成し、
Trace Explorerで読み、Quint Connectが意図的に壊したRust実装を拒否するところまで再現している。

さらに、この`OrderCheckout`からITFを生成してreplayする
[MoonBit版runtime adapter `mizchi/quint_connect`](https://github.com/mizchi/quint-connect-moonbit)も独立repoへ追加した。公式Connectのmacro移植ではないが、
Quint process起動、複数trace、seed、nested projectionを含むruntime workflowと、action mapping / state
projectionという同じcontractで、正常実装と意図的に壊した実装を識別できる。

この`OrderCheckout`はplain Quintのprobeである。Choreoへ移植するより、まずnegative controlを
ITFへ出力し、Trace Explorerまたは実装言語のadapterで読むのが最小の次stepになる。
