# TLA+

TLA+ は、状態変数と action を定義し、起こりうる全順序を探索する道具である。

network、queue、retry、crash、eventual consistency のように、
時間と順序が bug を作る領域に向く。

## 最小チュートリアル

TLA+ の基本単位はこれだけである。

```text
VARIABLES state, queue

Init == 初期状態
Next == Action1 \/ Action2 \/ Action3
Spec == Init /\ [][Next]_vars
Invariant == 常に守ってほしい性質
```

checkout の状態遷移なら、次のように考える。

```text
state = "cart" -> "paymentPending" -> "paid" -> "shipped"
```

safety:

```text
NoShipWithoutPayment == state = "shipped" => payment = "succeeded"
```

liveness:

```text
PaymentResolves == state = "paymentPending" ~> state \in {"paid", "cancelled"}
```

`~>` を使うなら fairness が必要になる。
fairness がないと「何もしないで stutter し続ける」反例が合法になる。

repo の実行例:

```sh
tlc -config languages/tla/OrderCheckout.cfg languages/tla/OrderCheckout.tla
```

## 出力の読み方

| 出力 | 意味 |
| --- | --- |
| invariant violation | safety が破れた。trace が bug report |
| temporal property violation | liveness / fairness が足りない |
| deadlock | enabled action がなくなった。terminal state なら cfg で許可する場合もある |
| states generated | 探索した状態数。scope / 定数設定の妥当性を見る |

## レシピ

### outbox pattern の lost publish

置き換える作業:

- 「DB commit 後はいつか queue に publish されるはず」という設計レビュー

モデルにする state:

- `dbCommitted`
- `outboxWritten`
- `queuePublished`
- `crashed`

検査:

```text
CommittedOutboxEventuallyPublished
```

反例:

```text
commit -> crash before publish -> no recovery scan
```

### idempotency と二重決済

state:

- `seenRequestIds`
- `externalCharges`
- `orders`

safety:

```text
AtMostOnceCharge == externalCharges[requestId] <= 1
```

反例が出たら、conditional write、外部決済側 idempotency key、retry semantics を見る。

### background worker の stuck

state:

- `pendingJobs`
- `inFlight`
- `acked`
- `failed`

liveness:

```text
EveryPendingJobEventuallyResolved
```

fairness をどの action に置くかが設計判断になる。

### actor mailbox の FIFO

state:

- `mailbox[a]`
- `sent`
- `received`

safety:

```text
PerSenderFifo
```

P で実装に寄せる前に、TLA+ で抽象 protocol として検査するのも有効。

## 避ける使い方

- 単純な config 矛盾を TLA+ で書く
- すべての DB column を state variable にする
- liveness を書いたのに fairness を考えない
- terminal state の deadlock を bug か仕様か決めずに放置する

近い repo 例:

- [`../../languages/tla/OrderCheckout.tla`](../../languages/tla/OrderCheckout.tla)
- [`../../languages/tla/EventSourcing.tla`](../../languages/tla/EventSourcing.tla)
- [`../../languages/tla/ActorMailbox.tla`](../../languages/tla/ActorMailbox.tla)

## Quint で同じモデルを書く

Quint は TLA の semantics を、静的型、`all` / `any`、`nondet` などの
application engineer に馴染みやすい surface で書く言語である。
この repo では `OrderCheckout` を両方で実装し、同じ TLC backend で
safety と liveness を検査できるようにした。

- [Quint 版と TLA+ 版の対比](../../languages/quint/README.md)
- [Quint 版 `OrderCheckout.qnt`](../../languages/quint/OrderCheckout.qnt)
- [TLA+ 版 `OrderCheckout.tla`](../../languages/tla/OrderCheckout.tla)

## FizzBee で同じモデルを書く

FizzBee は同じ temporal state machine を Python/Starlark 風の imperative な
design pseudocode で書ける。`role` / RPC、非 atomic action の yield、fault injection、
state/sequence diagram、model-based testing まで設計 model を伸ばしたい場合に向く。

- [FizzBee / Quint / TLA+ の対比](../../languages/fizzbee/README.md)
- [FizzBee 版 `OrderCheckout.fizz`](../../languages/fizzbee/OrderCheckout.fizz)
