///|
test "honest peers with matching commit reveal and state hash are accepted" {
  let p1_input = @p2p_game_protocol.input_stay()
  let p2_input = @p2p_game_protocol.input_move()
  let expected = @p2p_game_protocol.expected_state_hash(p1_input, p2_input)
  assert_eq(
    @p2p_game_protocol.verify_tick(
      @p2p_game_protocol.make_commit(p1_input),
      p1_input,
      expected,
      @p2p_game_protocol.make_commit(p2_input),
      p2_input,
      expected,
    ),
    @p2p_game_protocol.verdict_accept(),
  )
}

///|
test "revealing an input that does not match the commit is evidence" {
  let committed = @p2p_game_protocol.input_stay()
  let revealed = @p2p_game_protocol.input_move()
  let peer2 = @p2p_game_protocol.input_stay()
  let expected = @p2p_game_protocol.expected_state_hash(revealed, peer2)
  assert_eq(
    @p2p_game_protocol.verify_tick(
      @p2p_game_protocol.make_commit(committed),
      revealed,
      expected,
      @p2p_game_protocol.make_commit(peer2),
      peer2,
      expected,
    ),
    @p2p_game_protocol.verdict_bad_commit(),
  )
}

///|
test "speedhack input is rejected even when its commit matches" {
  let p1_input = @p2p_game_protocol.input_speedhack()
  let p2_input = @p2p_game_protocol.input_stay()
  let expected = @p2p_game_protocol.expected_state_hash(p1_input, p2_input)
  assert_eq(
    @p2p_game_protocol.verify_tick(
      @p2p_game_protocol.make_commit(p1_input),
      p1_input,
      expected,
      @p2p_game_protocol.make_commit(p2_input),
      p2_input,
      expected,
    ),
    @p2p_game_protocol.verdict_invalid_input(),
  )
}

///|
test "state hash equivocation is rejected after valid inputs" {
  let p1_input = @p2p_game_protocol.input_stay()
  let p2_input = @p2p_game_protocol.input_stay()
  let expected = @p2p_game_protocol.expected_state_hash(p1_input, p2_input)
  assert_eq(
    @p2p_game_protocol.verify_tick(
      @p2p_game_protocol.make_commit(p1_input),
      p1_input,
      expected,
      @p2p_game_protocol.make_commit(p2_input),
      p2_input,
      999,
    ),
    @p2p_game_protocol.verdict_hash_mismatch(),
  )
}

///|
test "typed transcript accepts a complete honest tick" {
  let p1_input = @p2p_game_protocol.input_stay()
  let p2_input = @p2p_game_protocol.input_move()
  let expected = @p2p_game_protocol.expected_state_hash(p1_input, p2_input)
  let transcript = @p2p_game_protocol.new_tick()
    .commit_p1(p1_input)
    .commit_p2(p2_input)
    .reveal_p1(p1_input)
    .reveal_p2(p2_input)
    .state_hash_p1(expected)
    .state_hash_p2(expected)
  assert_eq(transcript.verify_transcript(), @p2p_game_protocol.verdict_accept())
}

///|
test "typed transcript detects reveal after a different commit" {
  let committed = @p2p_game_protocol.input_stay()
  let revealed = @p2p_game_protocol.input_move()
  let peer2 = @p2p_game_protocol.input_stay()
  let expected = @p2p_game_protocol.expected_state_hash(revealed, peer2)
  let transcript = @p2p_game_protocol.new_tick()
    .commit_p1(committed)
    .commit_p2(peer2)
    .reveal_p1(revealed)
    .reveal_p2(peer2)
    .state_hash_p1(expected)
    .state_hash_p2(expected)
  assert_eq(
    transcript.verify_transcript(),
    @p2p_game_protocol.verdict_bad_commit(),
  )
}

///|
test "typed transcript rejects incomplete ticks before accept" {
  let p1_input = @p2p_game_protocol.input_stay()
  let p2_input = @p2p_game_protocol.input_move()
  let transcript = @p2p_game_protocol.new_tick()
    .commit_p1(p1_input)
    .commit_p2(p2_input)
    .reveal_p1(p1_input)
    .reveal_p2(p2_input)
  assert_eq(
    transcript.verify_transcript(),
    @p2p_game_protocol.verdict_incomplete(),
  )
}
