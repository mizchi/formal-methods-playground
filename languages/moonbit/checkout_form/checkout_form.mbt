// Probe: MoonBit `moon prove` formal verification.
//
// Backend: Why3 → Z3 / CVC5 / Alt-Ergo (all in the nix devShell).
// Run from this package directory:
//
//   moon prove
//
// Two functions:
//   max_of_two   — should verify
//   safe_abs     — should verify with proof_require guarding
//                  underflow on -Int::MIN_VALUE

///|
/// Returns the larger of two integers.
pub fn max_of_two(
  a : Int,
  b : Int,
) -> Int where {
  proof_ensure: result => result >= a,
  proof_ensure: result => result >= b,
} {
  if a >= b {
    a
  } else {
    b
  }
}

///|
/// Returns the absolute value of an integer.
///
/// `@int.MIN_VALUE` is not expressible in proof annotations
/// (v0.1.20260427: "unsupported expression in logic body"),
/// so the precondition uses a literal bound instead.
pub fn safe_abs(
  x : Int,
) -> Int where {
  proof_require: x > -2147483648,
  proof_ensure: result => result >= 0,
} {
  if x >= 0 {
    x
  } else {
    -x
  }
}

///|
/// Encoded kind for a physical order.
///
/// Kept as an `Int` so the same contract can be mirrored directly
/// in the SMT-LIB probe without a MoonBit-specific enum encoding.
pub fn physical_kind() -> Int {
  0
}

///|
/// Encoded kind for a digital order.
pub fn digital_kind() -> Int {
  1
}

///|
#proof_pure
fn checkout_spec(
  kind : Int,
  has_shipping : Bool,
  email_len : Int,
  total : Int,
) -> Bool {
  if total > 0 {
    if kind == 0 {
      has_shipping
    } else if kind == 1 {
      email_len > 0
    } else {
      false
    }
  } else {
    false
  }
}

///|
/// Pure checkout-form decision function extracted from the
/// branch-specific product rule:
///
/// - every valid order must have a strictly positive total
/// - physical orders require a shipping address
/// - digital orders require a non-empty email
/// - unknown order kinds fail closed
pub fn is_valid_checkout(
  kind : Int,
  has_shipping : Bool,
  email_len : Int,
  total : Int,
) -> Bool where {
  proof_ensure: result => {
    result == checkout_spec(kind, has_shipping, email_len, total)
  },
} {
  checkout_spec(kind, has_shipping, email_len, total)
}
