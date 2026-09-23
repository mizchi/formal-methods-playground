# 7. 実例

この章は、実装から仕様を吸い出し、モデルに落とし、最後に
ドメイン語へ戻す具体例を置く。

## Z3: checkout form validator

実装:

- [`languages/moonbit/checkout_form/checkout_form.mbt`](../languages/moonbit/checkout_form/checkout_form.mbt)
- [`languages/z3/checkout_form.smt2`](../languages/z3/checkout_form.smt2)

実装から抜いた claim:

```text
valid checkout:
  total > 0
  and (
    physical order requires shipping
    or digital order requires non-empty email
  )
  and unknown kind is rejected
```

Z3 query:

- unknown kind が valid になるか -> `unsat`
- digital order が empty email で valid になるか -> `unsat`
- valid digital order の最小境界は到達可能か -> `sat`
- email guard を消した broken variant は bad input を通すか -> `sat`

ドメイン語への戻し:

```text
現実装は unknown kind を fail-close している。
現実装は digital order に non-empty email を要求している。
これは意図した API 契約か?
```

## Z3: schema evolution

実装に近い問い:

```text
rolling deploy 中に、新 pod が書いたレコードを旧 pod は受け取れるか?
旧 pod が書いたレコードを新 pod は受け取れるか?
受け取れたとして、旧 pod はそれを正しく扱うか?
```

repo 内の例:

- [`languages/z3/schema_evolution.smt2`](../languages/z3/schema_evolution.smt2)
- [`usecases/schema-evolution/`](../usecases/schema-evolution/)

Z3 が返すもの:

- 両方向それぞれの reject witness
- tolerant reader にしたときの `unsat`（互換が閉じたことの確認）
- パースは通るが誤った動作に至る witness（fail-open な fallback）

## Alloy: 認証・認可

実装に近い問い:

```text
user が所属していない tenant の resource を読める経路はあるか?
non-admin が settings に到達できる screen transition はあるか?
Cloudflare Workers の public route から production D1 / secrets に到達できるか?
```

repo 内の例:

- [`languages/alloy/app-rbac.als`](../languages/alloy/app-rbac.als)
- [`languages/alloy/multi-tenant.als`](../languages/alloy/multi-tenant.als)
- [`usecases/cloud-config-verification/cloudflare-workers-bindings.als`](../usecases/cloud-config-verification/cloudflare-workers-bindings.als)
- [`usecases/offline-sync-convergence/lww-merge.als`](../usecases/offline-sync-convergence/lww-merge.als) — 関係の全順序性として書いた収束性

Alloy が返すもの:

- 小さい user / org / resource / role の world
- どの relation が穴を作ったか
- domain owner に見せられる具体 instance

## Temporal models: FizzBee / Quint / TLA+

実装に近い問い:

```text
API -> DB -> outbox -> queue -> worker のどこで crash しても、
二重処理や lost update が起きないか?

P2P game の tick protocol で、commit/reveal/state hash が揃わない入力を
accepted にしていないか?

クラウドの rollout で、new target が健康かつ DB 互換になる前に
traffic が切り替わらないか?
```

repo 内の例:

- [`languages/tla/OrderCheckout.tla`](../languages/tla/OrderCheckout.tla)
- [`languages/tla/EventSourcing.tla`](../languages/tla/EventSourcing.tla)
- [`languages/tla/ActorMailbox.tla`](../languages/tla/ActorMailbox.tla)
- [`languages/tla/P2PGameProtocol.tla`](../languages/tla/P2PGameProtocol.tla)
- [`languages/tla/CloudRollout.tla`](../languages/tla/CloudRollout.tla)
- [`languages/quint/OrderCheckout.qnt`](../languages/quint/OrderCheckout.qnt)
- [Quint と TLA+ の `OrderCheckout` 対比](../languages/quint/README.md)
- [`languages/fizzbee/OrderCheckout.fizz`](../languages/fizzbee/OrderCheckout.fizz)
- [FizzBee / Quint / TLA+ の `OrderCheckout` 対比](../languages/fizzbee/README.md)
- [`usecases/p2p-game-cheat-detection/`](../usecases/p2p-game-cheat-detection/)
- [`usecases/cloud-config-verification/`](../usecases/cloud-config-verification/)
- [`usecases/idempotency-key/`](../usecases/idempotency-key/) — safety と liveness が別々に壊れる例
- [`usecases/write-skew-seat-limit/`](../usecases/write-skew-seat-limit/) — isolation level を定数にして 3 設計を比べる例
- [`languages/tla/SeatLimitTrace.tla`](../languages/tla/SeatLimitTrace.tla) — 同じモデルに本番ログを流して、主張した isolation level と実測を突き合わせる例（T5）

temporal model checker が返すもの:

- action 名付きの trace
- stuck する state
- safety violation
- fairness が足りない liveness failure

## P: actor protocol

実装に近い問い:

```text
typed message を投げ合う actor が、どの schedule でも monitor の safety を破らないか?
```

repo 内の例:

- [`languages/p/PingPong/`](../languages/p/PingPong/)

P が返すもの:

- event schedule
- monitor violation
- state machine としての修正箇所

## Dafny / MoonBit prove: code-level contract

実装に近い問い:

```text
この関数は、すべての入力で postcondition を満たすか?
この loop は invariant を保つか?
```

repo 内の例:

- [`languages/dafny/checkout_form.dfy`](../languages/dafny/checkout_form.dfy)
- [`languages/dafny/rbac_screens.dfy`](../languages/dafny/rbac_screens.dfy)
- [`languages/dafny/dijkstra.dfy`](../languages/dafny/dijkstra.dfy)
- [`languages/moonbit/checkout_form/`](../languages/moonbit/checkout_form/)
- [`languages/moonbit/p2p_game_protocol/`](../languages/moonbit/p2p_game_protocol/)
- [`languages/moonbit/MOON_PROVE_CAPABILITIES.md`](../languages/moonbit/MOON_PROVE_CAPABILITIES.md)

返ってくるもの:

- 証明済み obligation
- failed assertion / failed postcondition
- 実装と contract のずれ

## Lean: 普遍定理

実装に近い問い:

```text
viewer が許可される permission は、常に editor でも許可されるか?
将来 permission が増えても、この monotonicity は破れないか?
```

repo 内の例:

- [`languages/lean/Rbac.lean`](../languages/lean/Rbac.lean)

Lean が返すもの:

- bounded scope ではない theorem
- check 済み proof term
- 実装から独立して残る仕様

## Rocq: compiler correctness

実装に近い問い:

```text
source evaluator と compiled stack machine は、任意の式と初期 stack で同じ結果になるか?
```

repo 内の例:

- [`languages/rocq/StackCompiler.v`](../languages/rocq/StackCompiler.v)
- [`languages/rocq/BrokenStackCompiler.v`](../languages/rocq/BrokenStackCompiler.v)

Rocq が返すもの:

- source expression の構造帰納法で check 済みの意味保存 theorem
- operand 順を逆転した compiler に対する `Some [0]` と `Some [3]` の型不一致
- compiler / interpreter / DSL semantics を本格証明へ伸ばす足場
