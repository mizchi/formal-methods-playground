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
