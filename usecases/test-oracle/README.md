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

Each directory pins the broken implementation as a test that finds the
disagreement, and the fixed one as a test that finds none.
