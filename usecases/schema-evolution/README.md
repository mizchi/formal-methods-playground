# schema-evolution/

Pattern: a payload shape changes, and for the length of the deploy window both
versions are live. Every message therefore crosses the version boundary in
**both** directions:

```text
v1 pod writes  ->  v2 pod reads     backward compatibility
v2 pod writes  ->  v1 pod reads     forward  compatibility
```

A change is deployable only if both hold. Teams usually check one — typically
"does the new code read the old data" during the migration review — and get
bitten by the other during the rollout, when a canary v2 pod writes a value the
still-running v1 pods reject.

Real instances: rolling deploys, protobuf/Avro/JSON-Schema evolution, an event
log or outbox topic replayed by consumers of mixed versions, a mobile client
that cannot be forced to update, `expand → migrate → contract` column changes.

The source of truth is both versions' writer and reader code. Do not model a
codec (that is [`wire-contract/`](../wire-contract/), which checks bit layout);
model **what each side emits and what each side accepts**.

## Split the question

| Question | Shape | Tool | Example |
| --- | --- | --- | --- |
| Can the new reader reject old data? | predicate satisfiability | Z3 | a required field that old writers omit |
| Can the old reader reject new data? | predicate satisfiability | Z3 | a new enum variant |
| Does the tolerant reader close both? | same query, tolerant readers | Z3 | default the field, catch-all the variant |
| Does *accepting* the message mean *understanding* it? | reachability of a wrong action | Z3 | unknown status mapped to `pending` |

The last row is the one worth stealing. Compatibility tooling checks that the
bytes parse. It does not check that the old code, having parsed a value it has
no concept of, then does something harmless.

## Probe: Z3

[`languages/z3/schema_evolution.smt2`](../../languages/z3/schema_evolution.smt2)

The change under test is the one every team ships eventually: `status` gains a
`refunded` variant, and `currency` goes from optional to required.

| Check | Expected | Domain meaning |
| --- | --- | --- |
| strict v2 reader vs. a v1 record | `sat` | old rows have no `currency`; the new required field fails them |
| strict v1 reader vs. a v2 record | `sat` | a canary pod writes `refunded`; old pods dead-letter it |
| tolerant v2 reader vs. a v1 record | `unsat` | defaulting the missing currency accepts every old record |
| tolerant v1 reader vs. a v2 record | `unsat` | a catch-all variant accepts every new record |
| fail-**open** fallback (`unknown -> pending`) | `sat` | witness: v1 parses a refunded order and re-captures payment |
| fail-**closed** fallback (`unknown -> hold`) | `unsat` | no status v1 does not understand can be acted on |

The fifth check is the interesting failure. The message parsed. Compatibility
tooling was green. The order was refunded and the old pod charged it again.

```sh
nix develop -c z3 -smt2 languages/z3/schema_evolution.smt2
nix develop -c just check-z3
```

## Ordering the deploy

The two `sat` results are also a deploy plan, because they say which side must
ship first:

| Change | Safe order |
| --- | --- |
| new enum variant | ship the tolerant *reader* everywhere, then the writer that emits it |
| field optional → required | backfill, then require on write, then require on read |
| field removal | stop reading, then stop writing, then drop |

That is `expand → migrate → contract`. What the probe adds is a check that
survives review: run it in the PR that changes the schema, and a change that
skips a phase turns a `unsat` into a `sat`.

## Domain ledger

| field | value |
| --- | --- |
| source | v1 and v2 writer/reader code, plus the fallback branch for unknown values |
| expected claim | during the deploy window every record either side writes is accepted *and* correctly acted on by the other |
| implementation observation | `repro/orders.ts`: the strict v2 reader requires `currency`, the strict v1 reader rejects `refunded`, and `v1ReadFallbackPending` maps an unknown status to `pending`, which `v1Process` captures |
| model question | is there a record one version can write that the other rejects, or acts on wrongly? |
| tool | Z3 |
| machine result | `sat, sat, unsat, unsat, sat, unsat` |
| witness | v1 record `{ status: pending }` with no `currency` (check 1); v2 record `{ status: refunded, currency: JPY }` (checks 2 and 5) |
| reproduction | reproduced: `repro/orders.test.ts` feeds both records to the six readers; the strict readers reject, the tolerant ones accept, the fail-open fallback captures `o2`, and the fail-closed fallback captures nothing |
| domain wording | "old pods dead-letter refunded orders, and if we make them tolerant naively they will re-capture them instead" |
| domain question | Which side ships first, and should v1 map an unknown status to a non-actionable hold rather than `pending`? |
| decision | bug (demo); tolerant readers with the fail-closed `hold` fallback, shipped in expand -> migrate -> contract order, are the checked design |
| lock | `just check-z3` (`check_schema_evolution.sh` pins all six results); `cd usecases/schema-evolution/repro && node --test orders.test.ts` |

## What this does NOT catch

- Whether the deploy window is actually bounded. A mobile client or a replayed
  event log means "old writer" never goes away, so the compatibility obligation
  is permanent, not temporary.
- Wire-level encoding. Field-number reuse, varint widening, enum ordering — that
  is [`wire-contract/`](../wire-contract/).
- The migration itself. Whether the backfill terminates and leaves no NULLs is a
  separate claim; this model assumes the data is already in the shape the
  writers describe.
- Storage-level defaults. If the *database* supplies a default the reader never
  sees the absent field, which changes the answer to check 1 — model the layer
  that actually decides.
- Semantic drift beyond the fallback branch: a field whose *meaning* changed
  while its type did not is invisible to any shape-based check.
