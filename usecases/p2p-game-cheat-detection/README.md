# P2P game cheat-detection transcript protocol

This use case models a minimal peer-to-peer online game tick protocol.

The goal is not to prove that a client is honest. In P2P games, clients control
their own runtime. The goal is narrower and more useful:

```text
Every accepted tick has a replayable transcript:
  commit -> reveal -> deterministic state hash.

If a peer reveals a different input, sends an invalid input, or signs a wrong
state hash, the tick is disputed with evidence instead of accepted.
```

## Protocol

For each game tick:

1. Each peer sends a commitment to its input.
2. After all commitments are present, peers reveal their input.
3. Each peer verifies that `commit == CommitOf(revealedInput)`.
4. Each peer validates the input against the game rule validator.
5. Each peer computes the deterministic state hash from the revealed input log.
6. Peers exchange signed state hashes.
7. The tick is accepted only if every peer sent the expected state hash.
8. Otherwise, the tick enters dispute with evidence.

The toy implementation uses small integer/string encodings instead of real
cryptographic hashes and signatures. A production version must replace these
with:

- per-player signing keys
- cryptographic commitments such as `H(input, nonce)`
- signed state hashes
- replayable input logs
- a dispute packet containing the minimal divergent tick

## Formal model

TLA+:

- [`languages/tla/P2PGameProtocol.tla`](../../languages/tla/P2PGameProtocol.tla)
- [`languages/tla/P2PGameProtocol.cfg`](../../languages/tla/P2PGameProtocol.cfg)

Checked properties:

| Property | Meaning |
| --- | --- |
| `NoBadCommitAccepted` | reveal-after-commit mismatch cannot be accepted |
| `NoInvalidInputAccepted` | speedhack / invalid action cannot be accepted |
| `AcceptedHashesAgree` | accepted tick has deterministic state-hash agreement |
| `DisputeHasEvidence` | a disputed tick is never evidence-free |
| `EvidenceIsSound` | evidence labels correspond to a real transcript fault |
| `Complete*Resolves` | once a phase has complete inputs, fairness resolves it |

Run:

```sh
nix develop -c tlc -config P2PGameProtocol.cfg P2PGameProtocol.tla
nix develop -c just check-tla
```

Observed result:

```text
Model checking completed. No error has been found.
717 states generated, 521 distinct states found.
```

## Executable protocol

MoonBit:

- [`languages/moonbit/p2p_game_protocol/p2p_game_protocol.mbt`](../../languages/moonbit/p2p_game_protocol/p2p_game_protocol.mbt)
- [`languages/moonbit/p2p_game_protocol/p2p_game_protocol_test.mbt`](../../languages/moonbit/p2p_game_protocol/p2p_game_protocol_test.mbt)

The executable verifier returns one of four verdicts:

| Verdict | Meaning |
| --- | --- |
| `verdict_accept` | transcript is accepted |
| `verdict_bad_commit` | revealed input does not match commitment |
| `verdict_invalid_input` | input is not valid under game rules |
| `verdict_hash_mismatch` | peer state hash does not match deterministic replay |

Run:

```sh
nix develop -c just test-moonbit
nix develop -c just prove-moonbit
```

The MoonBit proof layer checks that `verify_tick` is exactly the executable
version of the proof-only `tick_spec`; tests cover honest accept, commit/reveal
mismatch, speedhack input, and state-hash equivocation.

## Domain ledger

```text
source:
  P2P game tick protocol sketch.

expected claim:
  A tick is accepted only when every peer can replay the same transcript:
  commit -> reveal -> deterministic state hash.

model question:
  Across every commit/reveal/hash ordering in the finite model, can a bad
  commit, invalid input, or wrong state hash still reach accepted?

tool:
  TLA+ / TLC for protocol states and interleavings.
  MoonBit prove for the executable verifier contract.

machine result:
  TLC found no invariant or liveness violation in the modeled scope.
  MoonBit prove discharged the `verify_tick == tick_spec` obligations.

domain wording:
  A peer cannot get a tick accepted by revealing a different input than it
  committed to, by revealing a speedhack input, or by reporting a state hash
  that does not match deterministic replay.

domain question:
  Are these four verdicts enough for product behavior, or does dispute handling
  need more detailed reasons such as "late reveal" and "missing hash"?

lock:
  `nix develop -c just check-tla`
  `nix develop -c just test-moonbit`
  `nix develop -c just prove-moonbit`
```

## What this catches

- 後出し入力:
  commit と reveal が一致しない。
- speed hack / impossible action:
  reveal は commit と一致するが input validator が拒否する。
- state equivocation:
  入力は valid だが、peer が deterministic replay と違う state hash を送る。
- false evidence:
  TLA+ の `EvidenceIsSound` が、証拠ラベルだけが先に立つ状態を拒否する。

## What this does not catch

- aimbot
- wallhack
- human-vs-bot classification
- probabilistic latency abuse
- client-side memory tampering before the input is committed

Those require telemetry, statistical detection, trusted execution, or a server
authority. Formal methods still help around the boundary: the final ban/dispute
decision should reference a deterministic transcript rule rather than a vague
"suspicious" label.
