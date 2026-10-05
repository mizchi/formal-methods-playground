/*
 * Multi-tenant read authorization: docs vs implementation.
 *
 * Docs (trusted):
 *   D1 Owner reads projects and invoices in their own org.
 *   D2 BillingAdmin reads only invoices in their own org.
 *   D3 BillingAdmin cannot read projects.
 *   D4 Support override exists for billing investigations: invoice reads only.
 *   D5 No role reads a resource in another org.
 *
 * Implementation (observed):
 *   if (user.role === "Owner") return true;
 *   if (user.role === "BillingAdmin" &&
 *       (action === "read_invoice" || action === "read_project")) return true;
 *   if (user.supportOverride) return true;
 *   return false;
 *
 * Expected (scripts/check-alloy.sh):
 *   Impl*    checks  SAT   (counterexamples: the implementation breaks the docs)
 *   Fixed*   checks  UNSAT
 *   Sanity*  runs    SAT   (the fixed rule is not "deny everything")
 */

sig Org {}

abstract sig Role {}
one sig Owner, BillingAdmin, Member extends Role {}

sig User {
  org: one Org,
  role: one Role,
}
// Users with the support override flag set.
sig SupportOverride in User {}

abstract sig Resource { owner: one Org }
sig Project, Invoice extends Resource {}

// The action is determined by the resource kind: read_project / read_invoice.

pred ImplCanRead[u: User, r: Resource] {
  u.role = Owner
  or (u.role = BillingAdmin and (r in Invoice or r in Project))
  or u in SupportOverride
}

// The rule the docs describe.
pred DocCanRead[u: User, r: Resource] {
  u.org = r.owner
  and (
    u.role = Owner
    or (u.role = BillingAdmin and r in Invoice)
    or (u in SupportOverride and r in Invoice)
  )
}

// The proposed fix, in the shape of the code (repro/authz.ts, canReadFixed):
//   if (user.org !== resource.org) return false;
//   if (user.role === "Owner") return true;
//   if (action === "read_invoice" &&
//       (user.role === "BillingAdmin" || user.supportOverride)) return true;
//   return false;
pred FixedCanRead[u: User, r: Resource] {
  u.org = r.owner
  and (
    u.role = Owner
    or (r in Invoice and (u.role = BillingAdmin or u in SupportOverride))
  )
}

// ---- properties, stated once per rule ----

pred NoCrossTenantRead[can: User -> Resource] {
  all u: User, r: Resource | u -> r in can implies u.org = r.owner
}
pred NoBillingAdminProjectRead[can: User -> Resource] {
  all u: User, p: Project | u.role = BillingAdmin implies u -> p not in can
}
// Member has no grant of its own, so anything a Member with the override can
// read was granted by the override.
pred SupportInvoiceOnly[can: User -> Resource] {
  all u: SupportOverride, r: Resource |
    (u.role = Member and u -> r in can) implies r in Invoice
}

fun impl: User -> Resource  { { u: User, r: Resource | ImplCanRead[u, r] } }
fun fixed: User -> Resource { { u: User, r: Resource | FixedCanRead[u, r] } }
fun doc: User -> Resource   { { u: User, r: Resource | DocCanRead[u, r] } }

// ---- the implementation against the docs: expect counterexamples ----

check ImplNoCrossTenantRead         { NoCrossTenantRead[impl] }         for 3
check ImplNoBillingAdminProjectRead { NoBillingAdminProjectRead[impl] } for 3
check ImplSupportInvoiceOnly        { SupportInvoiceOnly[impl] }        for 3
check ImplMatchesDocs               { impl = doc }                      for 3

// ---- the fix: expect no counterexample within scope ----

check FixedNoCrossTenantRead         { NoCrossTenantRead[fixed] }         for 4
check FixedNoBillingAdminProjectRead { NoBillingAdminProjectRead[fixed] } for 4
check FixedSupportInvoiceOnly        { SupportInvoiceOnly[fixed] }        for 4
check FixedMatchesDocs               { fixed = doc }                      for 4

// ---- sanity: each documented grant is reachable under the fix ----

run SanityOwnerReadsOwnProject {
  some u: User, p: Project | u.role = Owner and u.org = p.owner and u -> p in fixed
} for 3
run SanityBillingAdminReadsOwnInvoice {
  some u: User, i: Invoice | u.role = BillingAdmin and u.org = i.owner and u -> i in fixed
} for 3
run SanitySupportReadsInvoice {
  some u: SupportOverride, i: Invoice | u.role = Member and u -> i in fixed
} for 3
