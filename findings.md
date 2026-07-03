# Findings — when each tool actually earned its slot

Raw notes from running each probe against an application-level
spec. Written after the fact, with the lesson it taught.

The probes are all in the repo:

| Tool | Probe | What it expresses |
| --- | --- | --- |
| Z3 | `languages/z3/checkout_form.smt2` | implementation-extracted checkout predicate + broken-variant witness |
| Alloy 6 | `languages/alloy/app-rbac.als` | RBAC + screen-navigation safety + sanity |
| TLA+ | `languages/tla/OrderCheckout.tla` | async order state machine + safety + liveness |
| Dafny | `languages/dafny/checkout_form.dfy` | conditional form invariants + loop verification |
| Lean 4 | `languages/lean/Rbac.lean` | role-hierarchy monotonicity, universal proof |

---

## Z3 — implementation-extracted checkout predicate

### What it expresses well

The MoonBit implementation exposes a pure decision function:

```text
valid =
  total > 0
  && (
       kind == physical_kind && has_shipping
       || kind == digital_kind && email_len > 0
     )
```

Z3 is the shortest path from that function to concrete
"does this bad input exist?" questions. The probe asks whether
an unknown kind can validate and whether a digital order with
`email_len <= 0` can validate; both are `unsat`.

It also carries a broken variant that forgets the digital email
guard. Against that variant the same class of bad input becomes
`sat`, so the harness is load-bearing rather than merely green.

### What I tripped on

SMT-LIB's `check-sat` output does not make the process fail when
the answer is unexpected. The wrapper script
`languages/z3/check_checkout_form.sh` compares the full expected answer
sequence:

```text
unsat
unsat
sat
sat
sat
```

That gives a human-readable trace and a CI-usable exit code.

### Surface readability score

**7 / 10** for tiny predicates, **4 / 10** once the domain stops
being simple integers and booleans. The model is honest and
direct, but the domain vocabulary is thinner than Alloy or Dafny.

### Counter-example quality

By default the current probe only prints `sat` / `unsat` because
the wrapper wants a stable output contract. Add `get-model` when
debugging a specific failure; keep it out of the CI path unless
the expected model is intentionally pinned.

### When to reach for it again

Pure, data-shaped predicates extracted from implementation:
feature flags, eligibility, config validation, branch coverage,
wire-value compatibility, and old-vs-new equivalence checks.
If the question involves state transitions over time, move to
TLA+; if it is mostly relations over entities, Alloy reads better.

---

## Alloy 6 — RBAC + screen navigation

### What it expresses well

Relations are first-class. `role`, `at`, `LoggedIn` are all
relations; `allowedFor[r]` is a function returning a set, written
exactly like a lookup table. Safety properties read like English:

```
assert NonAdminNeverAtSettings {
  always (all u: LoggedIn |
    u.role != Admin implies u.at != Settings)
}
```

That maps 1:1 to "no non-admin is ever observed at Settings."
No bookkeeping, no manual encoding of the transition system —
`always` + `implies` is just there.

### What I tripped on

`alloy6 exec` (Nix package name; the doc-traditional spelling is
`alloy execute`). On second run, the per-command output dir
(`languages/alloy/app-rbac/`) already existed and the CLI refused to
overwrite without `-f`. Easy fix; documented in `languages/alloy/README.md`.

### Surface readability score

**9 / 10** for this domain. The model file is a faithful
machine-readable rewrite of the spec sentence.

### Counter-example quality

Visual graphs in the Analyzer GUI. CLI mode produces
`<Cmd>-solution-0.md` with the instance written as Alloy
relations. Easy to read for a 4-instance scope, harder past
scope 8.

### When to reach for it again

Any time the property is naturally relational: permission
hierarchies, configuration constraints, "are these two graphs
related," ownership / RBAC / namespace-scoping. Anything you
can draw as nodes-and-edges and check "does this property hold
in every small instance."

---

## TLA+ (TLC) — async order checkout

### What it expresses well

Async actions + fairness + liveness. The order state machine
has a `paymentPending` step that can resolve three ways
(`PaymentSucceeded`, `PaymentFailed`, `PaymentTimeout`), and we
want to assert *something will fire eventually* — not just
*nothing wrong fires*. That's the kind of question Alloy
shrugs at and TLA+ takes seriously:

```
Spec ==
    /\ Init
    /\ [][Next]_vars
    /\ WF_vars(PaymentSucceeded)
    /\ WF_vars(PaymentFailed)
    /\ WF_vars(PaymentTimeout)

PaymentResolves ==
    (state = "paymentPending") ~> (state \in {"paid", "cart", "cancelled"})
```

The `WF_vars(...)` clauses are the spec's contract with itself
about progress. Drop them and `~>` fails with a stutter-step
counter-example. That feedback loop is the value proposition.

### What I tripped on

TLC defaults to flagging deadlock. The order spec is by design
terminal in `cancelled` / `refunded` / `shipped` — no enabled
actions. First run produced a "Deadlock reached" error on the
trace `cart → cancelled`. Fixed with `CHECK_DEADLOCK FALSE` in
the `.cfg`. Real concurrency specs (servers, protocols) rarely
deadlock by design, so this is a probe-specific quirk; document
it in the config rather than mutate the spec.

### Surface readability score

**6 / 10**. The ASCII math (`/\` `\/` `\E` `~>` `[]` `<>`) is
a real barrier for review. PlusCal as an imperative wrapper
helps; pure TLA+ as written here is honest about being a math
language. The spec is small and structured, but a non-formalist
needs ~30 minutes of orientation before reading is useful.

### Counter-example quality

Best in class for state machines. The trace is a numbered list
of states with the action that fired between each, plus values
of every state variable. The
`State 1 ──[CancelCart]──> State 2` form is exactly the trace
a developer would want.

### When to reach for it again

Any spec where time / async / fairness is load-bearing.
Distributed protocols, retry semantics, eventual consistency,
ordering guarantees, "this background task can't get stuck."
Strongly preferred over Alloy when state space is unbounded
or fairness is the actual question.

---

## Dafny — checkout form validation

### What it expresses well

Conditional invariants on data, discharged by SMT. The form
predicate:

```
predicate IsValidForm(f: Form) {
  && f.total > 0
  && (match f.kind
        case Physical => f.shipping.Some?
        case Digital  => f.email.Some? && |f.email.value| > 0)
}
```

Reads like a piece of the actual product spec. Constructors
declare `ensures IsValidForm(f)` and Z3 closes the obligation
in milliseconds. The loop in `SumPrices` carries two invariants
(`total >= 0` and `i > 0 ==> total > 0`) and SMT handles the
case split between "first iteration" and "subsequent iterations"
without manual help.

### What I tripped on

Nothing for this probe. Dafny's sweet spot — sequential code +
pre/post + loop invariants — is its sweet spot exactly because
SMT auto-discharges it. The friction starts when the obligation
needs non-linear arithmetic or higher-order quantifiers; this
probe has neither.

### Surface readability score

**8 / 10**. Pre/post/loop-invariant annotations are a notation
overhead, but they ARE the proof — there's no separate proof
script. Closer to "writing typed code" than "writing math."
Reviewers who can read TypeScript or Rust can roughly read this.

### Counter-example quality

Dafny outputs are textual ("postcondition not established")
with a hint at the violating path. Less visual than Alloy /
TLA+ but the locations are precise (line + column of the
violating assertion).

### When to reach for it again

Sequential code where the bug is "an invariant gets broken on
some path." Most form-validation, data-normalisation,
parser-like, simple-algorithm work fits. Don't reach for it
when the answer needs temporal reasoning (TLA+) or universal
quantification with structural recursion (Lean).

---

## Lean 4 — RBAC monotonicity

### What it expresses well

Universal quantification over a structurally-defined type.
The Alloy probe checks RBAC for scope 4 — that's 4 users, 4
screens, 4 roles, with a finite trace. The Lean probe proves
the same kind of monotonicity property *for every Permission
that will ever exist in the type Permission*:

```
theorem viewer_subset_editor :
    ∀ p : Permission, permits .viewer p = true → permits .editor p = true := by
  intro p h
  cases p <;> simp_all [permits]
```

Add a new constructor to `Permission`, re-run, and Lean will
require you to handle the new case before the proof type-checks.
That's the integrity contract — the theorem stays true through
edits or fails type-checking.

### What I tripped on

First version used `intro p _` (discard the hypothesis),
expecting `simp [permits]` to close every case. The `manage`
case failed because the goal reduced to `false = true` and
without the discarded hypothesis there was no way to close it.
Switching to `intro p h` and `simp_all [permits]` propagates
the absurd hypothesis through the case split and the proof
closes vacuously. This is the kind of small tactic-language
detail you don't have in a model checker — there's nothing to
"prove" wrong, there's a goal that's open.

### Surface readability score

**5 / 10** for non-Lean users, **8 / 10** if `simp` and `cases`
are familiar. The notation is dependent-types; the proof script
is tactic-mode. Better than Coq notation, still further from
"plain code" than Dafny.

### Counter-example quality

Not a counter-example tool. Lean gives you "unsolved goal at
line N, case M" with the open proof state. That's *better*
than a counter-example if you're trying to fix a wrong proof,
*worse* if you're trying to find a violating instance — the
shape of "wrong" is different.

### When to reach for it again

Properties that are *theorems*, not bug-hunts. "This function
respects this invariant for every input" — that's a Lean job.
"There's no 4-user trace that triggers this state" — that's an
Alloy job. The two are not interchangeable.

---

## TLA+ — EventSourcing replay determinism + snapshot consistency

`languages/tla/EventSourcing.tla` — a payment ledger whose state (`balance`)
is derived from an append-only `log` of Deposit / Withdraw
events. The probe verifies the four invariants that any
event-sourcing implementation has to satisfy regardless of
sequencing:

  - `NonNegativeBalance` — Withdraw is guarded; the SMT confirms
    no reachable state goes negative.
  - `ReplayDeterminism` — at every step, `balance = Replay(0,
    log)`. The live state and the log-derived state never
    diverge.
  - `SnapshotIsPrefix` — `snapshot.seq` is always a prefix of
    `log`; snapshots only ever capture historical truth.
  - `SnapshotConsistency` — replaying tail events from a
    snapshot lands on the live balance. This is the
    "restart from snapshot" guarantee that makes snapshots
    useful at all.

TLC explores 118 distinct states at depth 5 (Amounts = {1,2},
MaxLogLen = 3). All four invariants hold.

### Why this is the right tool

The interesting question in EventSourcing is *temporal* —
"replay from any prefix matches the live state" only makes
sense as a property *across* states. Alloy 6's bounded scope
could express the same shape but TLA+'s `[][Next]_vars`
matches the operational pipeline more directly. The recursive
`Replay` operator + `Fold`-style invariant are TLA+'s exact
sweet spot.

### Sketch of additions

Schema migration (replay an old event format under a new
reducer), idempotency (dedup-by-id), and causal ordering
(events with happens-before respected) all slot into the same
shape — add the variable, add the action, the invariant chain
extends. Recommended next-probe target if the
event-sourcing direction matters for the actual project.

---

## Alloy — multi-tenant data isolation

`languages/alloy/multi-tenant.als` — sig hierarchy of `User × Tenant ×
Document × Role`. The integrity claim is that a Regular user
never reads a Document outside their own Tenant. Surface:

```
assert CrossTenantReadBlocked {
  all u: User, d: Document |
    (some ur: UserRole |
       ur.user = u and ur.role = Regular and CanRead[u, d])
      implies u.tenantOf = d.ownedBy
}
check CrossTenantReadBlocked for 4
```

Three results:

  - `CrossTenantReadBlocked`  UNSAT — Regular users stay in lane
  - `WithinTenantReachable`   SAT   — sanity, same-tenant reads work
  - `AdminOverrideBounded`    SAT   — BillingAdmin role is the
                                       intentional break-glass; this
                                       run surfaces the trace where
                                       cross-tenant access happens
                                       (architect must explicitly
                                       accept it)

Lesson: Alloy makes the "structural invariant + one carved-out
exception" pattern declarable rather than commented. The
override is an EXPRESSED part of the spec, not an undocumented
deviation.

---

## Alloy — workflow-approval state machine (temporal)

`languages/alloy/workflow-approval.als` uses Alloy 6's `var` + `always`
+ prime notation to express an expense-approval flow:

```
  submitted  →  underReview  →  approved
                          \─→  rejected
```

Verifies four claims:

  - `NoSelfApprovalAction`   UNSAT — `Approve` action's
                                      pre-condition forbids
                                      the submitter from
                                      approving their own
                                      request
  - `ApprovalRequiresReview` UNSAT — `approved` is reached
                                      only from `underReview`,
                                      never directly from
                                      `submitted`
  - `MonotonicResolution`    UNSAT — once terminal, status
                                      stays terminal
  - `EveryRequestResolves`   SAT   — sanity / non-vacuity

### Lessons / gotchas

1. **`always (some action)` deadlocks at terminal states.** The
   first version of this probe had `EveryRequestResolves`
   coming back UNSAT because the behavior fact required
   *some* action to fire every step. Once all requests are
   approved / rejected, no progress action is enabled and the
   trace cannot extend. Fix: add an explicit `pred Stutter
   { all r: Request | r.status' = r.status }` and disjoin it
   into the behavior fact. Without this, the sanity run
   silently fails for the wrong reason.
2. **State-transition assertions need a "BECOMES" guard.** The
   first version of `ApprovalRequiresReview` was

   ```
   r.status' = approved implies r.status = underReview
   ```

   which incorrectly fired on the Stutter case (`approved →
   approved`, where `r.status' = approved` is trivially true
   but `r.status = underReview` is false). Correct form:

   ```
   (r.status' = approved and r.status != approved)
     implies r.status = underReview
   ```

   This isolates the *transition* to approved. Pattern worth
   internalising for any "X is only reached via Y"
   state-machine claim in Alloy 6 temporal.

### Why this earned its slot

Workflow approval is the canonical "design doc that's
slightly more than English" — one diagram with arrows, a few
guard conditions in prose, the assumption that the team
will implement it faithfully. Alloy lets you write the
diagram + guards down once, in a form that catches both
classes of failure: implementation drift (the SQL doesn't
respect the guard) AND spec ambiguity (the prose under-
specifies a corner). The two probes added here cover the
two flavour-axes of app-level spec: *structural* (multi-
tenant) and *behavioural* (workflow). Together with the
existing `app-rbac.als`, Alloy now has three different
shapes of probe in the repo.

---

## P — sister probe of TLA+'s ActorMailbox

`languages/p/PingPong/` re-expresses the actor-model problem in
Microsoft's P language. Same domain (Sender + Receiver
exchanging messages), but where the TLA+ version had to
hand-model a mailbox as `Seq` and check FIFO via a prefix
invariant, P has actors + typed events as built-in primitives
and the checker's scheduler handles the interleaving.

### What I tripped on

1. **Setup cost.** P is a .NET tool, not packaged in nixpkgs.
   Required `dotnet-sdk_8` in flake.nix + `dotnet tool install
   --global P` + a `DOTNET_ROOT` export pointing at
   `${pkgs.dotnet-sdk_8}/share/dotnet` because otherwise the
   `p` binary aborts with "App host version: 8.0.26" —
   the wrapper script can't find the runtime nix ships
   alongside the SDK.
2. **Reserved keyword `sent`.** Compile errored with
   "`sent` keyword is only supported by PVerifier backend"
   when used as a normal variable name. Renamed to
   `roundTrips`. Not in the P language reference's reserved
   list as prominently as one would hope.
3. **Modules are needed for the `test` clause.** `assert Spec
   in (union Sender, Receiver, { Test })` doesn't parse. The
   bare machine name needs a wrapping `module = { ... };`
   declaration; then `union <Module>, ...` works.

### Empirical run

```
p check --schedules 1000
... Found 0 bugs.
... Explored 1000 schedules
... Number of scheduling points in terminating schedules: 18
```

Default strategy is `random`. PCT, probabilistic, and POS
schedulers are alternatives (`--sch-pct`, `--sch-probabilistic`,
`--sch-pos`). The 18 scheduling points per schedule means each
trial walks 18 message-delivery decisions; with 1,000 trials
the cumulative interleaving coverage is significant for a
two-actor model.

### What P offers that TLA+ doesn't

The killer feature is **code generation**. The same .p file
that the checker analyses can compile to executable C# or Java
(`--mode=codegen` flag). Spec ↔ implementation correspondence
is structural, not maintained by hand. This is the structural
guarantee TLA+ cannot deliver — the spec and impl have to be
re-aligned manually whenever either changes.

For systems where the actor model is the production
architecture (Akka / Orleans / Erlang-shaped), this is real
ROI. For systems where the spec is auxiliary to a Go / Rust
impl, TLA+ is more appropriate because the code generation
target wouldn't be used anyway.

### What TLA+ offers that P doesn't

Universal range — TLA+ models arbitrary state machines with
arbitrary mathematical state, not just actor-shaped systems.
For the EventSourcing probe in this same repo, TLA+'s
`RECURSIVE Replay` + state-as-fold-of-log shape is
straightforward; doing the same in P would require
reformulating the log as a queue and the reducer as a
message handler, which warps the model.

### Picking between them

- Actor-shaped impl + want exec code → **P**
- Actor-shaped spec only + non-actor impl → **TLA+**
- Non-actor systems (consensus, EventSourcing, distributed
  protocol where state is the focus, not messages) → **TLA+**

---

## TLA+ — Actor Model mailbox: bounded + FIFO + eventual delivery

`languages/tla/ActorMailbox.tla` — two actors send each other typed
messages through per-actor mailboxes. The probe verifies:

  - `BoundedMailbox` (safety) — no mailbox exceeds
    `MaxMailbox`; Send guards against overflow.
  - `PerPairFIFO` (safety) — for any `(from, to)` pair, the
    `recv_log` is a prefix of the `sent_log`. No reorder, no
    drop.
  - `EventualDelivery` (liveness) — any non-empty mailbox
    eventually drains, under weak-fairness on `Receive`.

TLC explores 1,681 distinct states at depth 13 (Actors = {a1,
a2}, Messages = {m1, m2}, MaxMailbox = 2). All three
properties hold; the liveness check completes in well under a
second with the `TotalSentBound` CONSTRAINT capping Send
activity.

### Why TLA+ specifically (and not P)

P would be the canonical tool here — actors are language
primitives, the checker is purpose-built for message-passing
state machines, and successful proofs come with generated
executable code. TLA+ is "fine," not best. The reason this
probe is in TLA+ rather than P is purely operational: P is
not in nixpkgs, requires .NET, and would add ~20 minutes of
toolchain plumbing for a single probe. The TLA+ version is
honest (uses fairness annotations, models the mailbox as Seq
explicitly, verifies the FIFO via prefix invariant) and
generalises to more actors / more message types by changing
the CONSTANT values.

For an actual production system: if the impl is C# / Java,
adopt P. If the impl is Rust, adopt Stateright. If the impl
is something else, keep the spec in TLA+ and accept the
spec/impl two-side maintenance.

### Lesson from the TLC warning

TLC warned: *"Declaring state or action constraints during
liveness checking is dangerous"*. The `TotalSentBound`
CONSTRAINT bounds exploration but can mask liveness violations
(the constraint may prevent the system from reaching the
violating state). The warning is a real caveat — in this
probe the constraint is benign because Send isn't part of any
liveness claim, but in larger models the right move is
usually to use `MAXLEN` on sent_log via fairness annotations
rather than via state-constraint trimming.

---

## Dafny — same RBAC + screen-nav domain as the Alloy probe

A second Dafny probe in `languages/dafny/rbac_screens.dfy` re-expresses the
Alloy probe's domain (Role × Screen × authorisation table ×
adjacency graph) using Dafny's class-based state-machine
encoding. Direct side-by-side comparison with `languages/alloy/app-rbac.als`.

### What Dafny adds over Alloy here

| Concern | Alloy 6 | Dafny |
| --- | --- | --- |
| Property scope | `for 4 but 6 steps` (bounded) | universally quantified over `i` in history |
| State carrier | `var sig LoggedIn { var at: Screen }` | `class Session { var screen; ghost var history }` |
| "Never reaches Settings" check | scope-bounded counterexample search | one-line lemma discharged by SMT |
| Cross-step invariant | `fact behavior { always Next }` | `ghost predicate Valid() reads this` |
| Trace artefact | implicit (Alloy's temporal extension) | explicit `ghost var history: seq<Screen>` |
| Counter-example | concrete instance graph | "could not be proved" + line number |

The probe verifies *three* monotonic safety properties
(`ViewerNeverAtSettings`, `EditorNeverAtSettings`,
`NonAdminNeverAtSettings`) as lemmas. Each is one line of
`ensures` plus an empty proof body — the SMT discharges them
from the invariant chain inside `Valid()`. Alloy's
counter-example-search story can't deliver universal guarantees
of this kind; Dafny can.

### What Dafny doesn't add

The model still doesn't represent multiple concurrent sessions.
Each `Session` instance is a single thread of navigation; a
`Set<Session>` reasoning step would be additional work and the
SMT would start needing manual help (fan-out frame conditions,
modifies clauses across the set). Alloy 6 with `var sig LoggedIn
in User` handles multi-user via the relation, almost for free.
So even here the picking matrix holds: Alloy for "structural
question over a population," Dafny for "guarantee for any single
instance through any trace length."

### What I tripped on

`AdminCanReachSettings` initially failed with "precondition
`Allowed(role, to)` could not be proved" — because the
`Navigate` method's frame condition did not promise
`role == old(role)`. Dafny conservatively assumed `role` might
change across the call, losing the `role == Admin` fact mid-trace.

Fix: add `ensures role == old(role)` to `Navigate`. This is the
canonical "Dafny needs you to spell out what stays the same"
gotcha. With it, all 12 verification conditions discharge.

### Lemma effort cost

Three of the four lemmas have *empty* proof bodies — SMT
discharges them once `Valid()` is set up correctly. The lemma
overhead is exactly:

```dafny
lemma NonAdminNeverAtSettings(s: Session)
  requires s.Valid()
  requires s.role != Admin
  ensures forall i :: 0 <= i < |s.history| ==> s.history[i] != Settings
{
}
```

5 lines. That's the "what does adding a theorem cost in Dafny"
data point: 5 lines per safety property, assuming the invariant
already exists.

---

## MoonBit `moon prove` — checkout-form-shape probe

### What it expresses well

The annotation surface is Dafny-shaped — `where { proof_require:
..., proof_ensure: result => ... }` on the function signature.
For our two-function probe the MoonBit source is short and
reads cleanly. Translation to Why3 (`.mlw`) produces faithful
output: `requires { ... }` / `ensures { ... }` clauses + an
imperative `let ... = if ... then ... else ...` body.

With the repository-local opam switch, `moon prove` now discharges
the checkout package:

```text
Succeeded: 5 goals proved
```

### What I tripped on

1. **Per-package activation gate.** Without `options(
   "proof-enabled": true )` in `moon.pkg`, `moon prove` silently
   exits 0 without doing anything. No diagnostic. This swallowed
   30 minutes of "is it actually checking" debugging — addressed
   in languages/moonbit/README.md as the lead caveat.
2. **`@int.MIN_VALUE` not expressible in proof annotations.** The
   logic-side language is a subset of MoonBit; standard-library
   constants are not all reachable. Worked around with a literal
   `-2147483648`. Documented in the probe's `safe_abs` comment.
3. **Toolchain version mismatch.** Why3 1.8.2 (nixpkgs latest)
   does not recognise Z3 4.16.0, CVC5 1.3.3, or Alt-Ergo 2.6.3
   (also nixpkgs latest). All three are dropped from moon's
   prover-harness pool with "no configured provers are
   available." The adopted fix is to use Nix for `opam`, then
   pin Why3 1.7.2 + Alt-Ergo 2.5.4 in `.opam-root/`.
4. **Boolean equivalence shape matters.** The original checkout
   contract used an inline `&&` / `||` formula while the MoonBit
   body lowered to nested `if`s. That produced 4 proved goals and
   1 timeout. Moving the decision into a `#proof_pure` helper and
   specifying `result == checkout_spec(...)` made the proof
   straightforward.

### Surface readability score

**8 / 10** — the annotation surface is as compact as Dafny's
and the `where { }` placement reads naturally. The proof
language being a *subset* of MoonBit (not a separate proof
script DSL) is a real win for review.

### Counter-example quality

Now exercised. Successful proofs report package-level goal counts;
failed proofs produce `_build/verif/checkout_form.proof.json` with
the Why3 goal, local context, and per-prover result. The useful
debug path is:

1. inspect `_build/verif/<pkg>.mlw`
2. inspect `_build/verif/*.proof.json`
3. simplify the contract shape before adding more proof hints

### When to reach for it again

When you can pay the one-time setup cost:

```sh
nix develop -c just setup-moonbit-prove-opam
nix develop -c just prove-moonbit
```

After that, MoonBit's compelling pitch is operational: proof
annotations directly on the production language, no separate
proof script, full Why3 IR visibility.

### Architectural note

MoonBit + Why3 is a different style from Dafny's monolith.
Dafny owns the entire pipeline including the SMT call;
MoonBit emits Why3 ML, then defers to whatever proves the user
has wired up. This is *cleaner* in the sense that Why3 is the
broader-standard IR (used by Frama-C, Krakatoa, EasyCrypt) —
but it shifts the version-compat surface onto the user, which is
the exact thing Dafny's bundled-everything approach hides.

---

## Pickings — per use case

The mapping that came out of writing the probes:

| Use case shape | Pick |
| --- | --- |
| RBAC tables, scope-permissions, "who can do what" | **Alloy** (bounded check is plenty; instances are reviewable) |
| Universal RBAC monotonicity ("editor strictly extends viewer") | **Lean** (Alloy can't quantify over arbitrary Permission types) |
| Screen-navigation graphs, workflow safety in finite scope | **Alloy 6** (temporal extension; no need to lift to TLA+) |
| Async state machine, payment / retry / timeout | **TLA+** (fairness + liveness are first-class) |
| Distributed protocol, eventual consistency | **TLA+** |
| Conditional invariants on records, validation predicates | **Dafny** (SMT discharges case-splits trivially) |
| Sequential algorithm with non-trivial loop invariants | **Dafny** |
| Refinement: "this implementation implements this spec" | **Dafny** or **Lean** depending on automation budget |
| Property that needs to hold for ALL elements of a recursive type | **Lean** (Alloy cannot; Dafny can with quantifiers but slowly) |

### Lessons that didn't fit a row

- **Alloy + Lean is the natural pairing for RBAC**: Alloy
  catches scope-5 surprise interactions ("the org has 3 admins,
  one impersonates another"), Lean proves the table itself is
  monotonic ("editor ≥ viewer for any permission you might add
  in the future"). Both are RBAC, but different questions.
- **TLA+ replaces Alloy 6's temporal only when fairness is in
  play.** If the question is "in any 6-step trace, does X
  hold," Alloy 6 is faster to write and more visual. The
  moment "X eventually happens under fairness" enters the
  vocabulary, TLA+ takes over.
- **Dafny will not replace a runtime test.** Verifying that
  `SumPrices` returns `total > 0` does NOT tell you the
  function is actually called with `prices != []` in
  production. Static verification + runtime tests are
  complementary, not substitutes.
- **Lean's bootstrap is the most expensive of the four.** The
  toolchain (elan + lake) and mathlib4 download are
  multi-minute on first run. Worth it for theorems; overkill
  for one-off "does this hold" questions.

---

## Next probes (open invitation)

- TLA+ retry-with-exponential-backoff probe (matches pkspec's
  `parallel.background` / readyProbe semantics).
- Dafny refinement: a more complex algorithm where the SMT
  starts to struggle and the user has to add `assert` waypoints.
- Lean: prove `pkspec.internal/executor.Tally.IsGreen` is the
  characteristic function of `Failed = 0 ∧ Errored = 0 ∧
  Skipped = 0` — using a Lean datatype that mirrors the Go one.
- Z3 / cvc5 raw: write a small SMT-LIB file that solves the
  same RBAC question in 30 lines, as the "tool you reach for
  when even Dafny is overkill" baseline.
- Iris-on-Rocq: only if a concurrent data-structure question
  shows up that none of the above four can handle.
