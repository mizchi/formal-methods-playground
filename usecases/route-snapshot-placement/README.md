# wasmplane-route-placement/

Probe: model route snapshot publish target synthesis bugs found
while hardening [`mizchi/wasmplane`](https://github.com/mizchi/wasmplane).

## What this models

The wasmplane control plane publishes route snapshots to runtime
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
cd usecases/wasmplane-route-placement
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

The concrete wasmplane findings were:

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
