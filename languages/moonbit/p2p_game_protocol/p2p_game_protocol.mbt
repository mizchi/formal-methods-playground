// Executable transcript verifier for the P2P game anti-cheat protocol.
//
// This intentionally uses small integer wire values so the implementation can
// be compared directly with the finite TLA+ model. Real deployments should
// replace commit/state-hash integers with cryptographic hashes and signatures.

///|
pub fn input_stay() -> Int {
  0
}

///|
pub fn input_move() -> Int {
  1
}

///|
pub fn input_speedhack() -> Int {
  2
}

///|
pub fn verdict_accept() -> Int {
  0
}

///|
pub fn verdict_bad_commit() -> Int {
  1
}

///|
pub fn verdict_invalid_input() -> Int {
  2
}

///|
pub fn verdict_hash_mismatch() -> Int {
  3
}

///|
#proof_pure
fn valid_input(input : Int) -> Bool {
  input == 0 || input == 1
}

///|
#proof_pure
fn commit_of(input : Int) -> Int {
  input + 10
}

///|
#proof_pure
fn state_hash_of(p1_input : Int, p2_input : Int) -> Int {
  if p1_input == p2_input {
    100
  } else {
    101
  }
}

///|
#proof_pure
fn tick_spec(
  p1_commit : Int,
  p1_input : Int,
  p1_hash : Int,
  p2_commit : Int,
  p2_input : Int,
  p2_hash : Int,
) -> Int {
  if p1_commit != commit_of(p1_input) || p2_commit != commit_of(p2_input) {
    1
  } else if !valid_input(p1_input) || !valid_input(p2_input) {
    2
  } else {
    let expected = state_hash_of(p1_input, p2_input)
    if p1_hash != expected || p2_hash != expected {
      3
    } else {
      0
    }
  }
}

///|
pub fn make_commit(input : Int) -> Int {
  commit_of(input)
}

///|
pub fn expected_state_hash(p1_input : Int, p2_input : Int) -> Int {
  state_hash_of(p1_input, p2_input)
}

///|
pub fn is_valid_input(
  input : Int,
) -> Bool where {
  proof_ensure: result => result == valid_input(input),
} {
  valid_input(input)
}

///|
pub fn verify_tick(
  p1_commit : Int,
  p1_input : Int,
  p1_hash : Int,
  p2_commit : Int,
  p2_input : Int,
  p2_hash : Int,
) -> Int where {
  proof_ensure: result => {
    result ==
    tick_spec(p1_commit, p1_input, p1_hash, p2_commit, p2_input, p2_hash)
  },
} {
  tick_spec(p1_commit, p1_input, p1_hash, p2_commit, p2_input, p2_hash)
}
