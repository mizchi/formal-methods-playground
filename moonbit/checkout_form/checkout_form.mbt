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

/// Returns the larger of two integers.
pub fn max_of_two(a : Int, b : Int) -> Int where {
  proof_ensure: result => result >= a,
  proof_ensure: result => result >= b,
} {
  if a >= b {
    a
  } else {
    b
  }
}

/// Returns the absolute value of an integer.
///
/// `@int.MIN_VALUE` is not expressible in proof annotations
/// (v0.1.20260427: "unsupported expression in logic body"),
/// so the precondition uses a literal bound instead.
pub fn safe_abs(x : Int) -> Int where {
  proof_require: x > -2147483648,
  proof_ensure: result => result >= 0,
} {
  if x >= 0 {
    x
  } else {
    -x
  }
}
