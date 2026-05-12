# moonbit/

Probes for MoonBit's `moon prove` formal verification.

MoonBit ships a verification feature that translates code +
`where { proof_* : ... }` annotations into Why3 (`.mlw`) source,
then dispatches proof obligations to Z3 / CVC5 / Alt-Ergo. Same
auto-discharge model as Dafny, but the IR layer (Why3) is
visible and the SMT solver is explicitly named.

## Setup

The toolchain is not in nixpkgs. The host install lives at
`~/.moon/bin/` and the devShell prepends it to `PATH` via
`shellHook` so `moon` resolves inside `nix develop` too.

```sh
# one-time host install (from MoonBit's official installer)
curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
```

The Why3 + SMT solvers needed for actual verification come from
`flake.nix`'s devShell — no separate install.

## Per-package activation

Verification is **opt-in per package**. Add this to the package's
`moon.pkg`:

```
options(
  "proof-enabled": true,
)
```

Without that flag, `moon prove` silently exits 0 — it does NOT
flag the absence of activation as an error. This is the single
biggest gotcha when starting out.

## Run

```sh
cd moonbit/checkout_form
moon prove
```

## Probes

| Dir | Topic |
| --- | --- |
| [`checkout_form/`](checkout_form/) | `max_of_two` + `safe_abs` with `proof_ensure` post-conditions |

## Toolchain caveat (v0.1.20260427 + Why3 1.8.2 + nixpkgs unstable)

On the version combination above, `moon prove` aborts with

> anomaly: Failure("why3_harness: no configured provers are available")

The root cause is a Why3 ↔ SMT solver generation mismatch:

| Prover | nixpkgs version | Why3 1.8.2 knows |
| --- | --- | --- |
| Z3 | 4.16.0 | up to 4.13.x |
| CVC5 | 1.3.3 | up to 1.2.x |
| Alt-Ergo | 2.6.3 | up to 2.5.x |

Why3 1.8.2's prover-version regex table does not match the binaries
nix ships. `why3 config detect` reports them as "version not
recognized," so MoonBit's `moon prove` harness (which only loads
provers Why3 accepts as fully-validated) drops them all and
errors with "no configured provers are available."

**What works:**
- MoonBit → Why3 translation. `_build/verif/<pkg>.mlw` contains
  clean Why3 source for both functions. The `where { proof_* }`
  block is faithfully translated to `requires { ... }` /
  `ensures { ... }` clauses, the function body to a Why3
  `let ... = if ... then ... else ...`.
- MoonBit's type-check + build (`moon check`, `moon build`).
- The Why3 config file (`_build/verif/why3.conf`) is generated
  correctly with all three SMT solver paths.

**What's blocked:**
- Actual proof discharge against the SMT solver.

**Workarounds (not adopted in this repo yet):**
1. Pin older SMT-solver derivations via `nixpkgs#z3_4_8` /
   equivalent, matching what Why3 1.8.2 recognises.
2. Patch Why3's prover detection regex to accept the new
   versions. Possible but fragile across Why3 minor bumps.
3. Wait for Why3 1.9+ in nixpkgs unstable (the recognised
   version table is updated each release).

The honest picking conclusion: **MoonBit's verification pipeline
is structurally complete but operationally dependent on a tight
Why3 ↔ SMT-solver version window**. Dafny ships its SMT bundle
inline (Z3 baked into the dafny binary), eliminating this class
of problem. For one-off experiments today, Dafny is friction-free
where MoonBit's prove pipeline needs ~30 minutes of nixpkgs
pinning per host.
