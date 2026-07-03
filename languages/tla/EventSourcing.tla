----------------------------- MODULE EventSourcing -----------------------------
(*
 * Probe: event-sourced payment ledger.
 *
 * State is a single integer balance derived from an append-only
 * log of Deposit / Withdraw events. The probe verifies four
 * properties that any event-sourcing implementation should
 * satisfy:
 *
 *   TypeOK                — types stay sane
 *   NonNegativeBalance    — withdraws cannot overdraft (safety)
 *   ReplayDeterminism     — balance == fold(Apply, 0, log)
 *                            i.e. the live state is the same as
 *                            replaying the log from scratch
 *   SnapshotIsPrefix      — snapshot.seq is always a prefix of log
 *   SnapshotConsistency   — replaying tail events from the
 *                            snapshot lands on the live balance
 *
 * Run:
 *   tlc -config EventSourcing.cfg EventSourcing.tla
 *
 * Expect: model checking completed, no errors. With MaxLogLen=3
 * and Amounts={1,2}, the state space is bounded.
 *
 * To watch the verifier catch a bug, drop the `balance >= a`
 * guard from AppendWithdraw — NonNegativeBalance then fails with
 * a 1-step counter-example.
 *)
EXTENDS Naturals, Sequences

CONSTANTS Amounts, MaxLogLen

VARIABLES log, balance, snapshot

vars == <<log, balance, snapshot>>

EventKinds == {"deposit", "withdraw"}
Event == [kind : EventKinds, amount : Amounts]

\* Pure reducer: applies one event to a balance.
Apply(b, e) ==
    IF e.kind = "deposit"
    THEN b + e.amount
    ELSE b - e.amount

\* Fold the reducer over a sequence of events. This is the
\* "replay" operation an event-sourced system performs on
\* startup or to reconstruct historical state.
RECURSIVE Replay(_, _)
Replay(b, evts) ==
    IF evts = <<>>
    THEN b
    ELSE Replay(Apply(b, Head(evts)), Tail(evts))

Init ==
    /\ log = <<>>
    /\ balance = 0
    /\ snapshot = [seq |-> <<>>, balance |-> 0]

AppendDeposit(a) ==
    /\ a \in Amounts
    /\ Len(log) < MaxLogLen
    /\ log' = Append(log, [kind |-> "deposit", amount |-> a])
    /\ balance' = balance + a
    /\ UNCHANGED snapshot

AppendWithdraw(a) ==
    /\ a \in Amounts
    /\ Len(log) < MaxLogLen
    /\ balance >= a              \* guard: no overdraft
    /\ log' = Append(log, [kind |-> "withdraw", amount |-> a])
    /\ balance' = balance - a
    /\ UNCHANGED snapshot

\* Capture a snapshot at the current log position. In a real
\* system this would be persisted to durable storage; here we
\* just freeze the current pair (log, balance) into the
\* snapshot variable.
CaptureSnapshot ==
    /\ snapshot' = [seq |-> log, balance |-> balance]
    /\ UNCHANGED <<log, balance>>

Next ==
    \/ \E a \in Amounts : AppendDeposit(a)
    \/ \E a \in Amounts : AppendWithdraw(a)
    \/ CaptureSnapshot

Spec == Init /\ [][Next]_vars

\* ── Invariants ─────────────────────────────────────────────────

TypeOK ==
    /\ log \in Seq(Event)
    /\ balance \in Nat
    /\ snapshot.seq \in Seq(Event)
    /\ snapshot.balance \in Nat

NonNegativeBalance == balance >= 0

ReplayDeterminism == balance = Replay(0, log)

SnapshotIsPrefix ==
    /\ Len(snapshot.seq) <= Len(log)
    /\ \A i \in 1..Len(snapshot.seq) : snapshot.seq[i] = log[i]

SnapshotConsistency ==
    Replay(snapshot.balance,
           SubSeq(log, Len(snapshot.seq) + 1, Len(log))) = balance

================================================================================
