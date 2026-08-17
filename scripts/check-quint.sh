#!/usr/bin/env bash
set -euo pipefail

spec="languages/quint/OrderCheckout.qnt"

echo "== quint: typecheck ${spec}"
quint typecheck "${spec}"

echo "== quint: verify safety and liveness with TLC"
quint verify "${spec}" \
  --backend tlc \
  --main OrderCheckout \
  --invariant typeOk,refundedOnlyInRefundedState \
  --temporal paymentResolves

echo "== quint: broken cancel must violate refundedOnlyInRefundedState"
if output="$(quint verify "${spec}" \
  --backend tlc \
  --main OrderCheckout \
  --step brokenStep \
  --invariant refundedOnlyInRefundedState 2>&1)"; then
  echo "Expected brokenStep to violate refundedOnlyInRefundedState" >&2
  exit 1
fi

echo "${output}"
if ! grep -Eqi "invariant violated|violation" <<<"${output}"; then
  echo "brokenStep failed for an unexpected reason" >&2
  exit 1
fi

echo "== quint: liveness without fairness must fail"
if output="$(quint verify "${spec}" \
  --backend tlc \
  --main OrderCheckout \
  --temporal paymentResolvesWithoutFairness 2>&1)"; then
  echo "Expected paymentResolvesWithoutFairness to fail" >&2
  exit 1
fi

echo "${output}"
if ! grep -Eqi "temporal property.*violated|violation|counterexample" <<<"${output}"; then
  echo "paymentResolvesWithoutFairness failed for an unexpected reason" >&2
  exit 1
fi
