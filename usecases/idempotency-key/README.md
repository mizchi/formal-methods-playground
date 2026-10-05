# idempotency-key/

Pattern: a handler performs an **external side effect** and writes a **local
durable record**, and those two are not one transaction. The caller retries on
timeout (at-least-once). Whether the retry re-does the side effect depends
entirely on the order of the two writes and on what a retry does when it finds
a half-written record.

Real instances: Stripe `Idempotency-Key`, PSP capture callbacks, SQS/Kafka
consumers, "send the welcome email exactly once", provisioning a tenant,
minting an invite. Anything where the client cannot tell a lost response from
a lost request.

This is the reference implementation for scenario C of the
[`formal-methods-reconciler`](https://github.com/mizchi/skills/tree/main/formal-methods-reconciler)
skill eval (`formal-reconciler-async-tla-p-001`). That scenario records the key
in an async job after the provider call, which is the `_late` design below with
a wider window. Its other step, a retry that arrives before the job runs with
no crash at all, is two attempts in flight at once; this model runs one attempt
at a time (see "What this does NOT catch").

The source of truth is the handler's write order plus the retry policy. Do not
model HTTP; model the two writes and the crash window between them.

## Split the question

| Question | Shape | Tool | Example |
| --- | --- | --- | --- |
| Can a retry cause a second side effect? | safety over crash interleavings | TLA+ | crash after charging, before recording the key |
| Does a retried request eventually finish? | liveness under fairness | TLA+ | a key stuck in `reserved` that nobody may resume |
| Is a specific key/param pair even well-formed? | predicate | Z3 | out of scope here; see `wire-contract/` |

The two rows are the point of this use case: **a design can be safe and still
be broken.** Reserve-first plus "return 409 while reserved" never double
charges *and* wedges the key forever after one crash. Checking only
`NoDoubleCharge` would have shipped it.

## Probe: TLA+

[`languages/tla/IdempotentRetry.tla`](../../languages/tla/IdempotentRetry.tla)

Three constants pick out the three designs teams actually ship:

| Constant | Meaning |
| --- | --- |
| `ReserveFirst` | write the idempotency row *before* calling the provider |
| `ProviderIdempotent` | does the provider dedupe on the same key too? |
| `TakeoverReserved` | may a retry resume a row it found in `reserved`? |

| Command | Expected | Domain meaning |
| --- | --- | --- |
| `tlc -config IdempotentRetry.cfg IdempotentRetry.tla` | no error (16 states, depth 8) | reserve-first + resumable + provider-side dedupe: at most one charge, and every retry settles |
| `tlc -config IdempotentRetry_late.cfg IdempotentRetry.tla` | `Invariant NoDoubleCharge is violated` (`charges = 2`) | breaking variant (safety): the key row is written after the charge, so a crash in that window lets the retry charge again |
| `tlc -config IdempotentRetry_blocking.cfg IdempotentRetry.tla` | `Temporal properties were violated` (the cfg's only `PROPERTY` is `EventuallySettled`; stuttering at `rec = "reserved"`) | breaking variant (liveness): reserve-first with a hard 409 on `reserved` is safe and wedges after one crash |

`IdempotentRetry.cfg` is the CI-green check. The other two are load-bearing and
break *different* properties — keep both, because a future change that fixes one
by reintroducing the other would otherwise pass.

```sh
nix develop -c just check-tla
nix develop -c bash -c 'cd languages/tla && tlc -config IdempotentRetry_late.cfg IdempotentRetry.tla'
nix develop -c bash -c 'cd languages/tla && tlc -config IdempotentRetry_blocking.cfg IdempotentRetry.tla'
```

## The trace to show a reviewer

`IdempotentRetry_late.cfg`, six states:

```text
Begin   rec = "none"      pc = "charging"   charges = 0
Charge  rec = "none"      pc = "storing"    charges = 1
Crash   rec = "none"      pc = "idle"       charges = 1   <- the window
Begin   rec = "none"      pc = "charging"   charges = 1
Charge  rec = "none"      pc = "storing"    charges = 2   <- violated
```

The domain sentence is one line: *"if we die between the provider call and the
`INSERT INTO idempotency_keys`, the client's retry charges the card again."*

## Domain ledger

| field | value |
| --- | --- |
| source | the handler's write order, the retry policy, and the provider's own dedupe guarantee |
| expected claim | at most one external side effect per idempotency key, and every retried request eventually settles |
| implementation observation | `repro/handler.ts` implements the three designs: key row written after the charge, reserve-first with a 409 while `reserved`, and reserve-first + takeover + provider dedupe |
| model question | is there a crash interleaving with `charges > 1`? is there one where `pc` never reaches `settled`? |
| tool | TLA+ (TLC) |
| machine result | green cfg: no error (16 states, depth 8) / `_late`: `NoDoubleCharge` violated, `charges = 2` / `_blocking`: `EventuallySettled` violated (stuttering at `rec = "reserved"`) |
| witness | `_late`: Begin, Charge, Crash, Begin, Charge (see "The trace to show a reviewer"); `_blocking`: Begin (`rec = "reserved"`), Crash, then stuttering |
| reproduction | reproduced: `repro/handler.test.ts` forces both crash points (`afterCharge` gives `charges = 2`, `afterReserve` gives `"gave up"`) and passes one charge for the fixed design; `test-oracle/tla-trace/` replays the TLC traces against the same handler |
| domain wording | "a crash between the charge and the key row double-charges"; "a crash after reserving wedges the key until an operator clears it" |
| domain question | Does the provider dedupe on our key for at least as long as the caller keeps retrying, and may a retry resume a key it finds in `reserved`? |
| decision | bug (demo); fixed variant `IdempotentRetry.cfg` (reserve-first + takeover + provider dedupe) is the CI check |
| lock | `just check-tla` (runs `IdempotentRetry.cfg` green, and `_late` / `_blocking` expecting their violations); `cd usecases/idempotency-key/repro && node --test handler.test.ts` |

## What this does NOT catch

- Whether the provider's dedupe window is longer than the caller's retry window.
  `ProviderIdempotent = TRUE` assumes the key is still recognised; Stripe's is
  24h, a caller retrying for a week is outside the model.
- Whether the idempotency row and the business row commit together. This model
  treats `Store` as one durable step; if they are two tables without a
  transaction, that is a second crash window not modelled here.
- Key *scoping*. Two different requests reusing the same key (client bug, or a
  key derived from a non-unique field) is a predicate question, not a temporal
  one — model it like `trust-boundary/`.
- Concurrent retries. The model runs one attempt at a time; two in-flight
  retries racing need a `Workers`-style set, as in `RateLimitRace.tla`.
