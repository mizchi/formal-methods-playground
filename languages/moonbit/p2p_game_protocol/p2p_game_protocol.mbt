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
pub fn verdict_incomplete() -> Int {
  4
}

///|
pub fn missing_value() -> Int {
  -1
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
#proof_pure
fn complete_tick(
  p1_commit : Int,
  p1_input : Int,
  p1_hash : Int,
  p2_commit : Int,
  p2_input : Int,
  p2_hash : Int,
) -> Bool {
  p1_commit != -1 &&
  p1_input != -1 &&
  p1_hash != -1 &&
  p2_commit != -1 &&
  p2_input != -1 &&
  p2_hash != -1
}

///|
#proof_pure
fn transcript_spec(
  p1_commit : Int,
  p1_input : Int,
  p1_hash : Int,
  p2_commit : Int,
  p2_input : Int,
  p2_hash : Int,
) -> Int {
  if !complete_tick(p1_commit, p1_input, p1_hash, p2_commit, p2_input, p2_hash) {
    4
  } else {
    tick_spec(p1_commit, p1_input, p1_hash, p2_commit, p2_input, p2_hash)
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

///|
pub struct TickTranscript {
  p1_commit : Int
  p1_input : Int
  p1_hash : Int
  p2_commit : Int
  p2_input : Int
  p2_hash : Int
}

///|
pub fn new_tick() -> TickTranscript {
  {
    p1_commit: missing_value(),
    p1_input: missing_value(),
    p1_hash: missing_value(),
    p2_commit: missing_value(),
    p2_input: missing_value(),
    p2_hash: missing_value(),
  }
}

///|
pub fn TickTranscript::commit_p1(
  self : TickTranscript,
  input : Int,
) -> TickTranscript {
  { ..self, p1_commit: make_commit(input) }
}

///|
pub fn TickTranscript::commit_p2(
  self : TickTranscript,
  input : Int,
) -> TickTranscript {
  { ..self, p2_commit: make_commit(input) }
}

///|
pub fn TickTranscript::reveal_p1(
  self : TickTranscript,
  input : Int,
) -> TickTranscript {
  { ..self, p1_input: input }
}

///|
pub fn TickTranscript::reveal_p2(
  self : TickTranscript,
  input : Int,
) -> TickTranscript {
  { ..self, p2_input: input }
}

///|
pub fn TickTranscript::state_hash_p1(
  self : TickTranscript,
  state_hash : Int,
) -> TickTranscript {
  { ..self, p1_hash: state_hash }
}

///|
pub fn TickTranscript::state_hash_p2(
  self : TickTranscript,
  state_hash : Int,
) -> TickTranscript {
  { ..self, p2_hash: state_hash }
}

///|
pub fn TickTranscript::expected_state_hash(self : TickTranscript) -> Int {
  expected_state_hash(self.p1_input, self.p2_input)
}

///|
pub fn TickTranscript::verify_transcript(
  self : TickTranscript,
) -> Int where {
  proof_ensure: result => {
    result ==
    transcript_spec(
      self.p1_commit,
      self.p1_input,
      self.p1_hash,
      self.p2_commit,
      self.p2_input,
      self.p2_hash,
    )
  },
} {
  transcript_spec(
    self.p1_commit,
    self.p1_input,
    self.p1_hash,
    self.p2_commit,
    self.p2_input,
    self.p2_hash,
  )
}
