----------------------------- MODULE ActorMailbox -----------------------------
(*
 * Probe: minimal actor model with per-actor mailboxes,
 * bounded queues, and per-pair FIFO ordering.
 *
 * Two actors send arbitrary messages to each other. Each actor
 * has its own mailbox (a Seq); Send appends to the destination's
 * mailbox, Receive pops the head. The model tracks two
 * audit logs (sent_log / recv_log) per (from, to) pair so the
 * FIFO property can be expressed by comparing them.
 *
 * Properties:
 *   TypeOK            — types stay sane
 *   BoundedMailbox    — no mailbox exceeds MaxMailbox entries
 *                       (safety; the Send action enforces this)
 *   PerPairFIFO       — for any (from, to) pair, the sequence of
 *                       messages received is a prefix of the
 *                       sequence sent (no reordering, no drop)
 *   EventualDelivery  — non-empty mailbox eventually drains
 *                       (liveness, requires WF on Receive)
 *
 * Run:
 *   tlc -config ActorMailbox.cfg ActorMailbox.tla
 *
 * Expect: model checking completed, no errors.
 *
 * To watch the verifier catch a bug, drop the WF on Receive in
 * Spec; EventualDelivery then fails with a stuttering counter-
 * example trace where Send keeps firing but Receive never does.
 *)
EXTENDS Naturals, Sequences

CONSTANTS Actors, Messages, MaxMailbox

VARIABLES inbox, sent_log, recv_log

vars == <<inbox, sent_log, recv_log>>

InboxItem == [from : Actors, msg : Messages]

Init ==
    /\ inbox = [a \in Actors |-> <<>>]
    /\ sent_log = [a \in Actors |-> [b \in Actors |-> <<>>]]
    /\ recv_log = [a \in Actors |-> [b \in Actors |-> <<>>]]

Send(from, to, msg) ==
    /\ from # to
    /\ Len(inbox[to]) < MaxMailbox
    /\ inbox' = [inbox EXCEPT
                   ![to] = Append(@, [from |-> from, msg |-> msg])]
    /\ sent_log' = [sent_log EXCEPT
                     ![from][to] = Append(@, msg)]
    /\ UNCHANGED recv_log

Receive(a) ==
    /\ inbox[a] # <<>>
    /\ LET item == Head(inbox[a]) IN
         /\ inbox' = [inbox EXCEPT ![a] = Tail(@)]
         /\ recv_log' = [recv_log EXCEPT
                          ![item.from][a] = Append(@, item.msg)]
    /\ UNCHANGED sent_log

Next ==
    \/ \E f, t \in Actors, m \in Messages : Send(f, t, m)
    \/ \E a \in Actors : Receive(a)

\* Weak fairness on each actor's Receive ensures that any
\* non-empty mailbox eventually drains. Without this, a trace
\* in which Send fires forever but Receive never does would
\* be admitted by [][Next]_vars and violate EventualDelivery.
Spec ==
    /\ Init
    /\ [][Next]_vars
    /\ \A a \in Actors : WF_vars(Receive(a))

\* State-space constraint: cap the total number of messages
\* sent across each pair to keep TLC bounded. Not part of the
\* spec semantics — only a CONSTRAINT in the .cfg.
TotalSentBound ==
    \A f, t \in Actors : Len(sent_log[f][t]) <= 3

\* ── Invariants ─────────────────────────────────────────────────

TypeOK ==
    /\ inbox \in [Actors -> Seq(InboxItem)]
    /\ sent_log \in [Actors -> [Actors -> Seq(Messages)]]
    /\ recv_log \in [Actors -> [Actors -> Seq(Messages)]]

BoundedMailbox ==
    \A a \in Actors : Len(inbox[a]) <= MaxMailbox

IsPrefix(s, t) ==
    /\ Len(s) <= Len(t)
    /\ \A i \in 1..Len(s) : s[i] = t[i]

PerPairFIFO ==
    \A a, b \in Actors :
        a # b => IsPrefix(recv_log[a][b], sent_log[a][b])

\* Liveness: any non-empty mailbox eventually becomes empty.
\* Holds under WF_vars(Receive(a)) provided Send isn't required
\* to fire forever — TotalSentBound caps Send activity.
EventualDelivery ==
    \A a \in Actors :
        (inbox[a] # <<>>) ~> (inbox[a] = <<>>)

================================================================================
