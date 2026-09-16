/*
 * Probe: does an offline-first sync converge?
 *
 * Domain: a local-first / offline-capable app -- a notes app, a mobile CRM,
 * a kanban board -- where every device edits its own replica while offline
 * and later gossips updates to the others. The usual homegrown merge is
 * last-writer-wins on a per-field timestamp:
 *
 *   if (incoming.updatedAt > local.updatedAt) local = incoming
 *
 * Strong eventual consistency says: two devices that have received the same
 * SET of updates must show the same thing, regardless of the order they
 * arrived in. That holds iff the "who wins" relation is a strict total order
 * on updates -- so a unique maximum always exists. This model checks exactly
 * that, and shows the two ways the homegrown version loses it.
 *
 *   winner    -- LWW with a replica-id tiebreak  (the correct merge)
 *   winnerNaive -- LWW with `>=`, i.e. "on a tie, keep whatever I applied
 *                  first". Order-dependent, so it is not a function of the
 *                  delivered set at all.
 *
 * Run (inside the nix devShell):
 *
 *   alloy6 exec -f --command TiebreakIsCommutative      usecases/offline-sync-convergence/lww-merge.als
 *   alloy6 exec -f --command TiebreakIsAssociative      usecases/offline-sync-convergence/lww-merge.als
 *   alloy6 exec -f --command EveryReplicaConverges      usecases/offline-sync-convergence/lww-merge.als
 *   alloy6 exec -f --command SameUpdatesSameState       usecases/offline-sync-convergence/lww-merge.als
 *   alloy6 exec -f --command NaiveTieDiverges           usecases/offline-sync-convergence/lww-merge.als
 *   alloy6 exec -f --command NaiveReplicaHasNoUniqueWinner    usecases/offline-sync-convergence/lww-merge.als
 *   alloy6 exec -f --command RepeatedStampBreaksTiebreak usecases/offline-sync-convergence/lww-merge.als
 *   alloy6 exec -f --command ConcurrentEditsExist       usecases/offline-sync-convergence/lww-merge.als
 *
 * Expected: the four checks UNSAT (no counterexample), the four runs SAT
 * (the witnesses). The runs are the load-bearing half -- they are what proves
 * the checks are discriminating and not vacuous.
 */
module lww_merge

open util/ordering[Replica] as RO

// Devices. util/ordering gives them the stable total order that a real
// implementation gets from a UUID / site id comparison.
sig Replica {}

sig Value {}

// One field-level edit: "replica R set the field to V at local time T".
sig Update {
  time:   one Int,
  origin: one Replica,
  value:  one Value
}

// A device's inbox: the set of updates it has received so far.
sig Site {
  delivered: set Update
}

fact SaneTimes { all u: Update | u.time >= 0 }

// The assumption the tiebreak depends on: a replica never issues two updates
// with the same timestamp. Real systems get this from a monotonic counter or
// a Lamport/hybrid clock -- and lose it with a coarse wall clock.
pred UniqueStamps {
  all disj u1, u2: Update | u1.origin = u2.origin implies u1.time != u2.time
}

// The correct merge: newest wins, replica id breaks ties.
fun winner[a, b: Update]: Update {
  a.time > b.time implies a
  else b.time > a.time implies b
  else (a.origin in b.origin.^(RO/next) implies a else b)
}

// The homegrown merge: `>=` means "the one I am holding when the tie happens".
fun winnerNaive[a, b: Update]: Update {
  a.time >= b.time implies a else b
}

// A site's visible state is the maximum of its inbox under the merge order.
fun stateOf[s: Site]: set Update {
  { u: s.delivered | all v: s.delivered | winner[u, v] = u }
}

fun naiveStateOf[s: Site]: set Update {
  { u: s.delivered | all v: s.delivered | winnerNaive[u, v] = u }
}

// ---------------------------------------------------------------- checks

// Merge order does not depend on which side the update arrived on.
check TiebreakIsCommutative {
  UniqueStamps implies all a, b: Update | winner[a, b] = winner[b, a]
} for 6 but 4 Int

// Merge order does not depend on how the batch was grouped.
check TiebreakIsAssociative {
  UniqueStamps implies
    all a, b, c: Update | winner[winner[a, b], c] = winner[a, winner[b, c]]
} for 6 but 4 Int

// Strong eventual consistency: a non-empty inbox always resolves to exactly
// one visible value.
check EveryReplicaConverges {
  UniqueStamps implies all s: Site | some s.delivered implies one stateOf[s]
} for 6 but 4 Int

// ...and two devices holding the same inbox show the same thing.
check SameUpdatesSameState {
  UniqueStamps implies
    all disj p, q: Site | p.delivered = q.delivered implies stateOf[p] = stateOf[q]
} for 6 but 4 Int

// ---------------------------------------------------------------- witnesses

// The homegrown `>=` merge is not commutative: two devices that saw the same
// pair of concurrent edits in different orders keep different values.
run NaiveTieDiverges {
  some a, b: Update | winnerNaive[a, b] != winnerNaive[b, a]
} for 6 but 4 Int

// The same defect seen at the replica level, phrased as the exact negation of
// EveryReplicaConverges: an inbox where two updates each "beat everything", so
// what the device shows depends on which one it applied last.
run NaiveReplicaHasNoUniqueWinner {
  UniqueStamps
  some s: Site | some s.delivered and not one naiveStateOf[s]
} for 6 but 4 Int

// Even the correct tiebreak needs the clock assumption. Drop UniqueStamps --
// a coarse wall clock that repeats within one tick -- and it fails too.
run RepeatedStampBreaksTiebreak {
  not UniqueStamps
  some a, b: Update | winner[a, b] != winner[b, a]
} for 6 but 4 Int

// Non-vacuity: the scope really does admit two devices editing concurrently
// (same timestamp, different replicas, different values) and still converging.
run ConcurrentEditsExist {
  UniqueStamps
  some disj a, b: Update |
    a.time = b.time and a.origin != b.origin and a.value != b.value
  all s: Site | some s.delivered implies one stateOf[s]
  some s: Site | #s.delivered > 1
} for 6 but 4 Int
