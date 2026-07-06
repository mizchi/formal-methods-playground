----------------------------- MODULE CloudRollout ----------------------------
(*
 * Probe: cloud rollout state-machine check.
 *
 * This models a blue/green-style deployment behind a load balancer:
 *
 *   old target group is healthy and serving
 *   new target group is provisioned
 *   new target group becomes healthy
 *   DB migration / compatibility gate becomes ready
 *   traffic shifts to new
 *   old target group is terminated
 *
 * It does not model a vendor API. It models the contract we want the
 * orchestrator / CodeDeploy / Terraform apply / runbook to preserve.
 *
 * Run:
 *   tlc -config CloudRollout.cfg CloudRollout.tla
 *)

VARIABLES phase, oldHealthy, newHealthy, dbReady, traffic

vars == <<phase, oldHealthy, newHealthy, dbReady, traffic>>

Phases == {"preparing", "warming", "shifted", "done"}
TrafficTargets == {"old", "new"}

Init ==
    /\ phase = "preparing"
    /\ oldHealthy = TRUE
    /\ newHealthy = FALSE
    /\ dbReady = FALSE
    /\ traffic = "old"

ProvisionNew ==
    /\ phase = "preparing"
    /\ phase' = "warming"
    /\ UNCHANGED <<oldHealthy, newHealthy, dbReady, traffic>>

MarkNewHealthy ==
    /\ phase = "warming"
    /\ newHealthy = FALSE
    /\ newHealthy' = TRUE
    /\ UNCHANGED <<phase, oldHealthy, dbReady, traffic>>

ApplyMigration ==
    /\ phase \in {"preparing", "warming"}
    /\ dbReady = FALSE
    /\ dbReady' = TRUE
    /\ UNCHANGED <<phase, oldHealthy, newHealthy, traffic>>

ShiftTraffic ==
    /\ phase = "warming"
    /\ newHealthy
    /\ dbReady
    /\ traffic' = "new"
    /\ phase' = "shifted"
    /\ UNCHANGED <<oldHealthy, newHealthy, dbReady>>

TerminateOld ==
    /\ phase = "shifted"
    /\ traffic = "new"
    /\ oldHealthy' = FALSE
    /\ phase' = "done"
    /\ UNCHANGED <<newHealthy, dbReady, traffic>>

Next ==
    \/ ProvisionNew
    \/ MarkNewHealthy
    \/ ApplyMigration
    \/ ShiftTraffic
    \/ TerminateOld

Spec ==
    /\ Init
    /\ [][Next]_vars
    /\ WF_vars(ShiftTraffic)
    /\ WF_vars(TerminateOld)

\* ── Safety invariants ──────────────────────────────────────────────────────

TypeOK ==
    /\ phase \in Phases
    /\ oldHealthy \in BOOLEAN
    /\ newHealthy \in BOOLEAN
    /\ dbReady \in BOOLEAN
    /\ traffic \in TrafficTargets

TrafficOnlyToHealthyTarget ==
    /\ traffic = "old" => oldHealthy
    /\ traffic = "new" => newHealthy

NewTrafficRequiresDbReady ==
    traffic = "new" => dbReady

OldServesUntilCutover ==
    phase \in {"preparing", "warming"} =>
        /\ traffic = "old"
        /\ oldHealthy

DoneMeansNewOnly ==
    phase = "done" =>
        /\ traffic = "new"
        /\ newHealthy
        /\ ~oldHealthy
        /\ dbReady

\* ── Liveness after external readiness signals arrive ───────────────────────

ReadyRolloutEventuallyShifts ==
    (phase = "warming" /\ newHealthy /\ dbReady) ~> (traffic = "new")

ShiftedEventuallyDone ==
    phase = "shifted" ~> phase = "done"

=============================================================================
