# rate-limiting/

Pattern: a shared counter enforces a limit ("at most Cap events per
period"). Two independent failure modes, two tools:

- **concurrent enforcement** (does the limit hold when workers race?) -> TLA+
- **static config** (are the configured limits even meaningful?) -> Z3

The source of truth is the enforcement code plus the configured limits.
Do not model the traffic; model the counter protocol and the limit set.

## Split the question

| Question | Shape | Tool | Example |
| --- | --- | --- | --- |
| Can concurrent grants exceed the cap? | read-modify-write race | TLA+ | two workers read the same pre-grant count |
| Is a configured limit redundant? | integer feasibility | Z3 | "10/hour" under "1/hour" is dead config |
| What is the *effective* limit? | witness search | Z3 | tightest window dominates |

## Concurrent enforcement: TLA+

Probe: [`languages/tla/RateLimitRace.tla`](../../languages/tla/RateLimitRace.tla)

`N` workers read a shared count, check `count < Cap`, then grant + record.
Whether read-check-record is atomic decides correctness.

| Command | Expected | Domain meaning |
| --- | --- | --- |
| `tlc -config RateLimitRace.cfg RateLimitRace.tla` | no error | atomic check-and-increment: `granted <= Cap` under every interleaving |
| `tlc -config RateLimitRace_naive.cfg RateLimitRace.tla` | `NoOverGrant` violated (`granted = Cap+1`) | breaking variant: split read+record races, two workers over-grant |

`RateLimitRace.cfg` (atomic) is the CI-green check. The naive cfg is the
load-bearing breaking variant -- run it to see the over-grant trace.

```sh
nix develop -c just check-tla
nix develop -c bash -c 'cd languages/tla && tlc -config RateLimitRace_naive.cfg RateLimitRace.tla'
```

## Static config: Z3

Probe: [`languages/z3/rate_limit_subsumption.smt2`](../../languages/z3/rate_limit_subsumption.smt2)

`a=(cap_a,period_a)` subsumes `b` iff no event sequence satisfies `a`
while violating `b`. `unsat` on the witness search means `b` is redundant.

| Check | Expected | Domain meaning |
| --- | --- | --- |
| `1/3600s` vs `10/3600s` | `unsat` | the 10/hour limit is dead config (1/hour already dominates) |
| `2/10s` vs `5/10s` | `unsat` | tighter same-window limit subsumes the looser one |
| `10/3600s` vs `2/10s` | `sat` | both effective (witness: 3 events in 10s stays under 10/hour) |

```sh
nix develop -c z3 -smt2 languages/z3/rate_limit_subsumption.smt2
nix develop -c just check-z3
```

## Domain ledger

| field | value |
| --- | --- |
| source | rate-limit enforcement code + configured limit set |
| expected claim | grants never exceed the cap; every configured limit changes some decision |
| implementation observation | the naive variant splits read and record (`Atomic = FALSE`); the example config carries a 10/hour limit under a 1/hour limit |
| model question | is there an interleaving with `granted > Cap`? is there a sequence satisfying `a` but violating `b`? |
| tool | TLA+ (race) / Z3 (subsumption) |
| machine result | atomic: no error / naive: `granted = Cap+1`; subsumption: unsat, unsat, sat |
| witness | naive, `Cap = 1`: two workers both read the pre-grant count and both grant (`granted = 2`); `10/3600s` vs `2/10s`: 3 events in 10s stay under 10/hour |
| reproduction | none yet; the README proposes inspecting the production write path or trace-checking real operations against `RateLimitRace` |
| domain wording | "with a split read-then-record, two concurrent requests both pass the check and over-grant by one"; "the 10/hour cap under a 1/hour cap never fires" |
| domain question | Does the production store do the check and the record as one conditional write? Is the subsumed 10/hour limit meant to be active? |
| decision | bug (demo); atomic variant `RateLimitRace.cfg` is the CI check. The subsumed limit is unresolved (dead config to remove or re-tune). |
| lock | `just check-tla` (runs `RateLimitRace.cfg` green, and the naive cfg expecting `NoOverGrant` to be violated), `just check-z3` |

## What this does NOT catch

- The real store's actual atomicity (does the production DB do a conditional
  write?) is a code-vs-model gap: confirm by inspecting the write path or by
  trace-checking real operations against `RateLimitRace`.
- Distributed enforcement across replicas (no shared memory) is a stronger
  race than the single-counter model here.
- Eventual-consistency read staleness widens the window further and is not
  modeled in the atomic variant.
