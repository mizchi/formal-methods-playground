--------------------------- MODULE SeatLimitTrace ---------------------------
(*
 * Probe (T5, runtime): replay a *production log* against the design-time model
 * in SeatLimitWriteSkew.tla.
 *
 * SeatLimitWriteSkew answers a T0 question -- "which isolation level makes the
 * seat limit safe?" -- and its own README admits what it cannot answer:
 * whether production actually runs at the level you modelled. That question
 * has no design-time answer. It is settled by what the database did, which is
 * in the log.
 *
 * So: no search here. The log fully determines the step, and this module
 * replays it one line at a time, demanding at every line that the step the log
 * records is one the model ADMITS under the configured Isolation. Two
 * different failures fall out, and they mean opposite things:
 *
 *   TraceAccepted violated    the store did something the model forbids at
 *                             this Isolation -> either the model is wrong, or
 *                             you are not running at the level you think.
 *                             The final state's `i` is the 1-based index of
 *                             the log line that was refused.
 *
 *   SeatsWithinLimit violated the log conforms, and the business rule broke
 *                             anyway -> the bug is real and this is its
 *                             witness, taken from production rather than
 *                             from a model checker's imagination.
 *
 * The distinction between COMMIT and ROLLBACK is what makes this discriminate.
 * The model's Commit action covers both outcomes -- SSI aborts, SI does not --
 * so a log line has to say which one happened, and only one Isolation admits
 * it. That is how a log tells you the isolation level you are really on.
 *
 * Log alphabet (scripts/trace-to-tla.sh projects the JSON onto it):
 *
 *   "select"  BEGIN + the counting SELECT      -> Read
 *   "insert"  the INSERT was issued            -> Insert
 *   "deny"    handler refused, 409, no insert  -> Reject
 *   "commit"  COMMIT returned success          -> Commit, landing on committed
 *   "abort"   ROLLBACK / 40001                 -> Commit, landing on aborted
 *
 * Run (from this directory, inside the nix devShell):
 *
 *   tlc -config SeatLimitTrace.cfg         SeatLimitTrace.tla  # no error
 *   tlc -config SeatLimitTrace_retry.cfg   SeatLimitTrace.tla  # no error
 *   tlc -config SeatLimitTrace_claimed.cfg SeatLimitTrace.tla  # TraceAccepted violated
 *   tlc -config SeatLimitTrace_actual.cfg  SeatLimitTrace.tla  # SeatsWithinLimit violated
 *
 * The last two replay the SAME incident log at two isolation levels, and that
 * pair is the whole point: at the level ops claim, the log is impossible; at
 * the level that admits it, the seat limit is broken.
 *)
EXTENDS Naturals, Sequences, FiniteSets, SeatLimitTraceLog

CONSTANTS Txns,      \* transactions appearing in the log, e.g. {"t1", "t2"}
          SeatLimit, \* seats the org's plan allowed during the window
          Isolation, \* the level whose commit rule we are testing the log against
          Trace      \* the log, as a sequence of [op |-> ..., txn |-> ...]

VARIABLES members, snap, pc, lock,
          i          \* 1-based cursor into Trace

\* The model under test, unchanged. Everything below reuses its actions rather
\* than restating them -- a conformance check that re-derives the rules is only
\* checking itself.
M == INSTANCE SeatLimitWriteSkew

tvars == <<members, snap, pc, lock, i>>

\* Commit covers both outcomes; the log says which one the database reported.
CommitOK(t)    == M!Commit(t) /\ pc'[t] = "committed"
CommitAbort(t) == M!Commit(t) /\ pc'[t] = "aborted"

\* Does the model admit this log line as the next step? An op the model has no
\* action for is refused rather than ignored: a log that grew a new operation
\* is exactly the drift this check exists to notice.
Admits(e) ==
    CASE e.op = "select" -> M!Read(e.txn)
      [] e.op = "insert" -> M!Insert(e.txn)
      [] e.op = "deny"   -> M!Reject(e.txn)
      [] e.op = "commit" -> CommitOK(e.txn)
      [] e.op = "abort"  -> CommitAbort(e.txn)
      [] OTHER           -> FALSE

Init ==
    /\ M!Init
    /\ i = 1

Replay ==
    /\ i <= Len(Trace)
    /\ Admits(Trace[i])
    /\ i' = i + 1

Next == Replay

\* No fairness needed beyond WF: the replay is deterministic, so the state
\* space is one behaviour of Len(Trace)+1 states. If a line is refused there is
\* no successor and the behaviour stutters short of the end.
Spec == Init /\ [][Next]_tvars /\ WF_tvars(Next)

TypeOK ==
    /\ M!TypeOK
    /\ i \in 1..(Len(Trace) + 1)

\* Every line of the log was admitted by the model at this Isolation.
TraceAccepted == <>(i > Len(Trace))

\* The business rule, re-asked against what actually happened.
SeatsWithinLimit == M!SeatsWithinLimit

=============================================================================
