/*
 * Probe: multi-tenant data isolation.
 *
 * Models a SaaS with multiple tenants. Each User belongs to
 * exactly one Tenant. Resources (Documents) also belong to a
 * Tenant. The integrity invariant: a User never reads a
 * Document outside their own Tenant.
 *
 * Properties exercised:
 *   1. CrossTenantReadBlocked  — no Read edge crosses tenants
 *   2. WithinTenantReachable   — sanity: same-tenant reads work
 *   3. AdminOverrideBounded    — billing-admins CAN cross
 *                                tenants (by design) but their
 *                                trace is auditable in the
 *                                counter-example graph
 *
 * Run:
 *   alloy6 exec -f --command CrossTenantReadBlocked   multi-tenant.als
 *   alloy6 exec -f --command WithinTenantReachable    multi-tenant.als
 *   alloy6 exec -f --command AdminOverrideBounded     multi-tenant.als
 *
 * Expected:
 *   CrossTenantReadBlocked   UNSAT (safety holds)
 *   WithinTenantReachable    SAT
 *   AdminOverrideBounded     SAT (intentional surface — see body)
 */

sig Tenant {}

sig User {
  tenantOf: one Tenant,
}

sig Document {
  ownedBy: one Tenant,
}

abstract sig Role {}
one sig Regular, BillingAdmin extends Role {}

// Per-user role assignment.
sig UserRole {
  user: one User,
  role: one Role,
}

// The "read" edge being checked. In a real app this is the
// authorisation function the runtime invokes; here it's the
// declared rule.
pred CanRead[u: User, d: Document] {
  // Regular users can only read documents in their own tenant.
  (some ur: UserRole | ur.user = u and ur.role = Regular)
    implies u.tenantOf = d.ownedBy
  // BillingAdmins are allowed to cross tenants for billing
  // operations — a real-world break-glass scenario.
  else (some ur: UserRole | ur.user = u and ur.role = BillingAdmin)
}

// SAFETY: a Regular user never reads a document outside their
// tenant.
assert CrossTenantReadBlocked {
  all u: User, d: Document |
    (some ur: UserRole |
       ur.user = u and ur.role = Regular and CanRead[u, d])
      implies u.tenantOf = d.ownedBy
}
check CrossTenantReadBlocked for 4

// SANITY: same-tenant reads are reachable.
run WithinTenantReachable {
  some u: User, d: Document |
    u.tenantOf = d.ownedBy and CanRead[u, d]
} for 4

// AUDIT: a BillingAdmin CAN read across tenants. We don't assert
// this is wrong — we surface that the crack exists, the
// architect must explicitly accept it.
run AdminOverrideBounded {
  some u: User, d: Document, ur: UserRole |
    ur.user = u
    and ur.role = BillingAdmin
    and u.tenantOf != d.ownedBy
    and CanRead[u, d]
} for 4
