# Verification tools: when to reach for which

A pragmatic guide to picking among proof assistants, model checkers,
and SMT-backed verifiers. Written from the perspective of someone
who has a specific property they want to express and check, not
someone shopping for a research career.

The headline takeaway is that **these are not interchangeable
tools — they answer different questions**. The first job is to
classify your problem along three axes, then the tool falls out.

---

## The three axes

| Axis | Endpoints |
| --- | --- |
| State space | finite & small / infinite & abstract |
| Output | counter-example / proof certificate |
| Author effort | annotation only / interactive proof |

Map your problem onto these and most of the catalog below
collapses to one or two candidates.

```
                          finite & small        infinite & abstract
                          ───────────────────   ───────────────────
counter-example only      Alloy, Spin, P        TLA+ (TLC), CBMC
proof certificate         Alloy (extended)      Lean, Rocq, Isabelle
annotation + SMT          Dafny, Why3, Verus    Dafny + ghost, F*
```

This is rough — Alloy can do bounded proof, Lean can do model
finding via decide, etc. — but the heatmap is right.

---

## Decision matrix by use case

| You want to check | Reach for | Why |
| --- | --- | --- |
| RBAC / access control / config invariants | **Alloy** | relational logic is native; small-scope hypothesis catches the real bugs |
| Screen-navigation graph + role permissions | **Alloy 6** | temporal extension + relational logic in one tool |
| Async / distributed protocol safety + liveness | **TLA+** (TLC for bounded, Apalache for symbolic) | Lamport built it for exactly this; fairness / liveness are primitive |
| State machine + message-passing semantics | **P** or **TLA+** | P has explicit message-handler syntax; TLA+ is more general |
| Sequential algorithm with pre/post + loop invariants | **Dafny** or **Why3** | SMT discharges; low ceremony; output is "verified / not verified" |
| Imperative Rust with ownership-aware specs | **Verus** | borrow checker maps to separation logic; less proof work than Coq+Iris |
| Compiler / interpreter / OS kernel correctness | **Rocq** | CompCert + seL4 + MetaCoq ecosystem; nobody else has the precedent |
| Concurrent data structures + heap invariants | **Iris (in Rocq)** | concurrent separation logic; research-grade but battle-tested |
| Math theorems (analysis, algebra, combinatorics) | **Lean 4** + mathlib4 | by far the largest live math library; modern tactic story |
| Security protocols (Needham-Schroeder, TLS handshakes) | **Tamarin** / **ProVerif** | symbolic crypto reasoning, Dolev-Yao adversary baked in |
| One-shot SMT check ("is this formula SAT?") | **Z3** / **CVC5** directly | no language overhead; SMT-LIB or python binding |
| Quick "does any 5-step trace violate X?" | **Alloy** | minutes to a working model; visual counter-examples |

---

## Tool one-liners

### Model finders / model checkers (finite-state-ish)

**Alloy 6** — relational logic, finite-scope model finder. Sweet
spot: structural and access-control properties where the bug
manifests in scope 3–5. Counter-examples come back as graph
instances; the Analyzer visualiser is part of the language's
identity. Temporal extension (`always`, `eventually`, `next`)
since v6 covers state-machine flavour problems too. **Don't reach
for it** when your state space is genuinely large (linear in time,
hundreds of components) — scope exhaustion is real.

**TLA+** (with TLC, Apalache, TLAPS) — temporal logic of actions
+ Zermelo-Fraenkel set theory as the surface language. Built for
async distributed systems: state, next-state relation, fairness,
liveness all primitives. TLC is the bounded model checker, Apalache
the symbolic one, TLAPS the proof assistant. Surface syntax is
math-heavy (lots of `[]` and `<>`) — PlusCal is a more readable
imperative wrapper. **Don't reach for it** for structural / RBAC
questions where Alloy's relational logic is more direct.

**Spin** + **Promela** — explicit-state model checker, older than
TLA+, still the workhorse for protocol verification in industry.
LTL / safety / never claims. Promela syntax is C-flavoured.
**Reach for it** if you have an existing Promela model or need
the maturity for safety-critical certification.

**P** (Microsoft) — domain-specific language for asynchronous
state machines with typed message passing. Generates both
executable code and a model for verification. **Reach for it**
when the system *is* a network of state machines with messages —
USB stack, distributed cache eviction, etc.

**Stateright** — Rust library that gives you a model checker as
a crate. **Reach for it** when you want to keep authoring in Rust
and use the same types in the model and the implementation.

### Auto / SMT-backed verifiers (annotation style)

**Dafny** — imperative-with-functional ML-flavoured language;
annotate `requires`, `ensures`, `invariant`, `decreases`. SMT
discharges most obligations automatically. Sweet spot: sequential
algorithms with non-trivial invariants (sorting variants, hash
tables, parsers). Has had a long beta life and tooling improves
slowly. **Don't reach for it** for concurrency-heavy properties
(weak), temporal properties (no), or programs you don't want to
re-author in Dafny.

**Why3** — multi-prover frontend; you can route SMT obligations
to Z3 / CVC5 / Alt-Ergo, and unsolved ones to Rocq / Isabelle.
Sweet spot: when you don't want to commit to one backend. WhyML
is the surface language. Less polish than Dafny but more flexible.

**Verus** — Rust-flavoured Dafny. Pre/post conditions, ghost
code, mode system that lets you mix verified and unverified
modules. Targets Rust source with `verus!` macro. **Reach for
it** when you want verification for Rust without leaving Rust.

**F*** — Microsoft Research; refinement types + SMT + ITP in
one. Used for HACL\* (cryptographic library), EverParse, miTLS.
Higher ceiling than Dafny, steeper curve. **Reach for it** when
the proof obligation needs both SMT auto and occasional manual
tactic, and the project can absorb the language.

**SPARK** (Ada subset) — industrial verifier with decades of
certification track record. **Reach for it** when you need
DO-178C / EN 50128 evidence; otherwise probably not.

**Frama-C / ACSL** — verifier for C with annotation language.
**Reach for it** when the codebase is C and rewriting in Rust /
Dafny is off the table.

### Interactive theorem provers (proof style)

**Lean 4** — modern dependent-type ITP. mathlib4 is the largest
live math library in any ITP (group theory, analysis, category
theory, combinatorics). Tactic story is good. Performance is
fine for most things, sometimes painful for big metatheory.
Sweet spot: math; program verification when refinement types
don't reach. **Reach for it** as the default ITP today.

**Rocq** (renamed from Coq, 2025) — older sibling. Has
CompCert (verified C compiler), seL4 (verified microkernel),
MetaCoq (verified Coq metatheory), Iris (concurrent separation
logic). Notation heavier than Lean, automation weaker than
Isabelle, ecosystem the most mature. **Reach for it** when one
of those flagship libraries is exactly what you need.

**Isabelle/HOL** — classical HOL with Sledgehammer (the best
SMT/ATP hammer in the ITP world). Strong for protocols
(Isabelle/HOL has the original verified TLS proof, NS-Lowe,
etc.) and program semantics. Surface is uglier than Lean.
**Reach for it** when you need the hammer for goal-soup and
classical logic fits.

**Agda** — dependent-type-as-programming-language; less
automation, more "write the proof as a function" style.
**Reach for it** if you treat proofs as programs and want
dependent pattern matching to be the central activity.

### Specialised

**Iris** (Rocq library) — concurrent separation logic with
ghost state, invariants, weakest preconditions. The framework
behind RustBelt (Rust borrow checker correctness). **Reach
for it** when sequentialising the proof in your head is too
hard — concurrent data structures, lock-free algorithms, weak
memory models.

**Tamarin** / **ProVerif** — symbolic protocol verifiers. Both
take a protocol description and a Dolev-Yao adversary, then
verify secrecy / authentication / etc. Tamarin is more
expressive (equational theories), ProVerif faster on classical
cases.

**Z3** / **CVC5** / SMT-LIB directly — when the property is
small enough that you just want to push it to a solver. Often
the answer is "embed the question in 50 lines of SMT-LIB and
get an answer in a second."

**CBMC** — bounded model checker for C. Unwinds loops a fixed
number of times, encodes the result to SAT. **Reach for it**
when you want to verify a specific C function against a
property without rewriting it.

---

## Tool-picking heuristics

1. **Can the property be expressed by listing 3–5 entities and
   their relations?** → Alloy. The "small scope hypothesis"
   says most real bugs are findable with 3–5 instances of each
   type. RBAC, file systems, address books, refactoring
   patterns all live here.

2. **Does the property involve time / "eventually" / fairness?**
   → TLA+ if the state space is huge or infinite, Alloy 6 if
   the temporal claims live alongside relational ones in a
   bounded model.

3. **Is there an actual program you want to verify, written
   in a specific language?** → annotation-style. Rust → Verus,
   C → Frama-C, anything-greenfield → Dafny.

4. **Is the claim a universal mathematical theorem you don't
   want to bound?** → ITP. Lean 4 unless a Rocq / Isabelle
   library is decisive.

5. **Are you verifying a concurrent or distributed protocol?**
   → TLA+ for the spec layer, Iris in Rocq if you need to
   verify the implementation against the spec.

6. **Are you doing security protocol verification?** → Tamarin
   or ProVerif. Don't reinvent symbolic crypto reasoning.

---

## What not to do

- **Don't reach for an ITP when a model checker would do.**
  "I want to verify my access control" is usually answered in
  an hour with Alloy, not in a quarter with Lean.
- **Don't reach for a model checker when an ITP would do.**
  "I want to know my sort is correct for all inputs" is not
  a model-checker question.
- **Don't put a thick DSL on top of any of these.** The
  authoring language *is* the value proposition. A Pkl-to-Alloy
  transpiler that hides Alloy's relational logic produces
  something worse than `.als` — the user reads the generated
  Alloy on counter-example anyway. (Loose coupling via spec
  cross-reference is fine; thick translation is not.)
- **Don't pick by familiarity alone.** "I know Coq" is a fine
  reason to use Rocq for a one-off, but for a multi-year
  project, pick by problem fit.

---

## Probes worth building under `experiments/`

Open invitations rather than commitments — each is a
small self-contained probe that proves out a tool against a
realistic pkspec-ish scenario.

- `state-verifier/app-rbac.als` — done. Alloy 6 model of
  RBAC + screen navigation.
- `state-verifier/protocol.tla` — TLA+ spec of a small
  background-process readyProbe loop with timeouts. Mirrors
  pkspec's `parallel.background` scenario, but in a model
  checker. Reveals whether the Pkl-level spec admits any
  trace that the implementation forbids (or vice versa).
- `state-verifier/sort.dfy` — Dafny verification of a single
  algorithm. Pure SMT-backed annotation work; serves as the
  "this is what auto verification feels like" baseline.
- `state-verifier/invariants.lean` — Lean 4 sketch of a
  universally quantified property over pkspec's Tally.IsGreen
  logic. Demonstrates when proof actually buys something the
  test suite cannot.

Each probe should end with a short note in `findings.md`
recording what the tool was good at, what it was bad at, and
whether it earned a slot in any future pkspec workflow.
