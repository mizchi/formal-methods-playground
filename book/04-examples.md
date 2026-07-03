# 5. 実例

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

## Alloy: 認証・認可

実装に近い問い:

```text
user が所属していない tenant の resource を読める経路はあるか?
non-admin が settings に到達できる screen transition はあるか?
```

repo 内の例:

- [`languages/alloy/app-rbac.als`](../languages/alloy/app-rbac.als)
- [`languages/alloy/multi-tenant.als`](../languages/alloy/multi-tenant.als)

Alloy が返すもの:

- 小さい user / org / resource / role の world
- どの relation が穴を作ったか
- domain owner に見せられる具体 instance

## TLA+: network / queue / retry

実装に近い問い:

```text
API -> DB -> outbox -> queue -> worker のどこで crash しても、
二重処理や lost update が起きないか?
```

repo 内の例:

- [`languages/tla/OrderCheckout.tla`](../languages/tla/OrderCheckout.tla)
- [`languages/tla/EventSourcing.tla`](../languages/tla/EventSourcing.tla)
- [`languages/tla/ActorMailbox.tla`](../languages/tla/ActorMailbox.tla)

TLA+ が返すもの:

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
- [`languages/moonbit/checkout_form/`](../languages/moonbit/checkout_form/)
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

## Rocq: 成熟 ecosystem に向けた smoke probe

実装に近い問い:

```text
Lean と同じ RBAC monotonicity を、Rocq toolchain でも CI で確認できるか?
```

repo 内の例:

- [`languages/rocq/Rbac.v`](../languages/rocq/Rbac.v)

Rocq が返すもの:

- `coqc` による proof script の check
- 将来 Iris / CompCert などに進むための CI 上の足場
