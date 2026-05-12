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
| Alloy | `app-rbac.als` | RBAC + screen navigation; complete |
| TLA+ | — | next probe candidate: async background-process readyProbe |
| Dafny | — | next probe candidate: a single verified sort |
| Lean | — | next probe candidate: a small universally-quantified invariant |
| Rocq | — | optional; revisit when a flagship library (CompCert / Iris) becomes load-bearing |
