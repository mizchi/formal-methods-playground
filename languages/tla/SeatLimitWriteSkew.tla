------------------------- MODULE SeatLimitWriteSkew -------------------------
(*
 * Probe: write skew on a "count the rows, then insert one" invariant.
 *
 * Domain: a B2B SaaS org with a seat limit. Two admins click "invite" at the
 * same time. Each request runs the ORM's default transaction:
 *
 *   SELECT count(1) FROM members WHERE org_id = $1   -- read
 *   ...if count < seat_limit...
 *   INSERT INTO members (org_id, user_id) VALUES (...)  -- write
 *
 * This is NOT a lost update: the two transactions write *different rows*, so
 * there is no write-write conflict for the database to notice. Under Snapshot
 * Isolation (PostgreSQL REPEATABLE READ, MySQL default, most "just wrap it in
 * a transaction" advice) both commit and the org ends up over its limit.
 * The same shape covers: coupon redemption caps, inventory reservation,
 * "at least one admin must remain", and free-tier project quotas.
 *
 * Isolation selects which store we are modelling:
 *
 *   "SI"           snapshot read + first-committer-wins on the SAME row.
 *                  Different rows never conflict -> write skew is allowed.
 *   "SERIALIZABLE" PostgreSQL SERIALIZABLE / SSI: a transaction whose read
 *                  set changed underneath it aborts at commit.
 *   "SI_LOCK"      the request takes a row lock on the org first
 *                  (SELECT ... FOR UPDATE on organizations) and reads the
 *                  count AFTER the lock is granted, with a fresh snapshot.
 *                  In PostgreSQL this is READ COMMITTED + FOR UPDATE, where
 *                  every statement takes a new snapshot. The lock
 *                  materialises the missing conflict.
 *   "RR_LOCK"      PostgreSQL REPEATABLE READ + FOR UPDATE. The snapshot is
 *                  taken when the first statement starts -- before that
 *                  statement waits for the lock -- so the count read after
 *                  the lock is still the stale one. The lock does NOT help.
 *
 * Run (from this directory, inside the nix devShell):
 *
 *   tlc -config SeatLimitWriteSkew.cfg      SeatLimitWriteSkew.tla  # no error
 *   tlc -config SeatLimitWriteSkew_si.cfg   SeatLimitWriteSkew.tla  # SeatsWithinLimit violated
 *   tlc -config SeatLimitWriteSkew_lock.cfg SeatLimitWriteSkew.tla  # no error
 *   tlc -config SeatLimitWriteSkew_rrlock.cfg SeatLimitWriteSkew.tla # SeatsWithinLimit violated
 *
 * SeatLimitWriteSkew.cfg (SERIALIZABLE) is the CI-green check. The _si cfg is
 * the load-bearing breaking variant: it prints the two-admin trace that puts
 * the org one seat over. The _lock cfg shows the fix most teams actually ship,
 * and is green for a different reason -- worth keeping both so a future change
 * to the isolation level cannot silently pass. The _rrlock cfg is the second
 * breaking variant: the same lock under REPEATABLE READ still overbooks, which
 * usecases/write-skew-seat-limit/repro reproduces against PostgreSQL 17.
 *)
EXTENDS Naturals, FiniteSets

CONSTANTS Txns,      \* concurrent requests, e.g. {t1, t2}
          SeatLimit, \* seats the org's plan allows
          Isolation  \* "SI" | "SERIALIZABLE" | "SI_LOCK" | "RR_LOCK"

VARIABLES members,  \* committed member rows for this org
          snap,     \* per-txn snapshot of the count it read
          pc,       \* per-txn control state
          lock      \* holder of the org row lock, or "none"

vars == <<members, snap, pc, lock>>

PcStates == {"idle", "begun", "read", "inserted", "committed", "aborted"}

Init ==
    /\ members = 0
    /\ snap = [t \in Txns |-> 0]
    /\ pc = [t \in Txns |-> "idle"]
    /\ lock = "none"

\* BEGIN + the counting SELECT. Under SI_LOCK this is
\* `SELECT ... FOR UPDATE` on the org row, so it blocks while held.
\* RR_LOCK: PostgreSQL REPEATABLE READ + SELECT ... FOR UPDATE.
\* The snapshot is taken when the first statement starts -- before the
\* statement waits for the lock -- so the count it later reads is stale.
BeginRR(t) ==
    /\ Isolation = "RR_LOCK"
    /\ pc[t] = "idle"
    /\ snap' = [snap EXCEPT ![t] = members]
    /\ pc' = [pc EXCEPT ![t] = "begun"]
    /\ UNCHANGED <<members, lock>>

LockRR(t) ==
    /\ pc[t] = "begun"
    /\ lock = "none"
    /\ lock' = t
    /\ pc' = [pc EXCEPT ![t] = "read"]
    /\ UNCHANGED <<members, snap>>

Read(t) ==
    /\ Isolation # "RR_LOCK"
    /\ pc[t] = "idle"
    /\ Isolation = "SI_LOCK" => lock = "none"
    /\ lock' = IF Isolation = "SI_LOCK" THEN t ELSE lock
    /\ snap' = [snap EXCEPT ![t] = members]
    /\ pc' = [pc EXCEPT ![t] = "read"]
    /\ UNCHANGED members

\* The application's guard, evaluated against what this txn read.
Insert(t) ==
    /\ pc[t] = "read"
    /\ snap[t] < SeatLimit
    /\ pc' = [pc EXCEPT ![t] = "inserted"]
    /\ UNCHANGED <<members, snap, lock>>

\* The guard said no. Nothing was written; release any lock.
Reject(t) ==
    /\ pc[t] = "read"
    /\ snap[t] >= SeatLimit
    /\ pc' = [pc EXCEPT ![t] = "aborted"]
    /\ lock' = IF lock = t THEN "none" ELSE lock
    /\ UNCHANGED <<members, snap>>

\* COMMIT. Only SSI re-checks the read set; SI does not, because the two
\* transactions never touched the same row.
Commit(t) ==
    /\ pc[t] = "inserted"
    /\ IF Isolation = "SERIALIZABLE" /\ members # snap[t]
         THEN /\ pc' = [pc EXCEPT ![t] = "aborted"]
              /\ UNCHANGED members
         ELSE /\ pc' = [pc EXCEPT ![t] = "committed"]
              /\ members' = members + 1
    /\ lock' = IF lock = t THEN "none" ELSE lock
    /\ UNCHANGED snap

Next == \E t \in Txns : BeginRR(t) \/ LockRR(t) \/ Read(t) \/ Insert(t) \/ Reject(t) \/ Commit(t)

Spec == Init /\ [][Next]_vars

TypeOK ==
    /\ members \in 0..Cardinality(Txns)
    /\ lock \in Txns \cup {"none"}
    /\ \A t \in Txns : pc[t] \in PcStates
    /\ \A t \in Txns : snap[t] \in 0..Cardinality(Txns)

\* The business rule the code believes it enforces.
SeatsWithinLimit == members <= SeatLimit

=============================================================================
