/*
 * Probe: microservice reachability check derived from a
 * terraform-style security-group graph.
 *
 * Same shape as a real `terraform plan` would imply: services
 * live in security groups, security groups carry an `ingressFrom`
 * relation that says "I admit traffic from these other SGs."
 * Reachability is then a transitive-closure question over that
 * relation.
 *
 * In production the fact section below would be machine-emitted
 * from `terraform show -json`. For this probe the facts are
 * hand-encoded so the file runs standalone — see fixture/main.tf
 * for the corresponding HCL source.
 *
 * Run from this directory (inside `nix develop`):
 *   alloy6 exec -f --command FrontendCannotReachDbDirectly reachability.als
 *   alloy6 exec -f --command FrontendNeverTransitivelyReachesDb reachability.als
 *   alloy6 exec -f --command ApiCanReachDb reachability.als
 *
 * Expectations:
 *   FrontendCannotReachDbDirectly         UNSAT  (direct edge absent)
 *   FrontendNeverTransitivelyReachesDb    SAT (counter-example)
 *                                         — frontend → api → db is
 *                                         a real chained path, the
 *                                         architect must accept or
 *                                         break it
 *   ApiCanReachDb                         SAT (sanity)
 */

abstract sig Service {}
one sig Frontend, Api, Db extends Service {}

sig SecurityGroup {
  member: one Service,
  // Sources allowed to ingress into this SG. The terraform
  // analogue is `aws_security_group_rule.type = "ingress"`
  // with `source_security_group_id = <other SG>`.
  ingressFrom: set SecurityGroup,
}

// Direct edge: a can reach b iff a's SG is listed in b's ingress.
pred CanReach[a, b: Service] {
  some sa, sb: SecurityGroup |
    sa.member = a
    and sb.member = b
    and sa in sb.ingressFrom
}

// Transitive closure over all SG-to-SG edges. Catches paths that
// the rule table doesn't make obvious — e.g. frontend can route
// through api to reach db even though no rule names them
// together.
fun edges: SecurityGroup -> SecurityGroup {
  { sa, sb: SecurityGroup | sa in sb.ingressFrom }
}

pred CanReachTransitive[a, b: Service] {
  some sa, sb: SecurityGroup |
    sa.member = a
    and sb.member = b
    and (sa -> sb) in ^edges
}

// ── Facts (terraform-derived; hand-encoded for this probe) ────

one sig SgFrontend, SgApi, SgDb extends SecurityGroup {}

fact memberships {
  SgFrontend.member = Frontend
  SgApi.member = Api
  SgDb.member = Db
  SecurityGroup = SgFrontend + SgApi + SgDb
}

fact rules {
  // SG-Frontend has no ingress (egress-only in this stack).
  no SgFrontend.ingressFrom
  // SG-Api admits SG-Frontend.
  SgApi.ingressFrom = SgFrontend
  // SG-Db admits SG-Api.
  SgDb.ingressFrom = SgApi
}

// ── Properties ────────────────────────────────────────────────

// SAFETY: there is no direct rule allowing frontend → db.
assert FrontendCannotReachDbDirectly {
  not CanReach[Frontend, Db]
}
check FrontendCannotReachDbDirectly for 3

// SANITY: api can reach db (model isn't vacuously safe).
run ApiCanReachDb {
  CanReach[Api, Db]
} for 3

// TRANSITIVE: deliberately false — we expect this assertion to
// FAIL with a counter-example trace frontend → api → db. The
// counter-example is the actual decision surface: chained
// reachability through an authorised proxy is real, the
// architect must either accept it or insert a guard at api.
assert FrontendNeverTransitivelyReachesDb {
  not CanReachTransitive[Frontend, Db]
}
check FrontendNeverTransitivelyReachesDb for 3
