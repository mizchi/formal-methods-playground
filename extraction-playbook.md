# Extraction playbook — pointing these tools at a real codebase

The probes in this repo are *synthetic*: a property invented to
exercise one tool. This doc covers the other direction — starting
from an **existing implementation** and pulling a checked model out
of it, then closing the loop back to an executable reproduction.

The goal is never "verify the program". It is: **make one implicit
assumption explicit enough that an owner can accept, reject, or
refine it**, backed by a machine-checked witness. Keep each model
small and single-claim.

The tool-picking guidance in [`verification-tools.md`](verification-tools.md)
answers "which tool for shape X". This doc answers "where is a
checkable claim hiding, and how do I make the model *credible*".

## The ten patterns

Tool-agnostic patterns that survive stripping any one domain. Each
is expanded in the section noted.

| # | Pattern | One line | §  |
| --- | --- | --- | --- |
| 1 | **Extraction workflow** | source repo → claim → model → run → record → issue, as a loop | all |
| 2 | **Claim-shape tells** | where a checkable claim hides in real code, each tell pointing at a tool | §1 |
| 3 | **Dual-check discipline** | every model both *holds* the invariant and *witnesses* the boundary; only-green is weak, only-red may model the wrong thing | §3A |
| 4 | **Toggle, don't fork** | one CONSTANT / `push`-scoped assumption flips the code's own gate, so one file carries both "sound" and "regression" | §3 |
| 5 | **Abstract noise, keep the mechanism** | model the suspect at full fidelity, abstract the rest, and say what you abstracted | §3B |
| 6 | **Source-observation header** | every model names the exact files/functions/constants it came from, so it re-checks as code drifts | §2 |
| 7 | **Model→repro credibility ladder** | a witness is a hypothesis; rank Tier 1 (runs against real code, then revert) vs Tier 2 (reachable under stated assumptions) | §4 |
| 8 | **CI pins violations, not just success** | witness configs must *fail in the expected way*, or the model stopped discriminating | §5 |
| 9 | **Provenance ledger** | one index row per extracted claim: source / shape / model / result / question / next | §6 |
| 10 | **Fairness & big-literal gotchas** | per-action `WF` for liveness; abstract 32-/64-bit literals to a symbolic outcome so TLC doesn't explode | gotchas |

## 1. Find the claim shape in the implementation

Read the real code, not the README, and look for a place where the
code is *already deciding something that could be wrong*. The
recurring tells, each pointing at a tool:

| Tell in the code | Shape | Reach for |
| --- | --- | --- |
| a `match` / `if` cascade that resolves inputs into cases and rejects the rest (operand resolution, command authorization) | relation / case-exhaustiveness | Alloy, or Z3 for a pure predicate |
| a clamp / fold / `min` pipeline enforcing a bound (a safety envelope, a rate limit) | arithmetic bound | Z3 |
| an explicit state field advanced by rules (`status`, `wal_sequence`, a job lifecycle) | temporal state machine | TLA+ |
| a persisted layout with fixed offsets/sizes (a wire format, a record on disk) | byte/layout math, round-trip | Z3 |
| a durability sequence (`write` → `fsync` → `rename`, CAS + retry, recovery) | crash-consistency | TLA+ |
| a time-keyed lookup or a counting/uniqueness assumption (latest-before, a `group by`, a `(k, t)` uniqueness) | relation / ordering | Alloy or TLA+ |
| a comment that *admits* a hazard ("retry may duplicate", "hard to reproduce") | pre-located witness | whichever the shape above picks |

Name the claim in one sentence; the shape picks the tool. When two
tools fit, prefer the one whose *counterexample* is most readable to
the owner — a dated TLC trace beats a flat Z3 model for anything
temporal.

## 2. Anchor the model to the source: a provenance header

Every extracted model starts with a **source-observation** block:
the exact files, functions, and constants it was derived from. A
synthetic probe has no source; an extracted one is worthless without
this, because it must be re-checkable as the code drifts.

```
-- Source observation:
--   auth/rbac.ts  grant()        lines 40-58
--   the role table ROLES         (viewer < editor < admin)
-- Abstracted away: the HTTP layer, the DB. Kept exact: the role
--   comparison and the screen-permission join.
```

State what you abstracted, so a reader knows the model's reach.

## 3. Model the smallest thing that yields a witness — two rules

**Rule A — prove the good property AND hunt the witness.** A model
that only shows the code is fine is weak; a model that only shows a
bug may be modelling the wrong thing. Do both in the same file:

- assert the intended invariant, expect it to hold (Z3 `unsat` to a
  violation / TLC "No error" / Alloy no-instance), **and**
- construct the boundary case, expect a witness (Z3 `sat` +
  `get-model` / TLC counterexample / Alloy instance).

This is the same discipline as the repo's "breaking variant"
convention, made mandatory: a model without both directions has not
earned trust.

**Rule B — abstract the noise, keep the mechanism.** Model the
suspect mechanism at full fidelity; abstract everything else. If a
`uint32` multiply is the suspect, keep the width exact and drop the
surrounding I/O. If the checker chokes on a real constant (`2^32`
blows up TLC's state count), abstract the wrapped branch to a
*symbolic* outcome (`Overflowed`) rather than computing the literal.

**Toggle, don't fork.** Encode the "current code" and the "proposed
fix" as one CONSTANT / `push`-scoped assumption that flips the
code's own gate, so a single file carries both the "sound" check and
the "regression" witness:

```smt2
(push) ; current: no value check on the threshold
  (assert (= threshold nan)) (check-sat)          ; expect sat  — disarmed
(pop)
(push) ; fixed: reject non-finite thresholds
  (assert (and (is-finite threshold) (= threshold nan))) (check-sat) ; unsat
(pop)
```

## 4. Close the loop — the model→repro credibility ladder

A model witness is a **hypothesis**, not a verdict. It says "*under
these modeling assumptions* the bad state is reachable". Rank each
finding by how far you closed the gap to the real code:

- **Tier 1 — confirmed real defect.** The witness runs against the
  actual code as a test and reproduces. For pure/deterministic
  logic, drop the witness in as an in-crate `#[test]` / unit test,
  run it, then **revert** (`git checkout`) so the source repo is
  left clean. The passing test *is* the evidence.
- **Tier 2 — reachable under stated assumptions.** The trigger is a
  hardware / reset / timing condition you can't drive from a unit
  test, so the evidence is the exact missing guard plus the model
  witness. Say so; don't inflate it to Tier 1.

Record the raw solver output (the TLC trace, the `get-value`, the
Alloy instance) verbatim with its re-run command, so anyone can
reproduce the witness without re-deriving the model.

## 5. Pin the discrimination in CI

Running the tools and expecting *success* is half a gate. The other
half: the witness configs must **fail in the expected way**, or the
model has silently stopped discriminating. Assert the exact result
per check:

- Z3: the precise `sat` / `unsat` sequence (not just "no crash").
- TLC: distinguish "No error" from "Invariant violated" from
  "Temporal properties were violated" — a helper per expected
  outcome, grepping TLC's output for the right line.
- Alloy: instance-found vs no-instance per named command.

A check that comes back the wrong way is information: either the
model drifted from the code, or the code changed. Reconcile before
trusting the green.

## 6. A ledger for a portfolio of extracted models

One synthetic probe stands alone; a portfolio of extracted models
needs a provenance index. One section per claim, same skeleton:

```markdown
### <claim name>
- Source observation:  <files / functions / constants>
- Claim shape:         <predicate | state machine | relation | layout | crash-consistency>
- First model:         `<path>` (+ witness configs / commands)
- Current result:      <what holds, then each witness in one line>
- Domain question:     <what only the owner can decide>
- Next checks:         <the obvious follow-on, so the thread isn't lost>
```

The model is a conversation starter for the owner, not a judgment —
phrase the witness as "reachable in the model" and let them accept
it as an intended precondition or fix it.

## Tool-agnostic gotchas worth knowing up front

- **TLA+ liveness fairness.** `WF_vars(Next)` is usually too weak:
  an unrelated action keeps firing and the temporal property
  "holds" for the wrong reason. Put `WF_vars(...)` on each *exit*
  action you need to eventually fire, and re-confirm the fix config
  actually violates when you break it.
- **TLC and big literals.** A real 32-/64-bit constant explodes the
  state count. Abstract the arithmetic branch to a symbolic outcome
  instead of letting TLC enumerate it.
- **Package/name drift when adding in-crate tests.** The crate's
  package name is rarely its directory name; grep the manifest for
  the real name before `cargo test -p <name>`.
