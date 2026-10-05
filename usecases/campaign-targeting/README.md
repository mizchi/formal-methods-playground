# campaign-targeting/

Pattern: a targeting rule is assembled from several fields (include, exclude,
denylist, allowlist), often by different people. Each field looks fine on its
own; together they target nobody, or they fail open for inputs nobody wrote a
rule for.

Real instances: marketing campaign audiences, feature-flag targeting, push
notification segments, A/B experiment eligibility.

This is the reference implementation for scenario A of the
[`formal-methods-reconciler`](https://github.com/mizchi/skills/tree/main/formal-methods-reconciler)
skill eval (`formal-reconciler-config-z3-001`).

## Source of truth

The targeting document is trusted. The live config is an implementation
observation.

| Docs (trusted) | Live config (observed) |
| --- | --- |
| SummerPromo targets JP users aged 20-29 | `include.country = ["JP"]`, `include.age = { gte: 30, lt: 30 }` |
| Denylisted users never see it | `exclude.country = ["JP"]` |
| A missing or malformed country fails closed | (no field) |
| Empty allowlist: not documented | `allowlist = []` |

## Split the question

| Question | Shape | Tool |
| --- | --- | --- |
| Can the live config target anyone? | predicate satisfiability | Z3 |
| Which field makes it dead? | the same predicate, one field at a time | Z3 |
| Does the documented rule target anyone? (sanity) | predicate satisfiability | Z3 |
| Does fail-close hold for every rule shape? | predicate satisfiability | Z3 |
| What does an empty allowlist mean? | two readings, both checked | Z3, then a domain owner |

There is no ordering, retry, or relation between entities here, so TLA+ and
Alloy would add nothing.

## Probe: Z3

[`targeting.smt2`](targeting.smt2), run by [`check.sh`](check.sh):

| # | Check | Expected | Domain meaning |
| --- | --- | --- | --- |
| 1 | the live config matches someone | `unsat` | dead config: SummerPromo reaches nobody |
| 2 | `age >= 30 and age < 30` | `unsat` | the age range alone is empty |
| 3 | documented ages, but `exclude.country = ["JP"]` | `unsat` | the exclude cancels the include on its own |
| 4 | the documented rule matches someone | `sat`, e.g. `JP, 20, not denylisted` | sanity: the checks above are not vacuous |
| 5 | the documented rule matches a denylisted user | `unsat` | denylist holds |
| 6 | the documented rule matches a malformed country | `unsat` | fail-close holds, because `include.country` requires JP |
| 7 | the documented rule, empty allowlist read as "no restriction" | `sat` | the evaluator's reading keeps the campaign alive |
| 8 | the documented rule, empty allowlist read as "nobody" | `unsat` | the other reading kills the documented rule too |
| 9 | an exclude-only rule ("everyone except JP") matches a malformed country | `sat` | fail-close does not hold for exclude-only rules |

```sh
nix develop -c just check-z3
./usecases/campaign-targeting/check.sh
```

Checks 2 and 3 matter even though check 1 already failed: fixing only the age
range still leaves a dead campaign, and the reviewer needs both field names.

Check 9 was not in the first draft. Check 6 passed, and the reproduction test
for it passed even with the fail-close guard deleted from the evaluator. The
guard was not what made it pass; `include.country` was. A rule without
`include.country` has nothing to fail closed on.

## Reproduce in the implementation

[`repro/targeting.ts`](repro/targeting.ts) is a small evaluator shaped like the
ones that read campaign JSON. [`repro/targeting.test.ts`](repro/targeting.test.ts)
replays the Z3 witnesses:

| Test | Z3 check | Result |
| --- | --- | --- |
| the live config does not target `JP, 20` | 1, 4 | reproduced |
| each defect alone kills the config | 2, 3 | reproduced |
| the documented config targets `JP, 20` | 4 | reproduced |
| denylisted users never match | 5 | reproduced |
| fail-close for the documented rule | 6 | reproduced |
| empty allowlist is read as "no restriction" | 7 | pinned as an observation, not a decision |
| an exclude-only rule lets `country = "ZZ"` through | 9 | reproduced: fail-open |

```sh
node --test usecases/campaign-targeting/repro/targeting.test.ts
```

## Domain ledger

| field | value |
| --- | --- |
| source | targeting document (trusted); live campaign JSON (observed) |
| expected claim | SummerPromo reaches JP users aged 20-29 who are not denylisted; a missing or malformed country fails closed |
| implementation observation | `include.age = { gte: 30, lt: 30 }`, `exclude.country = ["JP"]`, `allowlist = []`; the evaluator reads an empty allowlist as "no restriction" |
| model question | is `live-match` satisfiable? is `doc-match` satisfiable? does any rule shape match a malformed country? |
| tool | Z3 (SMT-LIB) |
| machine result | checks 1-3 `unsat`, 4 `sat`, 5-6 `unsat`, 7 `sat`, 8 `unsat`, 9 `sat` |
| witness | `country = JP, age = 20` is not targeted by the live config; `country = Invalid` passes an exclude-only rule |
| reproduction | all witnesses reproduced by `repro/targeting.test.ts`; the first fail-close test was found to be vacuous and check 9 was added |
| domain wording | "SummerPromo currently reaches nobody: the age range is empty, and the exclude removes every JP user anyway"; "a campaign written as 'everyone except JP' also reaches users whose country we could not read" |
| domain question | Should `allowlist = []` mean "no restriction" or "nobody"? Should fail-close apply to exclude-only rules, that is, should an unreadable country be treated as excluded? |
| decision | bug (live config): fix to `gte: 20, lt: 30` and drop the JP exclude. Unresolved: empty-allowlist reading, fail-close for exclude-only rules |
| lock | `just check-z3` (`check.sh`) and `node --test usecases/campaign-targeting/repro/targeting.test.ts`; lint the config for empty ranges and include/exclude overlap before deploy |

## What this does NOT catch

- Whether the evaluator in production reads the JSON the way the model does.
  The model encodes one reading (include AND NOT exclude AND NOT denylisted AND
  allowlist); a different precedence, such as allowlist overriding exclude, is
  a different model.
- Users the data pipeline never labels. `Invalid` stands for "unreadable
  country"; whether upstream sends `null`, `""`, or omits the field is a
  reproduction question, covered only by the test's list of values.
- Time. Campaign start and end dates and time zones are not modelled.
