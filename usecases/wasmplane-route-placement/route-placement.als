/*
 * Probe: route snapshot placement bugs found in mizchi/wasmplane.
 *
 * This is a bug-hunting pattern for control-plane publish target
 * synthesis. The useful split is:
 *
 * - Legacy predicates produce SAT witnesses for the bad behavior.
 * - Fixed assertions return UNSAT for the same bad state under the
 *   repaired contract.
 *
 * Run from this directory (inside `nix develop`):
 *   alloy6 exec -f --command LegacyDuplicateDropsIsolation route-placement.als
 *   alloy6 exec -f --command FixedDuplicateCannotDropIsolation route-placement.als
 *   alloy6 exec -f --command FixedDuplicateDeliversIsolation route-placement.als
 *   alloy6 exec -f --command LegacyStaticBypassesPlacement route-placement.als
 *   alloy6 exec -f --command FixedStaticCannotReceivePlacedRoute route-placement.als
 *   alloy6 exec -f --command FixedStaticFiltered route-placement.als
 *   alloy6 exec -f --command LegacyTtlAllowsMissingHeartbeat route-placement.als
 *   alloy6 exec -f --command FixedTtlRequiresHeartbeat route-placement.als
 *   alloy6 exec -f --command FixedFreshHeartbeatCanBeActive route-placement.als
 *   alloy6 exec -f --command LegacyZeroMaxTargetsUsesFailover route-placement.als
 *   alloy6 exec -f --command FixedMaxTargetsZeroInvalid route-placement.als
 *   alloy6 exec -f --command FixedPositiveMaxTargetsCanBeValid route-placement.als
 *
 * Expectations:
 *   LegacyDuplicateDropsIsolation          SAT
 *   FixedDuplicateCannotDropIsolation      UNSAT
 *   FixedDuplicateDeliversIsolation        SAT
 *   LegacyStaticBypassesPlacement          SAT
 *   FixedStaticCannotReceivePlacedRoute    UNSAT
 *   FixedStaticFiltered                    SAT
 *   LegacyTtlAllowsMissingHeartbeat        SAT
 *   FixedTtlRequiresHeartbeat              UNSAT
 *   FixedFreshHeartbeatCanBeActive         SAT
 *   LegacyZeroMaxTargetsUsesFailover       SAT
 *   FixedMaxTargetsZeroInvalid             UNSAT
 *   FixedPositiveMaxTargetsCanBeValid      SAT
 */

abstract sig Project {}
one sig PlacedProject, IsolatedProject extends Project {}

abstract sig Url {}
one sig SharedUrl, StaticIadUrl, NrtUrl extends Url {}

abstract sig TargetSource {}
one sig StaticTarget, RegisteredNode extends TargetSource {}

sig PublishTarget {
  url: one Url,
  source: one TargetSource,
  routes: set Project,
}

fun delivered[u: Url]: set Project {
  { p: Project | some t: PublishTarget | t.url = u and p in t.routes }
}

// RP-001 legacy shape: static target is kept first for the same
// URL, so the registered node's isolated snapshot is dropped.
pred legacyDuplicateDropsIsolation {
  one t: PublishTarget |
    PublishTarget = t
    and t.url = SharedUrl
    and t.source = StaticTarget
    and no t.routes
}

run LegacyDuplicateDropsIsolation {
  legacyDuplicateDropsIsolation
} for 6

// RP-001 fixed contract: for duplicate URLs, the registered
// placement result wins, so the isolated route is still delivered.
pred fixedDuplicateScenario {
  one t: PublishTarget |
    PublishTarget = t
    and t.url = SharedUrl
    and t.source = RegisteredNode
    and t.routes = IsolatedProject
}

assert FixedDuplicateCannotDropIsolation {
  fixedDuplicateScenario implies IsolatedProject in delivered[SharedUrl]
}
check FixedDuplicateCannotDropIsolation for 6

run FixedDuplicateDeliversIsolation {
  fixedDuplicateScenario
  and IsolatedProject in delivered[SharedUrl]
} for 6

// RP-002 legacy shape: a static IAD target receives a route that
// was explicitly placed on NRT registered nodes.
pred legacyStaticBypassesPlacement {
  one static, registered: PublishTarget |
    PublishTarget = static + registered
    and static != registered
    and static.source = StaticTarget
    and static.url = StaticIadUrl
    and static.routes = PlacedProject
    and registered.source = RegisteredNode
    and registered.url = NrtUrl
    and registered.routes = PlacedProject
}

run LegacyStaticBypassesPlacement {
  legacyStaticBypassesPlacement
} for 6

// RP-002 fixed contract: static targets are retained for clearing
// stale routes, but routes governed by placement are filtered out.
pred fixedStaticFilteredScenario {
  one static, registered: PublishTarget |
    PublishTarget = static + registered
    and static != registered
    and static.source = StaticTarget
    and static.url = StaticIadUrl
    and no static.routes
    and registered.source = RegisteredNode
    and registered.url = NrtUrl
    and registered.routes = PlacedProject
}

assert FixedStaticCannotReceivePlacedRoute {
  fixedStaticFilteredScenario implies
    no t: PublishTarget | t.source = StaticTarget and PlacedProject in t.routes
}
check FixedStaticCannotReceivePlacedRoute for 6

run FixedStaticFiltered {
  fixedStaticFilteredScenario
} for 6

abstract sig Freshness {}
one sig NoHeartbeat, FreshHeartbeat, StaleHeartbeat extends Freshness {}

abstract sig Truth {}
one sig Yes, No extends Truth {}

sig RuntimeNode {
  freshness: one Freshness,
  publishActive: one Truth,
}

// RP-003 legacy shape: TTL mode still treats a never-heartbeated
// registered node as publish-active.
pred legacyTtlAllowsMissingHeartbeat {
  one n: RuntimeNode |
    RuntimeNode = n
    and n.freshness = NoHeartbeat
    and n.publishActive = Yes
}

run LegacyTtlAllowsMissingHeartbeat {
  legacyTtlAllowsMissingHeartbeat
} for 6

pred fixedTtlPredicate[n: RuntimeNode] {
  (n.freshness = FreshHeartbeat and n.publishActive = Yes)
  or (n.freshness != FreshHeartbeat and n.publishActive = No)
}

assert FixedTtlRequiresHeartbeat {
  no n: RuntimeNode |
    fixedTtlPredicate[n]
    and n.freshness = NoHeartbeat
    and n.publishActive = Yes
}
check FixedTtlRequiresHeartbeat for 6

run FixedFreshHeartbeatCanBeActive {
  some n: RuntimeNode |
    RuntimeNode = n
    and fixedTtlPredicate[n]
    and n.freshness = FreshHeartbeat
    and n.publishActive = Yes
} for 6

abstract sig MaxTargets {}
one sig ZeroTargets, OneTarget extends MaxTargets {}

sig PlacementRule {
  maxTargets: one MaxTargets,
  failoverPublishes: one Truth,
  valid: one Truth,
}

// RP-004 legacy shape: maxTargets = 0 empties the primary tier,
// then failover publishes even though the configuration is invalid.
pred legacyZeroMaxTargetsUsesFailover {
  one r: PlacementRule |
    PlacementRule = r
    and r.maxTargets = ZeroTargets
    and r.valid = Yes
    and r.failoverPublishes = Yes
}

run LegacyZeroMaxTargetsUsesFailover {
  legacyZeroMaxTargetsUsesFailover
} for 6

pred fixedRuleContract[r: PlacementRule] {
  (r.maxTargets = OneTarget and r.valid = Yes)
  or (r.maxTargets = ZeroTargets and r.valid = No)
}

assert FixedMaxTargetsZeroInvalid {
  no r: PlacementRule |
    fixedRuleContract[r]
    and r.maxTargets = ZeroTargets
    and r.valid = Yes
}
check FixedMaxTargetsZeroInvalid for 6

run FixedPositiveMaxTargetsCanBeValid {
  some r: PlacementRule |
    PlacementRule = r
    and fixedRuleContract[r]
    and r.maxTargets = OneTarget
    and r.valid = Yes
} for 6
