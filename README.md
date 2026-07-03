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
| [`languages/dafny/`](languages/dafny/) | Dafny | SMT-backed program verification |
| [`languages/fstar/`](languages/fstar/) | F* | refinement types + SMT for verified implementation cores |
| [`languages/lean/`](languages/lean/) | Lean 4 + mathlib4 | interactive theorem prover |
| [`languages/rocq/`](languages/rocq/) | Rocq (née Coq) | older ITP, mature ecosystem |
| [`languages/moonbit/`](languages/moonbit/) | MoonBit `moon prove` | Dafny-style annotations → Why3 → SMT |
| [`usecases/terraform-reachability/`](usecases/terraform-reachability/) | Alloy applied | microservice reachability graph from terraform SGs |
| [`languages/p/`](languages/p/) | P language | actor-model state machines with built-in checker |

## Tool selection guide

[`verification-tools.md`](verification-tools.md) — when to reach
for which tool, organised by use case. Read this first if the
question is "which one should I pick for problem X" rather than
"how do I write X in tool Y".

[`real-world-adoption.md`](real-world-adoption.md) — what these
tools replace in normal engineering work, which tool to adopt by
purpose, and what each language can prove. Japanese version:
[`real-world-adoption.ja.md`](real-world-adoption.ja.md).

GitBook draft outline: [`book/README.md`](book/README.md) and
[`book/SUMMARY.md`](book/SUMMARY.md).

## Probe naming convention

`<tool>/<topic>.<ext>` — one file per probe when small, one
subdirectory when the probe needs multiple files. Each probe
should have a top-of-file comment block with:

1. What property is being verified.
2. What tool command runs it.
3. What pass / fail looks like.
4. (Optional) A breaking variant — "weaken X and re-run, expect
   counter-example Y" — so the verifier's discrimination power
   is testable from the file itself.

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
| Dafny | `languages/dafny/checkout_form.dfy` | conditional form invariants + loop verification; 7 verified, 0 errors |
| Dafny | `languages/dafny/rbac_screens.dfy` | same RBAC + screen-nav domain as the Alloy probe, proved universally over trace length; 12 verified, 0 errors |
| F* | `languages/fstar/CheckoutForm.fst` | checkout-form constructors carry refinement contracts; invalid witnesses proved false with lemmas |
| Lean | `languages/lean/Rbac.lean` | RBAC role-hierarchy monotonicity, universal over Permission |
| MoonBit | `languages/moonbit/checkout_form/` | executable tests pass; `moon prove` succeeds with opam Why3 1.7.2 + Alt-Ergo 2.5.4; 5 goals proved |
| Alloy applied | `usecases/terraform-reachability/` | 3-service stack + SG ingress edges; direct safety UNSAT, transitive surfaces proxy-chain path |
| P | `languages/p/PingPong/` | two-actor ping-pong + safety monitor; 1000 schedules, 0 bugs |
| Rocq | `languages/rocq/Rbac.v` | RBAC role-hierarchy monotonicity smoke probe; revisit when a flagship library (CompCert / Iris) becomes load-bearing |

See [`findings.md`](findings.md) for the comparative
notes — surface readability, counter-example quality, and the
per-use-case picking matrix that came out of running all four.
