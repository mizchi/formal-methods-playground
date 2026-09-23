# claims/

Every probe in this repo makes a claim, and every claim is supposed to be
backed by a specific machine result. Until this directory existed, that pairing
lived in prose — a line in a README saying *"no error (21 states, depth 7)"* —
and CI only asserted that the green runs exited 0.

That is not enough for the discipline the rest of the repo is built on. The
load-bearing half of every probe is its **breaking variant**: the config that
is supposed to produce the counterexample. Seven of the seventeen TLA+ configs
were never run by CI at all, and all the interesting ones were among them. So:

```
$ # weaken SeatsWithinLimit from `members <= SeatLimit` to `<= SeatLimit + 1`
$ ./scripts/check-tla.sh    # the old one, green checks only
8 specs green, exit 0
```

Nothing notices. The green check stays green — a weaker invariant still holds —
and the breaking variant quietly stops breaking, which no one was looking at.

[`catalog.json`](catalog.json) is the fix, and
[`scripts/check-claims.py`](../scripts/check-claims.py) is the oracle over it:
it runs every claim, green and breaking alike, and decides whether the repo
still says what the book says it says.

```
$ ./scripts/check-claims.py
DRIFT SEAT-LIMIT-003  [model-drift or spec-drift]
      claim   : plain snapshot isolation admits the write skew and the seat limit breaks
      check   : tlc -config SeatLimitWriteSkew_si.cfg SeatLimitWriteSkew.tla
      drift   : the breaking variant stopped breaking: expected invariant-violated, got no error
      what to do: the property this variant is supposed to violate got weaker, or the
                  model no longer reaches the bad state. The green claim it guards is now
                  passing for no reason -- do not update the catalog until you know which.
```

This is chapter 5's continuous-verification pattern
(`checkResult == expectedResult`) and chapter 8's drift ledger
(`previous_machine_result` / `current_machine_result` / `epistemic_status`),
with a machine behind them instead of a person remembering.

## What a claim holds

| field | meaning |
| --- | --- |
| `claim_id` | stable id, in the [drift ledger](../book/templates/drift-ledger.md)'s style |
| `domain_claim` | the business rule, in domain words — not the invariant's name |
| `source_of_truth` | optional: where the rule actually lives (SQL, a config, an ADR) |
| `timing` | which [slot](../book/06-timing.md) this check belongs in (T0–T6) |
| `role` | `green` (the claim holds) or `breaking` (the claim is supposed to fail) |
| `guards` / `guarded_by` | which claims this variant gives teeth to, and vice versa |
| `unguarded_reason` | required on a green claim with no breaking variant |
| `tool`, `spec`, `config` | what to run |
| `expect` | the machine result: see below |
| `domain_wording` | what to tell someone who does not read TLA+ |
| `documented_in` / `doc_claims` | prose that must still quote the tool correctly |

`expect` is the load-bearing part:

```json
{ "outcome": "no-error", "distinct_states": 21, "depth": 7 }
```

```json
{ "outcome": "invariant-violated", "invariant": "SeatsWithinLimit",
  "witness": ["members = 2"], "distinct_states": 20, "depth": 7 }
```

```json
{ "outcome": "property-violated", "witness": ["i = 6"], "distinct_states": 6 }
```

`witness` fragments must appear in the counterexample. They are what keeps a
breaking variant honest: a violation that no longer shows `members = 2` is a
different bug, and the domain sentence in the README is no longer true of it.

## What a failure means

The oracle reports in the drift vocabulary of
[chapter 8](../book/05-model-maintenance.md), because which class it is decides
which file you go and edit.

| reported class | what happened | where to look |
| --- | --- | --- |
| `model-drift or spec-drift` | a breaking variant stopped breaking | the property got weaker, or the model stopped reaching the bad state |
| `code-drift or model-drift` | a green claim stopped holding | decide whether the rule changed or the model broke, before editing either |
| `model-drift` | it still fails, but differently: another invariant broke first, or the witness changed | the counterexample no longer demonstrates the claim it was written for |
| `harness-drift or model-drift` | same outcome, different state count or depth | a tool upgrade or a model change; update the catalog in the same commit as whatever moved it |
| `doc-drift` | the machine agrees with the catalog, the prose does not | a README quoting a tool output that the tool no longer prints |

`doc-drift` has already caught one: `usecases/idempotency-key/README.md` quoted
`Temporal property EventuallySettled was violated`, and TLC prints
`Temporal properties were violated.` without naming the property.

## Catalog-level checks

Beyond running each claim, the oracle checks the catalog itself:

- every `.cfg` under `languages/tla/` has exactly one claim — you cannot add a
  config CI does not run;
- every green claim is either `guarded_by` a breaking variant or carries an
  `unguarded_reason` — you cannot add a green check nothing can falsify without
  saying so in writing;
- `guards` and `guarded_by` agree in both directions;
- `claim_id`s are unique.

Five claims currently carry an `unguarded_reason`. That is a declared gap, not
a hidden one, and it is the honest place to start if you want to add a probe.

## Adding a claim

1. Write the probe and run it. Record what the tool actually printed — do not
   write down what you expect it to print.
2. Add the entry. Give it a `domain_claim` someone outside the repo could
   judge, and a `domain_wording` that never mentions an invariant's name.
3. If it is green, either write its breaking variant or fill in
   `unguarded_reason`.
4. `./scripts/check-claims.py --filter YOUR-CLAIM-ID`.

A new `tool` needs a runner in `scripts/check-claims.py` and a CI job that
calls the oracle for it. Alloy and Z3 are not in the catalog yet: they already
pin expected results (`run_expect ... UNSAT` in
[`scripts/check-alloy.sh`](../scripts/check-alloy.sh), fixed `check-sat`
sequences in `languages/z3/check_*.sh`), so they have an oracle of their own.
Folding them in would put every claim in one place; it has not been done.
