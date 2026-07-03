#!/usr/bin/env bash
set -euo pipefail

run_expect() {
  local file="$1"
  local command="$2"
  local expected="$3"

  echo "== alloy: ${file} :: ${command} expects ${expected}"
  local output
  output="$(alloy6 exec -f --command "${command}" "${file}" 2>&1)"
  echo "${output}"

  if ! grep -Eq "[[:space:]]${expected}([[:space:]]|$)" <<<"${output}"; then
    echo "Expected ${expected} for ${file} :: ${command}" >&2
    exit 1
  fi
}

run_expect languages/alloy/app-rbac.als ViewerScopedToPublicScreens UNSAT
run_expect languages/alloy/app-rbac.als NonAdminNeverAtSettings UNSAT
run_expect languages/alloy/app-rbac.als AdminCanReachSettings SAT

run_expect languages/alloy/multi-tenant.als CrossTenantReadBlocked UNSAT
run_expect languages/alloy/multi-tenant.als WithinTenantReachable SAT
run_expect languages/alloy/multi-tenant.als AdminOverrideBounded SAT

run_expect languages/alloy/workflow-approval.als NoSelfApprovalAction UNSAT
run_expect languages/alloy/workflow-approval.als MonotonicResolution UNSAT
run_expect languages/alloy/workflow-approval.als ApprovalRequiresReview UNSAT
run_expect languages/alloy/workflow-approval.als EveryRequestResolves SAT

run_expect usecases/terraform-reachability/reachability.als FrontendCannotReachDbDirectly UNSAT
run_expect usecases/terraform-reachability/reachability.als FrontendNeverTransitivelyReachesDb SAT
run_expect usecases/terraform-reachability/reachability.als ApiCanReachDb SAT

run_expect usecases/wasmplane-route-placement/route-placement.als LegacyDuplicateDropsIsolation SAT
run_expect usecases/wasmplane-route-placement/route-placement.als FixedDuplicateCannotDropIsolation UNSAT
run_expect usecases/wasmplane-route-placement/route-placement.als FixedDuplicateDeliversIsolation SAT
run_expect usecases/wasmplane-route-placement/route-placement.als LegacyStaticBypassesPlacement SAT
run_expect usecases/wasmplane-route-placement/route-placement.als FixedStaticCannotReceivePlacedRoute UNSAT
run_expect usecases/wasmplane-route-placement/route-placement.als FixedStaticFiltered SAT
run_expect usecases/wasmplane-route-placement/route-placement.als LegacyTtlAllowsMissingHeartbeat SAT
run_expect usecases/wasmplane-route-placement/route-placement.als FixedTtlRequiresHeartbeat UNSAT
run_expect usecases/wasmplane-route-placement/route-placement.als FixedFreshHeartbeatCanBeActive SAT
run_expect usecases/wasmplane-route-placement/route-placement.als LegacyZeroMaxTargetsUsesFailover SAT
run_expect usecases/wasmplane-route-placement/route-placement.als FixedMaxTargetsZeroInvalid UNSAT
run_expect usecases/wasmplane-route-placement/route-placement.als FixedPositiveMaxTargetsCanBeValid SAT
