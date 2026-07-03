# Real-world adoption guide

This repository is not trying to rank formal tools in the abstract.
The useful question is:

```text
What existing engineering activity can this replace or harden?
```

The goal is to turn fragile review conversations, hand-written
test matrices, and informal design docs into executable artifacts
that either produce counterexamples or become regression contracts.

When trusted specs or docs exist, treat them as the expected contract
and look for mismatches in the implementation. When they do not exist
or cannot be trusted, treat the code as a de-facto spec and extract
the behavior it implicitly commits to.

In both cases, translate solver output back into domain language before
asking for a decision. Do not show only SAT, UNSAT, traces, or failed
proof obligations. Ask who can do what, which order is accepted, or
which crash ordering loses an update.

Japanese version: [`real-world-adoption.ja.md`](real-world-adoption.ja.md).

## What These Tools Replace

| Current practice | Replace or harden with | Primary tool | Output |
| --- | --- | --- | --- |
| Manual review of branch guards, validators, feature flags, and policy predicates | Direct solver check over the extracted predicate | Z3 / SMT-LIB | SAT/UNSAT plus optional witness |
| Spreadsheet-style config sanity checks | Exhaustive consistency, reachability, and dead-config queries | Z3 or Alloy | Invalid config witness or proof of absence in scope |
| Whiteboard diagrams for RBAC, ownership, tenancy, routing, and workflow states | Relational model with finite-scope counterexample search | Alloy | Concrete small instance showing the bug |
| "We think every async path resolves" design discussion | Temporal model with safety and liveness invariants | TLA+ | Trace showing stuck, unsafe, or unfair behavior |
| Actor/message protocol tests with many mocks | Executable state-machine model and schedule exploration | P | Reproducible event schedule |
| Boundary-heavy unit tests for sequential logic | Pre/postconditions and loop invariants on code-like functions | Dafny / MoonBit `moon prove` | Verified obligations or exact failing assertion |
| Hand-maintained claims about data-structure behavior | Abstract model plus representation invariants | MoonBit `moon prove`, Dafny, Why3 | API contract that implementation preserves the model |
| "This refactor should be equivalent" confidence | Old-vs-new equivalence or difference query | Z3, Dafny, MoonBit `moon prove` | Proof of equivalence or input that separates versions |
| Mathematical assumptions inside code or protocols | Interactive proof over open inductive domains | Lean 4 / Rocq | Durable theorem with checked proof term |
| Informal crypto/security protocol reasoning | Dolev-Yao style symbolic protocol model | Tamarin / ProVerif | Attack trace or secrecy/authentication proof |

The adoption rule is: do not start by asking "which prover is best?"
Start by asking which existing manual activity is expensive,
ambiguous, or repeatedly wrong.

## Pick by Purpose

| Purpose | Adopt first | Use when | Avoid when |
| --- | --- | --- | --- |
| Find bad inputs to a pure predicate | Z3 | The implementation already has a mostly pure decision function; you want witnesses | The property depends on event order or concurrency |
| Check structural consistency | Alloy | The domain is entities and relations: roles, owners, tenants, routes, graph reachability | The real bug needs fairness, unbounded queues, or long-running time |
| Check async safety | TLA+ | You need "nothing bad ever happens" across all action orderings | A finite relational model would show the same issue faster |
| Check async liveness | TLA+ | You need "something good eventually happens" and fairness assumptions are load-bearing | The system has no meaningful progress property |
| Check actor protocols close to implementation | P | The system is naturally machines exchanging typed messages, and executable spec/codegen matters | You only need a design-level model |
| Prove sequential code contracts | Dafny | You can write or mirror the function in Dafny and specify pre/post/invariants | The production code must stay in another language with no translation budget |
| Prove MoonBit implementation contracts | MoonBit `moon prove` | The implementation is MoonBit; contracts and proof-only models can live beside code | You need Z3-style model extraction or temporal exploration |
| Prove reusable math or type-level facts | Lean 4 | The theorem is universal over arbitrary future values, not a bounded scope | A bounded counterexample would answer the engineering question |
| Reuse mature proof ecosystems | Rocq | You need CompCert, Iris, MetaCoq, or another Rocq-specific library | Lean/mathlib covers the theorem with less ceremony |
| Verify C without rewriting | CBMC / Frama-C | The codebase is C and bounded checks or ACSL annotations fit | You can isolate the logic into a cleaner pure model |
| Verify Rust with ownership-aware specs | Verus | You want Rust-shaped code plus pre/post/ghost reasoning | The target is not Rust or the team cannot absorb a verifier subset |

## Pick by Artifact

| Artifact you want to leave behind | Best fit | Why |
| --- | --- | --- |
| CI validator for real config files | Z3 | Directly encodes config predicates and returns a stable exit code |
| Counterexample for a design review | Alloy or TLA+ | Produces a concrete instance or trace people can discuss |
| Regression guard for a pure rule | Z3 or Dafny | Locks the rule after a bug is found |
| Regression guard for MoonBit code | MoonBit `moon prove` | Keeps contract and implementation in the same package |
| Executable protocol model | P | The spec is already state machines and messages |
| Durable theorem independent of implementation | Lean 4 or Rocq | Proof survives implementation rewrites |
| Proof-carrying data-structure API | MoonBit `moon prove`, Dafny, Why3 | Abstract model can stay stable while representation changes |

## What Each Language Can Prove

| Language / tool | Proves well | Typical real-world target | Counterexample quality | Repository example |
| --- | --- | --- | --- | --- |
| Z3 / SMT-LIB | Satisfiability, unsatisfiability, equivalence of first-order formulas over supported theories | Validators, feature flags, eligibility, wire compatibility, config reachability | High when `get-model` is used; otherwise SAT/UNSAT only | `languages/z3/checkout_form.smt2` |
| Alloy 6 | Bounded relational facts and temporal assertions over small scopes | RBAC, ownership, tenant isolation, workflow reachability, graph-shaped infra | High; concrete relation instance and visualizable graph | `languages/alloy/app-rbac.als`, `languages/alloy/multi-tenant.als`, `usecases/terraform-reachability/` |
| TLA+ / TLC | Safety and liveness over state transitions and action interleavings | Distributed protocols, retry loops, background jobs, event sourcing, queues | High; numbered execution trace with action names | `languages/tla/OrderCheckout.tla`, `languages/tla/ActorMailbox.tla` |
| P | Safety over actor state machines and message schedules | Actor protocols, device/service protocols, generated state-machine code | High; reproducible schedule | `languages/p/PingPong/` |
| Dafny | Sequential program contracts, loop invariants, algebraic datatypes, ghost state | Business-rule functions, parsers, normalizers, data transformations | Medium; source location and failed obligation | `languages/dafny/checkout_form.dfy`, `languages/dafny/rbac_screens.dfy` |
| MoonBit `moon prove` | MoonBit function contracts, loop invariants, abstract models in `.mbtp`, representation invariants | MoonBit libraries, validators, finance/domain operations, data structures | Medium; proof obligation failure rather than model finder | `languages/moonbit/checkout_form/` |
| Lean 4 | Universal theorems over inductive types, mathematical structures, executable definitions with proofs | Permission lattices, type-level laws, algorithms whose proof outlives an implementation | Low for bug hunting; high for final theorem confidence | `languages/lean/Rbac.lean` |
| Rocq | Mature interactive proofs, program semantics, separation logic via Iris, compiler/kernel-grade proofs | Compiler correctness, concurrent data structures, mechanized semantics | Low for quick counterexamples; very high for proof artifacts | Not currently probed |
| Why3 | Verification-condition generation with multiple prover backends | Shared verification backend, algorithm proofs, hand-authored WhyML | Medium; depends on backend/prover reports | Used by MoonBit `moon prove` |
| Verus | Rust-like program verification with ghost/spec code | Rust modules with ownership-sensitive invariants | Medium; verifier diagnostics | Not currently probed |
| Tamarin / ProVerif | Symbolic security protocol secrecy/authentication | Login protocols, key exchange, token flows, adversarial message systems | High; attack trace | Not currently probed |
| CBMC | Bounded C execution paths | C functions, embedded checks, memory-safety assertions under unwind bounds | Medium; bounded trace | Not currently probed |

## Replacement Ladder

Adopt in this order when moving a normal product codebase toward
formal checks:

1. Extract pure predicates and run Z3 against real examples.
2. Model structural domain rules in Alloy and collect counterexamples.
3. Move async protocols that survived Alloy into TLA+ only when order,
   fairness, or liveness becomes load-bearing.
4. Put code-level contracts on new sequential logic in Dafny or
   MoonBit `moon prove`.
5. Escalate to Lean / Rocq only for reusable theorems or proof
   ecosystems that justify the cost.

This keeps the first artifact close to the bug class. Most product
teams should get value from steps 1 and 2 before touching an
interactive theorem prover.

## How to Read This Repository

| If your question is... | Start here |
| --- | --- |
| "Which tool should I try first?" | `verification-tools.md` |
| "What is each tool good or bad at?" | `book/tool-fit-map.md` |
| "What manual process can this replace?" | This file |
| "What did each probe teach?" | `findings.md` |
| "How does MoonBit prove compare to Z3?" | `languages/moonbit/MOON_PROVE_CAPABILITIES.md` |
| "How do I run the checks?" | `README.md` and `justfile` |

The expected final deliverable for a real project is not a pile of
proofs. It is a ledger of:

```text
expected spec / implementation claim -> machine check -> counterexample or contract -> domain decision
```

If the domain owner says a counterexample is intended, write it down
as the spec. If not, it is a bug.
