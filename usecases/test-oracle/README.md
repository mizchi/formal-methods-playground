# test-oracle/

Pattern: use a formal model as the test oracle for an existing implementation.
The model does not replace the tests; it decides what the right answer is, and
the implementation's own test suite asks it.

| Directory | Oracle | Implementation under test | How they meet |
| --- | --- | --- | --- |
| [`z3-node/`](z3-node/) | Z3 (the `z3-solver` npm package) | a TypeScript dependency resolver | random problems; the resolver's "impossible" must agree with Z3's `unsat` |
| [`tla-trace/`](tla-trace/) | TLC counterexamples for `IdempotentRetry` | `idempotency-key/repro/handler.ts` | the TLC trace is parsed into a crash point and an expected final state, then replayed |
| [`lean-rust/`](lean-rust/) | the proven Lean `midSafe`, compiled through C to an executable | a Rust midpoint function | 10,004 input pairs piped through both; outputs must match |

```sh
cd usecases/test-oracle/z3-node && pnpm install && node --test resolver.test.ts
cd usecases/test-oracle/tla-trace && node --test replay.test.ts   # ./gen.sh (inside nix develop) re-runs TLC
cd usecases/test-oracle/lean-rust && ./build.sh                   # needs lean, leanc and cargo on PATH
```

`z3-node/` and `lean-rust/` pin the broken implementation as a test that
finds the disagreement, and the fixed one as a test that finds none.
`tla-trace/` replays only the two broken designs: the correct design has no
counterexample trace to replay.

## Domain ledger

One ledger per sub-example.

### z3-node

| field | value |
| --- | --- |
| source | `z3-node/resolver.ts` (a TypeScript dependency resolver) and `z3-node/oracle.ts` (Z3 via `z3-solver`) |
| expected claim | the resolver answers "impossible" only when no install set satisfies the requires and conflicts |
| implementation observation | `resolveGreedy` takes the first candidate of each group and never backtracks; `resolveBacktrack` backtracks |
| model question | is each of 200 seeded random problems satisfiable, and does the resolver agree? |
| tool | Z3 |
| machine result | greedy: a mismatch within 200 problems / backtrack: agrees on all 200 |
| witness | printed by the test: root needs e or d, d needs e or a, e needs c or b, c and a both conflict with e; greedy picks e and gives up, Z3 installs `root, a, d` |
| reproduction | reproduced: `resolver.test.ts` pins greedy as disagreeing and backtrack as agreeing |
| domain wording | The greedy resolver tells a user that a solvable dependency set cannot be installed. |
| domain question | none stated; the oracle decides the right answer |
| decision | bug; `resolveBacktrack` is the checked variant |
| lock | `cd usecases/test-oracle/z3-node && pnpm install && node --test resolver.test.ts` |

### tla-trace

| field | value |
| --- | --- |
| source | TLC counterexamples `tla-trace/late.out` and `tla-trace/blocking.out`, and `idempotency-key/repro/handler.ts` |
| expected claim | the handler ends in the TLC counterexample's final state for the same design constants and crash point |
| implementation observation | `trace.ts` parses each trace and cfg into a design, a crash point, the final `charges`, and whether it settles |
| model question | does the implementation, replaying the trace, end where TLC's trace ends? |
| tool | TLA+ (TLC), replayed with `node:test` |
| machine result | `late`: `NoDoubleCharge` violated, `charges = 2` / `blocking`: temporal property violated, stuttering at `rec = "reserved"` |
| witness | see `idempotency-key/` "The trace to show a reviewer" |
| reproduction | reproduced: `replay.test.ts` replays both; `late` ends with `charges = 2`, `blocking` never settles |
| domain wording | see `idempotency-key/`: a crash between the charge and the key row double-charges; a crash after reserving wedges the key |
| domain question | see `idempotency-key/` |
| decision | bug (demo); see `idempotency-key/` |
| lock | `cd usecases/test-oracle/tla-trace && node --test replay.test.ts`; `./gen.sh` re-runs TLC |

### lean-rust

| field | value |
| --- | --- |
| source | `lean-rust/lean/MidOracle.lean` (`midSafe`, proven equal to `midSpec`) and `lean-rust/midpoint/src/lib.rs` |
| expected claim | the Rust midpoint equals `(lo + hi) / 2` computed without overflow, for every `lo <= hi` in `u64` |
| implementation observation | `mid_naive` computes `lo.wrapping_add(hi) / 2`; `mid_safe` computes `lo + (hi - lo) / 2` |
| model question | theorem `midSafe_correct`: `midSafe lo hi = midSpec lo hi` when `lo <= hi`; then the compiled oracle vs. Rust on 10,004 input pairs |
| tool | Lean 4 (`bv_decide`), compiled through C |
| machine result | `midSafe_correct` proved / `mid_naive` disagrees / `mid_safe` agrees on all 10,004 pairs |
| witness | printed by the test: `lo = hi = u64::MAX`, where `mid_naive` returns `2^63 - 1` and Lean returns `u64::MAX` |
| reproduction | reproduced: `midpoint/tests/against_lean.rs` pins the naive version as disagreeing and the safe one as agreeing |
| domain wording | A binary search whose bounds are near `u64::MAX` computes the wrong midpoint with the naive formula. |
| domain question | none stated; the proof decides the right answer |
| decision | bug; `mid_safe` is the checked variant |
| lock | `cd usecases/test-oracle/lean-rust && ./build.sh` |
