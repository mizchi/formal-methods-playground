#!/usr/bin/env bash
set -euo pipefail

if ! command -v fizz >/dev/null 2>&1; then
  echo "fizz not found. Enter the nix devShell: nix develop" >&2
  exit 127
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

check_passes() {
  local name="$1"
  local spec="$2"
  local temp_spec="$tmp_dir/$name.fizz"
  local output

  echo "== fizzbee: $name"
  cp "$spec" "$temp_spec"
  if ! output="$(fizz --test --output-dir "$tmp_dir/$name" "$temp_spec" 2>&1)"; then
    printf '%s\n' "$output" >&2
    return 1
  fi
  printf '%s\n' "$output"

  if printf '%s\n' "$output" | grep -qE '^FAILED:|^DEADLOCK'; then
    echo "expected $name to pass" >&2
    return 1
  fi
  if ! printf '%s\n' "$output" | grep -q '^PASSED: Model checker completed successfully'; then
    echo "FizzBee did not report a successful model check for $name" >&2
    return 1
  fi
}

check_fails_with() {
  local name="$1"
  local spec="$2"
  local expected="$3"
  local temp_spec="$tmp_dir/$name.fizz"
  local output

  echo "== fizzbee negative control: $name"
  cp "$spec" "$temp_spec"
  if ! output="$(fizz --test --output-dir "$tmp_dir/$name" "$temp_spec" 2>&1)"; then
    printf '%s\n' "$output" >&2
    return 1
  fi
  printf '%s\n' "$output"

  if ! printf '%s\n' "$output" | grep -q '^FAILED:'; then
    echo "expected $name to fail" >&2
    return 1
  fi
  if ! printf '%s\n' "$output" | grep -q "$expected"; then
    echo "expected $name output to contain: $expected" >&2
    return 1
  fi
}

check_passes \
  order-checkout \
  languages/fizzbee/OrderCheckout.fizz

check_fails_with \
  broken-cancel \
  languages/fizzbee/BrokenCancel.fizz \
  NoRefundWithoutRefundedState

check_fails_with \
  no-fairness \
  languages/fizzbee/NoFairness.fizz \
  PaymentResolves
