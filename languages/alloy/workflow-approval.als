/*
 * Probe: expense-approval workflow with role-gated transitions.
 *
 * Uses Alloy 6's temporal extension (`var`, `always`,
 * `eventually`, prime) to model a typical SaaS approval flow:
 *
 *   submitted  →  underReview  →  approved
 *                          \─→  rejected
 *
 * Properties:
 *   1. NoSelfApproval        — the submitter never approves
 *                               their own expense (safety,
 *                               separation of duties)
 *   2. ApprovalRequiresReview — `approved` is only reached via
 *                               `underReview`, never directly
 *   3. EveryRequestResolves   — eventually every submitted
 *                               request reaches approved or
 *                               rejected (sanity / non-vacuity)
 *
 * Run:
 *   alloy6 exec -f --command NoSelfApproval         workflow-approval.als
 *   alloy6 exec -f --command ApprovalRequiresReview workflow-approval.als
 *   alloy6 exec -f --command EveryRequestResolves   workflow-approval.als
 *
 * Expected:
 *   NoSelfApproval          UNSAT
 *   ApprovalRequiresReview  UNSAT
 *   EveryRequestResolves    SAT
 *
 * To bait a bug: remove the `r.submitter != u` guard from the
 * Approve action. NoSelfApproval then fails with a 2-step
 * trace where the submitter approves their own request.
 */

abstract sig Role {}
one sig Submitter, Manager extends Role {}

sig User {
  hasRole: one Role,
}

abstract sig Status {}
one sig submitted, underReview, approved, rejected extends Status {}

// Each Request is identified by who submitted it; the status
// flips through the lifecycle.
sig Request {
  submitter: one User,
  var status: one Status,
}

// ── Actions ──────────────────────────────────────────────────────

pred SubmitOpens[r: Request] {
  r.status = submitted
}

pred OpenReview[r: Request, u: User] {
  r.status = submitted
  u.hasRole = Manager
  r.status' = underReview
  all other: Request - r | other.status' = other.status
}

pred Approve[r: Request, u: User] {
  r.status = underReview
  u.hasRole = Manager
  // Separation of duties: the approver cannot be the submitter.
  r.submitter != u
  r.status' = approved
  all other: Request - r | other.status' = other.status
}

pred Reject[r: Request, u: User] {
  r.status = underReview
  u.hasRole = Manager
  r.status' = rejected
  all other: Request - r | other.status' = other.status
}

// Stutter step: when every request has reached a terminal
// state, no progress action is enabled. Without an explicit
// no-op the `always (some action)` fact below deadlocks and
// makes sanity runs UNSAT. Stutter keeps state unchanged.
pred Stutter {
  all r: Request | r.status' = r.status
}

pred Init {
  all r: Request | r.status = submitted
}

fact behavior {
  Init
  always (
    Stutter or
    some r: Request, u: User |
      OpenReview[r, u] or Approve[r, u] or Reject[r, u]
  )
}

// ── Properties ────────────────────────────────────────────────

// SAFETY: whenever the Approve action fires, the actor is not
// the request's submitter. This is enforced by the action's
// own pre-condition (`r.submitter != u`); the assertion makes
// the constraint explicit at the spec level so any future
// edit that loosens the action gets caught.
assert NoSelfApprovalAction {
  always (all r: Request, u: User |
    Approve[r, u] implies r.submitter != u)
}
check NoSelfApprovalAction for 4 but 6 steps

// SAFETY: status is monotonic — once approved or rejected,
// stays in that terminal state.
assert MonotonicResolution {
  always (all r: Request |
    (r.status = approved implies r.status' = approved)
    and (r.status = rejected implies r.status' = rejected))
}
check MonotonicResolution for 4 but 6 steps

// SAFETY: `approved` is reached only via `underReview`, never
// directly from `submitted`. The `status' = approved and
// status != approved` guard isolates the *transition* to
// approved; the Stutter case (already approved, stays
// approved) is correctly out of scope.
assert ApprovalRequiresReview {
  always (all r: Request |
    (r.status' = approved and r.status != approved)
      implies r.status = underReview)
}
check ApprovalRequiresReview for 4 but 6 steps

// SANITY: there is at least one trace where every request
// resolves (approved or rejected).
run EveryRequestResolves {
  eventually (all r: Request |
    r.status = approved or r.status = rejected)
} for 4 but 6 steps
