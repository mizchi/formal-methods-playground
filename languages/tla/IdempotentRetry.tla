--------------------------- MODULE IdempotentRetry ---------------------------
(*
 * Probe: idempotency keys under at-least-once retry.
 *
 * Domain: a payment / webhook endpoint that the caller retries on timeout
 * (Stripe `Idempotency-Key`, PSP callbacks, queue consumers with at-least-once
 * delivery). The handler does two things that are NOT one transaction:
 *
 *   1. an external side effect  (charge the card / call the provider)
 *   2. a local durable record   (remember "this key is handled")
 *
 * The order of those two, and what a retry does when it finds a half-written
 * record, is the whole design. Three knobs make the three real designs:
 *
 *   ReserveFirst       TRUE  = write the key row BEFORE calling the provider
 *                      FALSE = write it AFTER (the "store the result" bug)
 *   ProviderIdempotent TRUE  = the provider dedupes on the same key too
 *                      FALSE = every call to the provider creates a charge
 *   TakeoverReserved   TRUE  = a retry that finds "reserved" resumes it
 *                      FALSE = a retry that finds "reserved" returns 409
 *
 * Crash is bounded by MaxCrashes so the state space stays finite; retries
 * themselves are unbounded, which is what makes the liveness check meaningful.
 *
 * Run (from this directory, inside the nix devShell):
 *
 *   tlc -config IdempotentRetry.cfg          IdempotentRetry.tla  # no error
 *   tlc -config IdempotentRetry_late.cfg     IdempotentRetry.tla  # NoDoubleCharge violated
 *   tlc -config IdempotentRetry_blocking.cfg IdempotentRetry.tla  # EventuallySettled violated
 *
 * IdempotentRetry.cfg is the CI-green check. The other two are the
 * load-bearing breaking variants, and they break *different* properties:
 * one is a safety bug (charged twice), one is a liveness bug (a key wedged
 * in "reserved" forever). A design that only ever shows green on safety has
 * not been asked the second question.
 *)
EXTENDS Naturals

CONSTANTS MaxCrashes,        \* how many times the handler may die mid-flight
          ReserveFirst,      \* write the idempotency row before the side effect?
          ProviderIdempotent,\* does the provider dedupe on the same key?
          TakeoverReserved   \* may a retry resume a "reserved" row?

VARIABLES rec,      \* our durable idempotency record: "none" | "reserved" | "done"
          charges,  \* side effects the provider actually recorded
          pc,       \* handler control state for the current attempt
          crashes   \* crashes used so far

vars == <<rec, charges, pc, crashes>>

RecStates == {"none", "reserved", "done"}
PcStates  == {"idle", "charging", "storing", "settled"}

Init ==
    /\ rec = "none"
    /\ charges = 0
    /\ pc = "idle"
    /\ crashes = 0

\* A (re)try arrives and looks up the key.
Begin ==
    /\ pc = "idle"
    /\ \/ \* already handled: replay the stored result, no side effect
          /\ rec = "done"
          /\ pc' = "settled"
          /\ UNCHANGED rec
       \/ \* half-written row: resume it (only if the design allows takeover)
          /\ rec = "reserved"
          /\ TakeoverReserved
          /\ pc' = "charging"
          /\ UNCHANGED rec
       \/ \* first sight of this key
          /\ rec = "none"
          /\ pc' = "charging"
          /\ rec' = IF ReserveFirst THEN "reserved" ELSE "none"
    /\ UNCHANGED <<charges, crashes>>

\* The external side effect. A provider that dedupes on the key does not
\* create a second charge; one that does not, does.
Charge ==
    /\ pc = "charging"
    /\ charges' = IF ProviderIdempotent /\ charges > 0
                    THEN charges
                    ELSE charges + 1
    /\ pc' = "storing"
    /\ UNCHANGED <<rec, crashes>>

\* Durably record that the key is handled.
Store ==
    /\ pc = "storing"
    /\ rec' = "done"
    /\ pc' = "settled"
    /\ UNCHANGED <<charges, crashes>>

\* The process dies after the side effect started but before it finished.
\* Whatever was already durable stays durable; the caller retries.
Crash ==
    /\ pc \in {"charging", "storing"}
    /\ crashes < MaxCrashes
    /\ crashes' = crashes + 1
    /\ pc' = "idle"
    /\ UNCHANGED <<rec, charges>>

Next == Begin \/ Charge \/ Store \/ Crash

\* Crash is deliberately NOT fair: it may happen, it need not.
Spec ==
    /\ Init
    /\ [][Next]_vars
    /\ WF_vars(Begin)
    /\ WF_vars(Charge)
    /\ WF_vars(Store)

TypeOK ==
    /\ rec \in RecStates
    /\ pc \in PcStates
    /\ crashes \in 0..MaxCrashes
    /\ charges \in 0..(MaxCrashes + 1)

\* Safety: the caller is charged at most once no matter how often it retries.
NoDoubleCharge == charges <= 1

\* Liveness: a retried request does not wedge. A design can satisfy
\* NoDoubleCharge by never making progress -- this is the check that
\* rules that out.
EventuallySettled == <>(pc = "settled")

=============================================================================
