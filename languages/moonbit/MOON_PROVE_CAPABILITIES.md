# What `moon prove` Can Do

Based on `moonbit-community/verified`:

- <https://github.com/moonbit-community/verified>
- <https://github.com/moonbit-community/verified/tree/main/examples/demos>
- <https://github.com/moonbit-community/verified/tree/main/examples/finance>

`moon prove` is best understood as an SMT-backed verifier for
MoonBit implementation contracts. It is close to Dafny / Why3 in
style: write executable MoonBit, add preconditions,
postconditions, loop invariants, and proof-only predicates, then
let Why3 dispatch verification conditions to SMT solvers.

## What It Verifies Well

### Function Contracts

Use `proof_require` for preconditions and `proof_ensure` for
postconditions.

Good targets:

- arithmetic functions: `abs`, `clamp`, `max`, integer division
- boundary-heavy helpers: valid ranges, lower bounds, safe indexes
- business-rule functions: mint/repay/withdraw/liquidate style state
  updates

This is the most direct replacement for a Z3 proof that says:

```text
for all inputs satisfying preconditions, result satisfies contract
```

### Loop Invariants

The `verified` repo uses `proof_invariant`, `proof_yield`, and
`proof_reasoning` to prove loops.

Good targets:

- linear search
- binary search
- lower bound
- array max index
- counting
- sorting loops
- byte-string search

This is stronger than example tests because the loop contract is
checked for all input arrays satisfying the stated preconditions.

### Data-Structure Representation Invariants

The larger examples prove that operations preserve an abstract model.

Examples from `verified`:

- `vector`: persistent vector operations against a `Seq` model
- `sparse_array`: bitmap-backed storage against a finite-map model
- `avl`: balance, ordering, insert/delete, and set preservation
- `leftist_heap`, `skew_heap`, `pairing_heap`: heap order and minimum
  behavior
- `stack_min`: cached minimum remains correct

The pattern is:

```text
runtime structure -> proof-only model -> operation postcondition
```

For application code, this maps to "the implementation layout can
change, but the abstract behavior stays fixed."

### Domain Invariants

The finance examples show that `moon prove` can handle domain logic,
not only toy algorithms.

Examples:

- stablecoin engine: collateralization, liquidation, bad-debt accounting
- margin engine: liquidation boundary, funding impact, deleveraging
- bridge custody: replay-safe withdrawals through nonce tracking
- CPMM swap: fee-adjusted reserve updates
- LTV lending: solvency-preserving operations
- batch auction: matched/unmatched frontier search
- risk limits: earliest-breach monitor
- vesting stream: bounded claim/release logic
- threshold multisig: approval counting and threshold execution

This is the most relevant category for "implementation as de-facto
spec": encode the product rule as predicates in `.mbtp`, keep the
MoonBit body executable, and prove the body preserves the rule.

### Logical Models, Lemmas, and Trusted Bridges

`verified` uses `.mbtp` files heavily for:

- `predicate`
- proof-only model functions
- `lemma`
- `proof_import`
- `proof_decrease`
- abstract sequence/set/map/bitvector models

This is the right place for facts that are not runtime code but are
needed by the verifier.

There is also a trust boundary: examples use `proof_axiomatized` and
model bridges for arrays, bytes, bitvectors, maps, and hashes. These
make verification practical, but the axiom must correctly describe the
runtime primitive.

## What It Does Not Replace

### It Is Not a Model Finder

Z3 direct queries are still better for:

- `sat` witness extraction
- old-vs-new predicate difference witnesses
- broken-variant self-checks
- "show me an input where this changes"

`moon prove` proves obligations. It does not naturally return a model
like:

```text
kind = 1, email_len = 0, total = 1
```

Use `moon prove` to lock the contract. Use Z3 to hunt for examples and
counterexamples.

### It Is Not a Temporal Model Checker

Use TLA+ / P instead when the property is about:

- concurrent interleavings
- retry ordering
- eventual consistency
- crash/restart
- fairness / liveness
- message protocol schedules

`moon prove` is for a function body and its local control flow. It is
not a replacement for checking all possible event orders.

### It Is Not Fully Automatic

Non-trivial proofs need proof engineering:

- loop invariants must be written
- recursive predicates need decreases measures
- algebra often needs helper lemmas
- proof shape matters; a logically equivalent formula can timeout
- trusted model bridges must be reviewed

If a proof times out, simplify the contract shape, add intermediate
`proof_assert`s, or move reusable facts into `.mbtp` lemmas.

## Practical Pattern

Use this workflow for MoonBit code:

1. Keep implementation in `.mbt`.
2. Put domain predicates, model functions, and lemmas in `.mbtp`.
3. Put `proof_require` / `proof_ensure` on public operations.
4. Add `proof_invariant` for loops.
5. Use `proof_assert` to expose intermediate facts to the solver.
6. Run:

```sh
nix develop -c just setup-moonbit-prove-opam
nix develop -c just prove-moonbit
```

Use `moon test` for executable examples and snapshot behavior. Use
Z3 direct SMT checks for witness-oriented questions.

## Tool Selection Rule

Use `moon prove` when:

- the code is MoonBit
- the property is a function contract or loop invariant
- the desired result is "this implementation always satisfies this
  predicate"
- the proof target can be phrased over integers, arrays, algebraic data,
  sequences, sets, maps, bitvectors, or proof-only models

Use Z3 directly when:

- the target is data/config/policy rather than MoonBit code
- you want witnesses or equivalence/difference examples
- you want broken-variant self-checks

Use TLA+ / P when:

- the target is time, ordering, concurrency, retries, or messages

In this repo, the current split is therefore:

- `moon prove`: lock MoonBit implementation contracts
- `z3/`: ask direct SAT/UNSAT witness questions
- `tla/` and `p/`: explore temporal/interleaving behavior
