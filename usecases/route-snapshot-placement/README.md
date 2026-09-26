# route-snapshot-placement/

Probe: model route snapshot publish target synthesis bugs in a
control plane that places routes onto runtime hosts.

## What this models

The control plane publishes route snapshots to runtime
hosts. The bug-prone surface is the composition of:

- registered runtime nodes selected by placement policy
- static runtime targets retained for legacy deployments and route clearing
- URL dedupe when static and registered targets refer to the same host
- runtime heartbeat freshness under an active TTL
- placement `maxTargets` validation before failover

The Alloy file intentionally keeps the world small. It does not
model HTTP, databases, or snapshot JSON. It models only the
relations needed to expose the bug pattern: target source, URL,
delivered projects, heartbeat freshness, and rule validity.

## Run

```sh
cd usecases/route-snapshot-placement
nix develop ../..  # if not already in devShell

alloy6 exec -f --command LegacyDuplicateDropsIsolation route-placement.als
alloy6 exec -f --command FixedDuplicateCannotDropIsolation route-placement.als
alloy6 exec -f --command FixedDuplicateDeliversIsolation route-placement.als
alloy6 exec -f --command LegacyStaticBypassesPlacement route-placement.als
alloy6 exec -f --command FixedStaticCannotReceivePlacedRoute route-placement.als
alloy6 exec -f --command FixedStaticFiltered route-placement.als
alloy6 exec -f --command LegacyTtlAllowsMissingHeartbeat route-placement.als
alloy6 exec -f --command FixedTtlRequiresHeartbeat route-placement.als
alloy6 exec -f --command FixedFreshHeartbeatCanBeActive route-placement.als
alloy6 exec -f --command LegacyZeroMaxTargetsUsesFailover route-placement.als
alloy6 exec -f --command FixedMaxTargetsZeroInvalid route-placement.als
alloy6 exec -f --command FixedPositiveMaxTargetsCanBeValid route-placement.als
```

Verified expectations:

```
LegacyDuplicateDropsIsolation          SAT
FixedDuplicateCannotDropIsolation      UNSAT
FixedDuplicateDeliversIsolation        SAT
LegacyStaticBypassesPlacement          SAT
FixedStaticCannotReceivePlacedRoute    UNSAT
FixedStaticFiltered                    SAT
LegacyTtlAllowsMissingHeartbeat        SAT
FixedTtlRequiresHeartbeat              UNSAT
FixedFreshHeartbeatCanBeActive         SAT
LegacyZeroMaxTargetsUsesFailover       SAT
FixedMaxTargetsZeroInvalid             UNSAT
FixedPositiveMaxTargetsCanBeValid      SAT
```

## Bug Pattern

This usecase is for the "compose two individually reasonable
sets, then lose the specific contract at the merge" class of
control-plane bugs.

The concrete bug shapes are:

1. Static target first-wins dedupe could shadow the registered
   node-specific snapshot for an isolated project.
2. Static targets could receive routes governed by placement
   policy, bypassing region/pool constraints.
3. TTL mode allowed a registered node with no heartbeat to remain
   publish-eligible.
4. `maxTargets: 0` could empty the primary tier and accidentally
   select failover.

The repaired contract is:

- registered placement results win URL dedupe over static targets
- static targets receive only routes not governed by placement or
  tenant isolation/drain rules
- active TTL mode requires `lastSeenAt`
- `maxTargets` must be a positive integer

## Why Alloy

The useful questions are relational and finite: which target
source owns a URL, which projects are delivered through that URL,
which freshness state permits publish eligibility, and which
configuration states are valid. Alloy gives small SAT witnesses
for the legacy bug shapes and UNSAT checks for the repaired
contract without pulling in the actual TypeScript runtime.

## Domain ledger

| field | value |
| --- | --- |
| source | the control plane's publish target synthesis (a TypeScript runtime not in this repo), reduced to the four bug shapes in "Bug Pattern" |
| expected claim | Registered placement results win URL dedupe; static targets receive only routes not governed by placement or tenant isolation/drain rules; active TTL mode requires `lastSeenAt`; `maxTargets` is a positive integer. |
| implementation observation | Legacy: static first-wins dedupe drops an isolated project's snapshot, static targets receive placed routes, TTL mode keeps a never-heartbeated node publish-eligible, and `maxTargets: 0` empties the primary tier and selects failover. |
| model question | Can each legacy bad state exist (run), is the same state excluded under the repaired contract (check), and can the repaired contract still reach its good state (sanity run)? |
| tool | Alloy 6 (scope 6) |
| machine result | `Legacy*` (4 runs): SAT / `FixedDuplicateCannotDropIsolation`, `FixedStaticCannotReceivePlacedRoute`, `FixedTtlRequiresHeartbeat`, `FixedMaxTargetsZeroInvalid`: UNSAT / `FixedDuplicateDeliversIsolation`, `FixedStaticFiltered`, `FixedFreshHeartbeatCanBeActive`, `FixedPositiveMaxTargetsCanBeValid`: SAT |
| witness | one atom each, e.g. `LegacyDuplicateDropsIsolation`: a single static target on `SharedUrl` with no routes; `LegacyStaticBypassesPlacement`: a static IAD target and a registered NRT node both carry `PlacedProject` |
| reproduction | none yet |
| domain wording | When static and registered targets are merged, an isolated project can lose its node-specific snapshot and a route placed on NRT can also be served from a static IAD target. |
| domain question | Are static targets meant only for legacy deployments and route clearing, so that they never receive routes governed by placement or tenant isolation/drain rules? |
| decision | bug; the repaired contract (`Fixed*` commands) is the CI check |
| lock | `nix develop -c just check-alloy` |
