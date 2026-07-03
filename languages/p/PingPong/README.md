# p/PingPong/

P-language probe of a two-actor ping-pong protocol with a safety
monitor. Sister probe to `languages/tla/ActorMailbox.tla` — same domain
(message-passing actors with FIFO inboxes) re-expressed in a tool
where actors are language primitives.

## Layout

```
PingPong/
├── PingPong.pproj          project file (input list + output dir)
├── PSrc/Actors.p           Sender + Receiver machines
├── PSpec/PingPongBalance.p safety monitor: ePong always preceded by ePing
└── PTst/TestScript.p       module declarations + test case
```

## Run

```sh
cd languages/p/PingPong
nix develop ../../..  # or run from any subdir of formal-methods-playground

p compile               # → ./PGenerated/PingPongProbe.dll
p check                 # default: random strategy, 1 schedule
p check --schedules 1000  # exhaustive-ish exploration
```

Verified result:

```
... Explored 1000 schedules
... Found 0 bugs.
```

## How to bait a bug

To watch the spec catch a violation, edit `PSrc/Actors.p`:

```p
machine Receiver {
  start state Listening {
    on ePing do (sender: machine) {
      send sender, ePong;
      send sender, ePong;   // <-- intentional double-reply
    }
  }
}
```

Re-run `p check`. The `PingPongBalance` spec fires on the second
ePong (pendingPings already 0) and the checker prints the exact
bug trace: the schedule, the machine events, and the failing
assertion location.

## P-language specifics that bit

1. **`sent` is a reserved keyword** for the `PVerifier` backend.
   Using it as a variable name produces a `NotSupportedError` at
   compile time, not a parse error. Renamed to `roundTrips`.
2. **`test` syntax requires modules, not bare machine names** —
   `assert Spec in (union Sender, Receiver, ...)` doesn't parse
   even though tutorials sometimes elide the `module = { ... };`
   declarations. Explicit modules `module Senders = { Sender };`
   are needed; then `union Senders, ...` works.
3. **Set literals use bare braces in `union`**: `{ TestPingPong }`
   is a one-element machine set, syntactically distinct from a
   module name.

## What P adds over the TLA+ ActorMailbox

| Concern | TLA+ ActorMailbox.tla | P PingPong |
| --- | --- | --- |
| Actor + message as primitives | manual via Seq + records | language built-in |
| Mailbox semantics | hand-modelled (Send appends, Receive pops Head) | runtime managed |
| Spec invariant | TLA+ formula | monitor machine with assert |
| Scheduler control | TLC's BFS, all interleavings within scope | configurable strategies (random / PCT / probabilistic) |
| Output on failure | numbered state sequence | bug-trace with schedule + event log |
| Generates impl code | no | yes — `--mode=codegen` emits C# / Java |

P's compelling pitch is the last row: spec and implementation
share one source. The same .p file the checker analyses gets
turned into the running production code. TLA+ doesn't offer that
(spec / impl are independently maintained).

The cost is toolchain weight: P needs .NET SDK + a per-user
`dotnet tool install` + `DOTNET_ROOT` plumbing. Once set up
inside the nix devShell here, it's transparent — but the path
from "fresh machine" to "p check works" was meaningfully longer
than for TLA+, which is a single `tlaplus` package.
