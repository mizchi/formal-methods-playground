# mizchi/p2p_game_protocol

Executable MoonBit version of the P2P game transcript verifier modeled in
`languages/tla/P2PGameProtocol.tla`.

This package demonstrates the "formal model -> executable protocol" path:

1. TLA+ checks every modeled commit/reveal/hash ordering.
2. `verify_tick` keeps the proof-friendly verdict function small.
3. `TickTranscript` exposes the application-facing protocol API.
4. `moon prove` checks that the implementation follows the proof-only specs.

Example:

```moonbit
let p1_input = input_stay()
let p2_input = input_move()
let expected = expected_state_hash(p1_input, p2_input)
let transcript = new_tick()
  .commit_p1(p1_input)
  .commit_p2(p2_input)
  .reveal_p1(p1_input)
  .reveal_p2(p2_input)
  .state_hash_p1(expected)
  .state_hash_p2(expected)

assert_eq(transcript.verify_transcript(), verdict_accept())
```
