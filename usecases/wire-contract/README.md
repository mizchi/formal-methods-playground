# wire-contract/

Pattern: two independently-authored sides (producer / consumer, or two
services, or two language ports) must agree on how a logical field is
packed on the wire -- bit layout, granularity, endianness, enum ordering.
A one-sided change (finer granularity, reversed block order, a renumbered
enum) makes some values decode to the wrong thing. Unit tests on either
side alone pass; only the cross-side contract catches it.

The source of truth is both sides' layout code. Model the index arithmetic
of the layout, not a real byte buffer.

## Split the question

| Question | Shape | Tool | Example |
| --- | --- | --- | --- |
| Does encode/decode round-trip for every value? | equivalence over an arbitrary field | Z3 | hourly bitmap ↔ quarter-hour wire form |
| Does a one-sided layout change break it? | difference witness | Z3 | consumer assumes a different granularity / order |

## Probe: Z3

[`languages/z3/wire_contract.smt2`](../../languages/z3/wire_contract.smt2)

The producer holds one bit per hour. A codec encodes it into `Q` slots per
hour; the consumer decodes a given hour back. The producer bitmap is an
arbitrary uninterpreted function, so one check quantifies over all contents.

| Check | Expected | Domain meaning |
| --- | --- | --- |
| aligned (encode Q=4, decode Q=4) | `unsat` | round-trips for every hour and every bitmap |
| granularity mismatch (encode 4, decode 3) | `sat` | consumer misreads some hour -- a real layout bug witness |
| one-sided reversal (codec reverses, consumer forward) | `sat` | endianness/block-order mismatch witness |

```sh
nix develop -c z3 -smt2 languages/z3/wire_contract.smt2
nix develop -c just check-z3
```

## Domain ledger

| field | value |
| --- | --- |
| source of truth | producer and consumer layout code (or two service/port implementations) |
| claim | decode(encode(x)) == x for every field value |
| model question | is there a field content + position where the decoded bit differs from the source bit? |
| tool | Z3 |
| machine result | unsat (aligned round-trips) / sat, sat (breaking variants) |
| domain wording | "hourly and quarter-hour sides agree only when the codec expands by exactly the factor the consumer assumes and both use the same block order" |
| lock | `just check-z3` |

## What this does NOT catch

- Whether the modeled index arithmetic matches the *actual* production codec
  is a code-vs-model gap: reproduce the real transform tables faithfully, or
  trace-check real encoded payloads.
- Value-domain issues (a field that is packed correctly but semantically
  wrong) are out of scope; this checks layout, not meaning.
