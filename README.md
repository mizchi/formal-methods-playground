# prove-playground

Learning sandbox for proof assistants, model checkers, and SMT
verifiers. One directory per tool, each holding small probes
that exercise a single property against a realistic scenario.

The goal is **comparative literacy**: the same shape of problem
re-expressed in each tool, so the differences in surface syntax,
counter-example style, and effort cost become concrete.

## Layout

| Dir | Tool | Style |
| --- | --- | --- |
| [`alloy/`](alloy/) | Alloy 6 | finite-scope relational model finder |
| [`tla/`](tla/) | TLA+ (TLC / Apalache / TLAPS) | temporal logic for async / distributed |
| [`dafny/`](dafny/) | Dafny | SMT-backed program verification |
| [`lean/`](lean/) | Lean 4 + mathlib4 | interactive theorem prover |
| [`rocq/`](rocq/) | Rocq (née Coq) | older ITP, mature ecosystem |
| [`moonbit/`](moonbit/) | MoonBit `moon prove` | Dafny-style annotations → Why3 → SMT |
| [`terraform-reachability/`](terraform-reachability/) | Alloy applied | microservice reachability graph from terraform SGs |

## Tool selection guide

[`verification-tools.md`](verification-tools.md) — when to reach
for which tool, organised by use case. Read this first if the
question is "which one should I pick for problem X" rather than
"how do I write X in tool Y".

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
| Alloy | `alloy/app-rbac.als` | RBAC + screen navigation; UNSAT / SAT all 3 commands |
| TLA+ | `tla/OrderCheckout.tla` | async order state machine + safety + liveness; 20 states, depth 6 |
| Dafny | `dafny/checkout_form.dfy` | conditional form invariants + loop verification; 7 verified, 0 errors |
| Dafny | `dafny/rbac_screens.dfy` | same RBAC + screen-nav domain as the Alloy probe, proved universally over trace length; 12 verified, 0 errors |
| Lean | `lean/Rbac.lean` | RBAC role-hierarchy monotonicity, universal over Permission |
| MoonBit | `moonbit/checkout_form/` | translates to Why3 cleanly; prover step blocked by Why3 1.8.2 ↔ Z3 4.16 / CVC5 1.3 version regex mismatch |
| Alloy applied | `terraform-reachability/` | 3-service stack + SG ingress edges; direct safety UNSAT, transitive surfaces proxy-chain path |
| Rocq | — | covered by Lean for ITP duties; revisit when a flagship library (CompCert / Iris) becomes load-bearing |

See [`findings.md`](findings.md) for the comparative
notes — surface readability, counter-example quality, and the
per-use-case picking matrix that came out of running all four.
