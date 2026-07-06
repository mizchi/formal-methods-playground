--------------------------- MODULE P2PGameProtocol ---------------------------
(*
 * Minimal P2P game anti-cheat transcript protocol.
 *
 * The model intentionally does not try to prove that a client is honest.
 * Instead it proves that an accepted tick has a self-checking transcript:
 *
 *   1. each peer committed before revealing an input
 *   2. each reveal matches the earlier commit
 *   3. revealed inputs satisfy the game rule validator
 *   4. every peer signs the deterministic state hash for the same input log
 *
 * A cheating peer may choose any commit, reveal, or state hash. The protocol
 * should either reject the tick with evidence or accept only a valid transcript.
 *
 * Run:
 *   tlc -config P2PGameProtocol.cfg P2PGameProtocol.tla
 *
 * Expected:
 *   - NoBadCommitAccepted, NoInvalidInputAccepted, AcceptedHashesAgree,
 *     DisputeHasEvidence, and EvidenceIsSound all hold.
 *   - Completed phases resolve under weak fairness on the phase-check actions.
 *)
EXTENDS Naturals, FiniteSets

CONSTANTS P1, P2

Players == {P1, P2}

Inputs == {"stay", "move", "speedhack"}
ValidInputs == {"stay", "move"}

Commitments == {"commitStay", "commitMove", "commitSpeedhack", "fakeCommit"}
Hashes == {"hashSame", "hashDifferent", "fakeHash"}
Evidence == {"badCommit", "invalidInput", "hashMismatch"}

None == "none"

VARIABLES phase, commits, reveals, hashes, evidence

vars == <<phase, commits, reveals, hashes, evidence>>

Phases == {"commit", "reveal", "hash", "accepted", "disputed"}

CommitOf(input) ==
    IF input = "stay" THEN "commitStay"
    ELSE IF input = "move" THEN "commitMove"
    ELSE IF input = "speedhack" THEN "commitSpeedhack"
    ELSE "fakeCommit"

ValidInput(input) == input \in ValidInputs

StateHashOf(inputLog) ==
    IF inputLog[P1] = inputLog[P2] THEN "hashSame" ELSE "hashDifferent"

AllPresent(mapping) ==
    \A p \in Players : mapping[p] # None

BadCommit ==
    \E p \in Players : commits[p] # CommitOf(reveals[p])

BadInput ==
    \E p \in Players : ~ValidInput(reveals[p])

HashFault ==
    /\ AllPresent(hashes)
    /\ \E p \in Players : hashes[p] # StateHashOf(reveals)

InputEvidence ==
    {e \in Evidence :
        \/ e = "badCommit" /\ BadCommit
        \/ e = "invalidInput" /\ BadInput}

Init ==
    /\ phase = "commit"
    /\ commits = [p \in Players |-> None]
    /\ reveals = [p \in Players |-> None]
    /\ hashes = [p \in Players |-> None]
    /\ evidence = {}

Commit(p, commitment) ==
    /\ phase = "commit"
    /\ commits[p] = None
    /\ commitment \in Commitments
    /\ commits' = [commits EXCEPT ![p] = commitment]
    /\ UNCHANGED <<phase, reveals, hashes, evidence>>

StartReveal ==
    /\ phase = "commit"
    /\ AllPresent(commits)
    /\ phase' = "reveal"
    /\ UNCHANGED <<commits, reveals, hashes, evidence>>

Reveal(p, input) ==
    /\ phase = "reveal"
    /\ reveals[p] = None
    /\ input \in Inputs
    /\ reveals' = [reveals EXCEPT ![p] = input]
    /\ UNCHANGED <<phase, commits, hashes, evidence>>

CheckReveals ==
    /\ phase = "reveal"
    /\ AllPresent(reveals)
    /\ IF BadCommit \/ BadInput
       THEN /\ phase' = "disputed"
            /\ evidence' = evidence \union InputEvidence
            /\ UNCHANGED <<commits, reveals, hashes>>
       ELSE /\ phase' = "hash"
            /\ UNCHANGED <<commits, reveals, hashes, evidence>>

SendHash(p, h) ==
    /\ phase = "hash"
    /\ hashes[p] = None
    /\ h \in Hashes
    /\ hashes' = [hashes EXCEPT ![p] = h]
    /\ UNCHANGED <<phase, commits, reveals, evidence>>

CheckHashes ==
    /\ phase = "hash"
    /\ AllPresent(hashes)
    /\ IF HashFault
       THEN /\ phase' = "disputed"
            /\ evidence' = evidence \union {"hashMismatch"}
            /\ UNCHANGED <<commits, reveals, hashes>>
       ELSE /\ phase' = "accepted"
            /\ UNCHANGED <<commits, reveals, hashes, evidence>>

Next ==
    \/ \E p \in Players, c \in Commitments : Commit(p, c)
    \/ StartReveal
    \/ \E p \in Players, i \in Inputs : Reveal(p, i)
    \/ CheckReveals
    \/ \E p \in Players, h \in Hashes : SendHash(p, h)
    \/ CheckHashes

Spec ==
    /\ Init
    /\ [][Next]_vars
    /\ WF_vars(StartReveal)
    /\ WF_vars(CheckReveals)
    /\ WF_vars(CheckHashes)

\* ── Safety invariants ──────────────────────────────────────────────────────

TypeOK ==
    /\ phase \in Phases
    /\ commits \in [Players -> (Commitments \union {None})]
    /\ reveals \in [Players -> (Inputs \union {None})]
    /\ hashes \in [Players -> (Hashes \union {None})]
    /\ evidence \subseteq Evidence

AcceptedTranscriptComplete ==
    phase = "accepted" =>
        /\ AllPresent(commits)
        /\ AllPresent(reveals)
        /\ AllPresent(hashes)

NoBadCommitAccepted ==
    phase = "accepted" =>
        \A p \in Players : commits[p] = CommitOf(reveals[p])

NoInvalidInputAccepted ==
    phase = "accepted" =>
        \A p \in Players : ValidInput(reveals[p])

AcceptedHashesAgree ==
    phase = "accepted" =>
        \A p \in Players : hashes[p] = StateHashOf(reveals)

DisputeHasEvidence ==
    phase = "disputed" => evidence # {}

EvidenceIsSound ==
    /\ "badCommit" \in evidence => BadCommit
    /\ "invalidInput" \in evidence => BadInput
    /\ "hashMismatch" \in evidence => HashFault

\* ── Progress once peers provide a complete transcript phase ────────────────

CompleteCommitResolves ==
    (phase = "commit" /\ AllPresent(commits)) ~> (phase = "reveal")

CompleteRevealResolves ==
    (phase = "reveal" /\ AllPresent(reveals)) ~> (phase \in {"hash", "disputed"})

CompleteHashResolves ==
    (phase = "hash" /\ AllPresent(hashes)) ~> (phase \in {"accepted", "disputed"})

=============================================================================
