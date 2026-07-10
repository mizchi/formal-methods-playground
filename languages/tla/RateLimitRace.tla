---------------------------- MODULE RateLimitRace ----------------------------
(*
 * Probe: concurrent rate-limit / quota enforcement.
 *
 * N workers share one counter guarded by a limit ("at most Cap grants").
 * Each worker reads the count, checks count < Cap, then grants and records.
 * Whether read-check-record is one atomic step decides correctness:
 *
 *   Atomic = TRUE   check-and-increment is a single step
 *                   (conditional write / atomic ADD-with-condition)
 *                   -> granted <= Cap holds under every interleaving
 *   Atomic = FALSE  read and record are separate steps
 *                   -> two workers read the same pre-grant count, both
 *                      pass the check, both grant -> granted = Cap+1
 *
 * The canonical read-modify-write race. TLC explores all interleavings.
 *
 * Run (from this directory, inside the nix devShell):
 *
 *   tlc -config RateLimitRace.cfg       RateLimitRace.tla   # atomic: no error
 *   tlc -config RateLimitRace_naive.cfg RateLimitRace.tla   # naive: NoOverGrant violated
 *
 * NoOverGrant passes for the atomic design and is the CI-green check.
 * The naive cfg is the breaking variant: run it to see TLC print the
 * over-grant counterexample (granted = Cap+1). This proves the invariant
 * is load-bearing, not vacuously true.
 *)
EXTENDS Naturals, FiniteSets

CONSTANTS Workers,  \* set of concurrent workers, e.g. {w1, w2}
          Cap,      \* grant limit
          Atomic    \* TRUE: atomic check-and-increment / FALSE: split read+record

VARIABLES count,    \* shared persisted counter
          pc,       \* per-worker control state
          seen,     \* value each worker read (naive path)
          granted   \* total grants made (must stay <= Cap)

vars == <<count, pc, seen, granted>>

Init ==
    /\ count = 0
    /\ pc = [w \in Workers |-> "start"]
    /\ seen = [w \in Workers |-> 0]
    /\ granted = 0

\* atomic: read + check + record in one indivisible step
AtomicStep(w) ==
    /\ Atomic
    /\ pc[w] = "start"
    /\ IF count < Cap
         THEN /\ count' = count + 1
              /\ granted' = granted + 1
         ELSE UNCHANGED <<count, granted>>
    /\ pc' = [pc EXCEPT ![w] = "done"]
    /\ UNCHANGED seen

\* naive: read now, decide-and-record later (the gap is the race)
Read(w) ==
    /\ ~Atomic
    /\ pc[w] = "start"
    /\ seen' = [seen EXCEPT ![w] = count]
    /\ pc' = [pc EXCEPT ![w] = "decide"]
    /\ UNCHANGED <<count, granted>>

Decide(w) ==
    /\ ~Atomic
    /\ pc[w] = "decide"
    /\ IF seen[w] < Cap
         THEN /\ count' = count + 1
              /\ granted' = granted + 1
         ELSE UNCHANGED <<count, granted>>
    /\ pc' = [pc EXCEPT ![w] = "done"]
    /\ UNCHANGED seen

Next == \E w \in Workers : AtomicStep(w) \/ Read(w) \/ Decide(w)

Spec == Init /\ [][Next]_vars

\* Safety: never grant more than the limit.
NoOverGrant == granted <= Cap

TypeOK ==
    /\ granted \in 0..Cardinality(Workers)
    /\ count \in 0..(Cap + Cardinality(Workers))

=============================================================================
