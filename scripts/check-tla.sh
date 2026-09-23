#!/usr/bin/env bash
set -euo pipefail

run_tlc() {
  local cfg="$1"
  local spec="${2:-$1}"
  echo "== tla: ${cfg}"
  (cd languages/tla && tlc -config "${cfg}.cfg" "${spec}.tla")
}

run_tlc OrderCheckout
run_tlc EventSourcing
run_tlc ActorMailbox
run_tlc P2PGameProtocol
run_tlc CloudRollout
run_tlc RateLimitRace
run_tlc IdempotentRetry
run_tlc SeatLimitWriteSkew

# T5: the replayed logs are generated from traces/*.json, so check the
# generated module is not stale before trusting what the replay says.
./scripts/trace-to-tla.sh --check
run_tlc SeatLimitTrace
run_tlc SeatLimitTrace_retry SeatLimitTrace
