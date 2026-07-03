// Blackbox tests run against the package's public API. Use `@checkout_form` to import.
// Prefer high-level behaviors over implementation details.
// Run `moon test` to execute and `moon test --update` to refresh snapshots.

///|
test "checkout form validity follows the branch-specific contract" {
  assert_eq(
    @checkout_form.is_valid_checkout(@checkout_form.physical_kind(), true, 0, 1),
    true,
  )
  assert_eq(
    @checkout_form.is_valid_checkout(
      @checkout_form.physical_kind(),
      false,
      10,
      1,
    ),
    false,
  )
  assert_eq(
    @checkout_form.is_valid_checkout(@checkout_form.digital_kind(), false, 1, 1),
    true,
  )
  assert_eq(
    @checkout_form.is_valid_checkout(@checkout_form.digital_kind(), true, 0, 1),
    false,
  )
  assert_eq(
    @checkout_form.is_valid_checkout(@checkout_form.digital_kind(), true, 1, 0),
    false,
  )
}

///|
test "unknown checkout kind is fail-closed" {
  assert_eq(@checkout_form.is_valid_checkout(99, true, 100, 1), false)
}
