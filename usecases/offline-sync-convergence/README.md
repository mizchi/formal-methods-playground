# offline-sync-convergence/

Pattern: several replicas accept writes while disconnected and merge later.
The merge rule decides whether the devices end up showing the same thing. The
usual homegrown rule is last-writer-wins on a per-field timestamp:

```js
if (incoming.updatedAt > local.updatedAt) local = incoming
```

**Strong eventual consistency** is the claim that matters: two replicas that
have received the same *set* of updates show the same state, whatever order
those updates arrived in. That holds exactly when the "who wins" relation is a
strict total order on updates — so every non-empty inbox has a unique maximum.
Written that way, it is a small relational question, which is Alloy's shape.

Real instances: a local-first notes app, a mobile client with an offline queue,
a kanban board with optimistic updates, multi-region active-active writes,
a browser extension syncing settings across profiles.

The source of truth is the merge function and the clock that stamps updates.
Do not model the network; model the winner relation and what a replica's inbox
resolves to.

## Split the question

| Question | Shape | Tool | Example |
| --- | --- | --- | --- |
| Is the merge order-independent? | commutativity / associativity of a function | Alloy | `merge(a,b) = merge(b,a)` |
| Does a replica's inbox resolve to one value? | unique maximum of a relation | Alloy | two updates that each beat everything |
| Does the tiebreak survive a coarse clock? | the same check with the clock assumption dropped | Alloy | two stamps equal within one tick |
| Does a *specific* op-based CRDT converge for all sizes? | unbounded theorem | Lean / Rocq / Isabelle | out of scope here — Alloy is bounded |

## Probe: Alloy

[`lww-merge.als`](lww-merge.als)

Two merge functions sit side by side:

- `winner` — LWW with a replica-id tiebreak (the correct one)
- `winnerNaive` — LWW with `>=`, i.e. "on a tie, keep whichever I applied first"

and one assumption, stated explicitly rather than assumed:

- `UniqueStamps` — a replica never issues two updates with the same timestamp
  (what you get from a monotonic counter or a hybrid logical clock, and lose
  from a coarse wall clock)

| Command | Expected | Domain meaning |
| --- | --- | --- |
| `TiebreakIsCommutative` | UNSAT | the merge does not care which side an update arrived on |
| `TiebreakIsAssociative` | UNSAT | it does not care how the batch was grouped |
| `EveryReplicaConverges` | UNSAT | every non-empty inbox resolves to exactly one value |
| `SameUpdatesSameState` | UNSAT | two devices with the same inbox show the same thing |
| `NaiveTieDiverges` | SAT | witness: `>=` picks a different winner depending on argument order |
| `NaiveReplicaHasNoUniqueWinner` | SAT | witness: an inbox where two updates each beat everything — the device shows whichever it applied last |
| `RepeatedStampBreaksTiebreak` | SAT | witness: drop the clock assumption and even the correct tiebreak diverges |
| `ConcurrentEditsExist` | SAT | non-vacuity: the scope really does contain two devices editing at the same instant, and it still converges |

The four SAT runs are the load-bearing half. `EveryReplicaConverges` passing
means nothing if the scope cannot express a conflict at all — which is what
`ConcurrentEditsExist` rules out.

```sh
nix develop -c just check-alloy
nix develop -c alloy6 exec -f usecases/offline-sync-convergence/lww-merge.als
```

## What the counterexamples say in domain terms

- `NaiveTieDiverges`: *"two phones edit the same note in the same second; each
  keeps its own text, and neither will ever adopt the other's — the conflict is
  invisible because both sides think they are up to date."*
- `RepeatedStampBreaksTiebreak`: *"our tiebreak is correct only if one device
  never stamps two edits with the same millisecond. `Date.now()` does."*

The second is the useful one. The merge code was right; the *assumption under
it* was the bug, and stating `UniqueStamps` as a named predicate is what made
it checkable instead of implicit.

## Domain ledger

| field | value |
| --- | --- |
| source | the client's merge function and the clock that stamps updates |
| expected claim | replicas that received the same set of updates display the same value |
| implementation observation | `repro/lww.ts`: `mergeNaive` keeps the local value on a timestamp tie; `mergeWithTiebreak` breaks ties on replica id, which is only total if one replica never repeats a stamp |
| model question | does the winner relation have a unique maximum on every inbox? |
| tool | Alloy 6 (scope 6, 4 Int) |
| machine result | 4 checks UNSAT (`TiebreakIsCommutative`, `TiebreakIsAssociative`, `EveryReplicaConverges`, `SameUpdatesSameState`), 4 runs SAT (`NaiveTieDiverges`, `NaiveReplicaHasNoUniqueWinner`, `RepeatedStampBreaksTiebreak`, `ConcurrentEditsExist`) |
| witness | `NaiveTieDiverges`: two replicas stamp the same time; `RepeatedStampBreaksTiebreak`: one replica stamps two updates with the same time |
| reproduction | reproduced: `repro/lww.test.ts` shows the naive merge diverging for A and B at `time = 1000`, the tiebreak converging, a repeated stamp from A at `time = 2000` diverging again, and `monotonicClock` restoring convergence |
| domain wording | "last-writer-wins converges only with a total tiebreak *and* per-replica-unique stamps; with `>=` and a wall clock, two devices can disagree forever" |
| domain question | Does every client stamp edits from a clock that never repeats per device (monotonic counter / hybrid logical clock), or from `Date.now()`? |
| decision | bug (demo); `winner` under `UniqueStamps` is the checked design: it needs both the replica-id tiebreak and unique per-replica stamps |
| lock | `just check-alloy`; `cd usecases/offline-sync-convergence/repro && node --test lww.test.ts` |

## What this does NOT catch

- **Bounded scope.** Alloy checked up to 6 atoms and 4-bit integers. That is
  enough to find order-dependence, which shows up in pairs — but it is not a
  proof for all replica counts. For that, the tradition is a proof assistant:
  Gomes et al. verified strong eventual consistency for op-based CRDTs in
  Isabelle/HOL with an explicit network model
  ([arXiv:1707.01747](https://arxiv.org/abs/1707.01747)).
- **Per-field vs. per-document LWW.** This models one field. Whole-document LWW
  converges too and still loses concurrent edits to *different* fields — a
  correctness question the SEC property does not ask.
- **Causality.** There is no happens-before here. An update that logically
  depends on one a replica has not received yet is a delivery-order problem
  (causal broadcast), not a merge problem.
- **Sequence/text editing.** Interleaving anomalies in list CRDTs are about
  where an element lands, not which value wins; a different model entirely.
- **Tombstones and GC.** Deleting, then merging with a replica that never saw
  the delete, needs a tombstone in the model.
