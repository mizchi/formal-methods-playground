# formal-methods-playground

Learning sandbox for proof assistants, model checkers, and SMT
verifiers. One directory per tool, each holding small probes
that exercise a single property against a realistic scenario.

The goal is **comparative literacy**: the same shape of problem
re-expressed in each tool, so the differences in surface syntax,
counter-example style, and effort cost become concrete.

## Layout

| Dir | Tool | Style |
| --- | --- | --- |
| [`languages/alloy/`](languages/alloy/) | Alloy 6 | finite-scope relational model finder |
| [`languages/z3/`](languages/z3/) | Z3 | direct SMT checks for implementation-extracted predicates |
| [`languages/tla/`](languages/tla/) | TLA+ (TLC / Apalache / TLAPS) | temporal logic for async / distributed |
| [`languages/quint/`](languages/quint/) | Quint (TLC backend) | typed, executable TLA-style specifications |
| [`languages/fizzbee/`](languages/fizzbee/) | FizzBee | Python-like distributed-system design specifications, visualization, and model checking |
| [`languages/dafny/`](languages/dafny/) | Dafny | SMT-backed program verification |
| [`languages/fstar/`](languages/fstar/) | F* | refinement types + SMT for verified implementation cores |
| [`languages/lean/`](languages/lean/) | Lean 4 + mathlib4 | interactive theorem prover |
| [`languages/rocq/`](languages/rocq/) | Rocq (formerly Coq) | interactive proofs for compiler / semantics and a mature ecosystem |
| [`languages/moonbit/`](languages/moonbit/) | MoonBit `moon prove` | Dafny-style annotations → Why3 → SMT |
| [`usecases/terraform-reachability/`](usecases/terraform-reachability/) | Alloy applied | microservice reachability graph from terraform SGs |
| [`usecases/wasmplane-route-placement/`](usecases/wasmplane-route-placement/) | Alloy applied | route snapshot placement bug witnesses and fixed-contract checks |
| [`usecases/offline-sync-convergence/`](usecases/offline-sync-convergence/) | Alloy applied | offline-first LWW merge: strong eventual consistency and its clock assumption |
| [`usecases/idempotency-key/`](usecases/idempotency-key/) | TLA+ applied | at-least-once retry: no double side effect, and no wedged key |
| [`usecases/write-skew-seat-limit/`](usecases/write-skew-seat-limit/) | TLA+ applied | write skew on a seat limit under snapshot isolation |
| [`usecases/schema-evolution/`](usecases/schema-evolution/) | Z3 applied | rolling-deploy compatibility in both directions |
| [`languages/p/`](languages/p/) | P language | actor-model state machines with built-in checker |

## Tool selection guide

[`docs/personal-tool-selection.md`](docs/personal-tool-selection.md) —
personal defaults for this repository: Alloy 6 for structure, Quint
for behavior, and Lean 4 for durable unbounded theorems, with explicit
escape hatches for other question shapes.

[`docs/quint-ecosystem.md`](docs/quint-ecosystem.md) —
how Quint LLM Kit, Choreo, Connect, ITF export, and Trace Explorer extend
the workflow from model authoring through implementation conformance and
counterexample review, including their trust boundaries and maturity.

[`docs/quint-ecosystem-evaluation.md`](docs/quint-ecosystem-evaluation.md) —
hands-on evaluation using the pinned official two-phase-commit examples:
an 8-state Choreo/ITF trace, Connect positive and deliberately broken Rust
implementations, terminal trace exploration, and a MoonBit runtime adapter that
generates and replays both simulation and named-test traces.

[`docs/rocq-vs-lean-program-verification.md`](docs/rocq-vs-lean-program-verification.md) —
an attributed reading note on the Lean / Rocq boundary: native codata,
extraction, program-verification ecosystems, proof boundaries, and the
resulting repository decision.

[`docs/dafny-code-generation.md`](docs/dafny-code-generation.md) —
how verified Dafny code translates to JavaScript / Go, what appears in the
generated artifacts, bundle and performance measurements, Rust backend status,
and the design and CI practices needed around the generated core.

[`docs/lean-c-wasm.md`](docs/lean-c-wasm.md) —
the verified Lean → generated C → freestanding WebAssembly probe, including
the scalar ABI restriction, Emscripten scalar/runtime-backed routes, generated
output, bundle/runtime size, upstream patch, and trust boundary.

[`verification-tools.md`](verification-tools.md) — when to reach
for which tool, organised by use case. Read this first if the
question is "which one should I pick for problem X" rather than
"how do I write X in tool Y".

[`real-world-adoption.md`](real-world-adoption.md) — what these
tools replace in normal engineering work, which tool to adopt by
purpose, and what each language can prove. Japanese version:
[`real-world-adoption.ja.md`](real-world-adoption.ja.md).

[`extraction-playbook.md`](extraction-playbook.md) — the other
axis: pointing these tools at an **existing codebase** instead of a
synthetic probe. Where a checkable claim hides in real code, how to
anchor a model to its source, and the model→executable-repro
credibility ladder that makes a finding believable. Read this when
the question is "there is a real program — what do I model, and how
do I trust the result".

[`book/06-timing.md`](book/06-timing.md) — the third axis. The
bug-pattern catalog says *what* can be checked and the tool-fit map says
*which tool*; this chapter says **when** — design, editor, PR gate,
migration, rollout, runtime, postmortem — with the pattern x timing
matrix and the arXiv evidence behind each slot. Read this when the
question is "we know this is checkable, but is now the moment".

GitBook draft outline: [`book/README.md`](book/README.md) and
[`book/SUMMARY.md`](book/SUMMARY.md).

## Probe naming convention

`<tool>/<topic>.<ext>` — one file per probe when small, one
subdirectory when the probe needs multiple files. Each probe
should have a top-of-file comment block with:

1. What property is being verified.
2. What tool command runs it.
3. What pass / fail looks like.
4. A breaking variant — "weaken X and re-run, expect
   counter-example Y" — so the verifier's discrimination power
   is testable from the file itself. A probe that only ever
   shows green has not earned trust; the witness side is what
   proves the check still discriminates. (This is the
   dual-check discipline of the
   [extraction playbook](extraction-playbook.md); required for
   extracted models, expected for synthetic probes too.)

## Status

| Tool | Probes | Notes |
| --- | --- | --- |
| Alloy | `languages/alloy/app-rbac.als` | RBAC + screen navigation; UNSAT / SAT all 3 commands |
| Alloy | `languages/alloy/multi-tenant.als` | tenant isolation; cross-tenant read UNSAT, billing-admin override SAT |
| Alloy | `languages/alloy/workflow-approval.als` | expense-approval state machine; no self-approval / monotonic resolution / approval-via-review all UNSAT |
| Z3 | `languages/z3/checkout_form.smt2` | MoonBit checkout predicate mirror; fail-closed / email guard UNSAT, broken variant SAT |
| TLA+ | `languages/tla/OrderCheckout.tla` | async order state machine + safety + liveness; 20 states, depth 6 |
| TLA+ | `languages/tla/EventSourcing.tla` | replay determinism + snapshot consistency on a payment ledger; 118 states, depth 5 |
| TLA+ | `languages/tla/ActorMailbox.tla` | per-pair FIFO + bounded mailbox + eventual delivery under WF on Receive; 1,681 states, depth 13 |
| Quint | `languages/quint/OrderCheckout.qnt` | typed restatement of the TLA+ checkout model; the same 20 states / depth 6, plus a broken-step witness |
| Quint + MoonBit | [`mizchi/quint-connect-moonbit`](https://github.com/mizchi/quint-connect-moonbit) | standalone package `mizchi/quint_connect`; MoonBit launches Quint and replays 8 generated traces / 34 states plus a nested named-test trace, with negative controls for both paths |
| FizzBee | `languages/fizzbee/OrderCheckout.fizz` | Python-like design restatement; 20 unique states, plus safety and no-fairness witnesses |
| Dafny | `languages/dafny/checkout_form.dfy` | conditional form invariants + loop verification; 7 verified, 0 errors |
| Dafny | `languages/dafny/rbac_screens.dfy` | same RBAC + screen-nav domain as the Alloy probe, proved universally over trace length; 12 verified, 0 errors |
| Dafny | `languages/dafny/dijkstra.dfy` | immutable reference + mutable-array Dijkstra; ghost path witnesses and universal shortest-distance proof; translates to JS / Go |
| F* | `languages/fstar/CheckoutForm.fst` | checkout-form constructors carry refinement contracts; invalid witnesses proved false with lemmas |
| Lean | `languages/lean/Rbac.lean` | RBAC role-hierarchy monotonicity, universal over Permission |
| Lean + Wasm | `languages/lean/wasm/` | verified scalar and `String` cores → C → freestanding/Emscripten Wasm; Node execution tests |
| Rocq | `languages/rocq/StackCompiler.v` | compiler correctness for every expression and initial stack; reversed-subtraction negative control |
| Rocq | `languages/rocq/Rbac.v` | Leanとの最小構文比較として残す RBAC monotonicity probe |
| MoonBit | `languages/moonbit/checkout_form/` | executable tests pass; `moon prove` succeeds with opam Why3 1.7.2 + Alt-Ergo 2.5.4; 5 goals proved |
| Alloy applied | `usecases/terraform-reachability/` | 3-service stack + SG ingress edges; direct safety UNSAT, transitive surfaces proxy-chain path |
| Alloy applied | `usecases/wasmplane-route-placement/` | wasmplane route snapshot placement bugs; legacy witnesses SAT, fixed-contract checks UNSAT |
| P | `languages/p/PingPong/` | two-actor ping-pong + safety monitor; 1000 schedules, 0 bugs |
| TLA+ applied | `usecases/idempotency-key/` | idempotency keys under retry; correct design green (16 states, depth 8), late-store witness `charges = 2`, blocking witness wedges at `reserved` |
| TLA+ applied | `usecases/write-skew-seat-limit/` | seat limit under SI/SSI/row lock; SERIALIZABLE and FOR UPDATE green, snapshot isolation witnesses `members = 2` on a 1-seat plan |
| Alloy applied | `usecases/offline-sync-convergence/` | LWW merge convergence; 4 checks UNSAT, 4 witnesses SAT (naive tie, no unique winner, repeated stamp, non-vacuity) |
| Z3 applied | `usecases/schema-evolution/` | rolling-deploy compatibility both directions; `sat, sat, unsat, unsat, sat, unsat` |

See [`findings.md`](findings.md) for the comparative
notes — surface readability, counter-example quality, and the
per-use-case picking matrix that came out of running all four.
