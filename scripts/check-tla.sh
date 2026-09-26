#!/usr/bin/env bash
set -euo pipefail

run_tlc() {
  local spec="$1"
  echo "== tla: ${spec}"
  (cd languages/tla && tlc -config "${spec}.cfg" "${spec}.tla")
}

run_tlc OrderCheckout
run_tlc EventSourcing
run_tlc ActorMailbox
run_tlc P2PGameProtocol
run_tlc CloudRollout
run_tlc RateLimitRace
run_tlc IdempotentRetry
run_tlc SeatLimitWriteSkew

# Breaking variants: each must fail, and fail on the named property. A variant
# that turns green (or fails for another reason) means the check stopped being
# load-bearing.
run_tlc_expect_violation() {
  local spec="$1" cfg="$2" expected="$3"
  echo "== tla: ${cfg} expects '${expected}'"
  local output
  output="$(cd languages/tla && tlc -config "${cfg}.cfg" "${spec}.tla" 2>&1 || true)"
  if ! grep -Fq "${expected}" <<<"${output}"; then
    echo "${output}"
    echo "Expected '${expected}' from ${cfg}" >&2
    exit 1
  fi
}

run_tlc_expect_green() {
  local spec="$1" cfg="$2"
  echo "== tla: ${cfg}"
  (cd languages/tla && tlc -config "${cfg}.cfg" "${spec}.tla")
}

run_tlc_expect_green SeatLimitWriteSkew SeatLimitWriteSkew_lock
run_tlc_expect_violation IdempotentRetry IdempotentRetry_late "Invariant NoDoubleCharge is violated"
# The blocking cfg has one PROPERTY (EventuallySettled); TLC does not name it.
run_tlc_expect_violation IdempotentRetry IdempotentRetry_blocking "Temporal properties were violated"
run_tlc_expect_violation SeatLimitWriteSkew SeatLimitWriteSkew_si "Invariant SeatsWithinLimit is violated"
run_tlc_expect_violation SeatLimitWriteSkew SeatLimitWriteSkew_rrlock "Invariant SeatsWithinLimit is violated"
run_tlc_expect_violation RateLimitRace RateLimitRace_naive "Invariant NoOverGrant is violated"
