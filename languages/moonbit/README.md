# languages/moonbit/

Probes for MoonBit's `moon prove` formal verification.

MoonBit ships a verification feature that translates code +
`where { proof_* : ... }` annotations into Why3 (`.mlw`) source,
then dispatches proof obligations to Z3 / CVC5 / Alt-Ergo. Same
auto-discharge model as Dafny, but the IR layer (Why3) is
visible and the SMT solver is explicitly named.

For a broader inventory of what `moon prove` can and cannot do,
see [`MOON_PROVE_CAPABILITIES.md`](MOON_PROVE_CAPABILITIES.md).

## Setup

The toolchain is not in nixpkgs. The host install lives at
`~/.moon/bin/` and the devShell prepends it to `PATH` via
`shellHook` so `moon` resolves inside `nix develop` too.

```sh
# one-time host install (from MoonBit's official installer)
curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
```

The reproducible proof path uses Nix for `opam`, then a local opam
switch for the MoonBit-recommended Why3 version:

```sh
nix develop -c just setup-moonbit-prove-opam
```

This creates `.opam-root/` in the repository and installs:

- Why3 1.7.2
- Alt-Ergo 2.5.4

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
nix develop -c just prove-moonbit
```

Full local check, including MoonBit tests, Z3 SMT checks, and
`moon prove`:

```sh
nix develop -c just check-with-prove
```

## Probes

| Dir | Topic |
| --- | --- |
| [`checkout_form/`](checkout_form/) | `max_of_two`, `safe_abs`, and an implementation-extracted checkout validator with `proof_ensure` post-conditions |

The checkout validator is intentionally mirrored in
[`../languages/z3/checkout_form.smt2`](../languages/z3/checkout_form.smt2). The MoonBit
code is the executable implementation; the Z3 file asks direct
"does a counter-example exist?" questions over the same predicate.

## Toolchain caveat (v0.1.20260629 + Why3 1.8.2 + nixpkgs unstable)

Without the devShell, `moon prove` aborts early with:

> failed to locate `why3` required by `moon prove`

Inside the devShell, the version combination above gets further
and then aborts with:

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

**What works with the opam path:**
- `nix develop -c just prove-moonbit` uses opam Why3 1.7.2 and
  Alt-Ergo 2.5.4.
- `moon prove` succeeds for `checkout_form`: 5 goals proved.

**What still works with nixpkgs Why3 but is not enough:**
- MoonBit → Why3 translation. `_build/verif/<pkg>.mlw` contains
  clean Why3 source for the annotated functions. The `where { proof_* }`
  block is faithfully translated to `requires { ... }` /
  `ensures { ... }` clauses, the function body to a Why3
  `let ... = if ... then ... else ...`.
- MoonBit's type-check + build (`moon check`, `moon build`).
- MoonBit tests (`moon test`) for executable examples.
- The Why3 config file (`_build/verif/why3.conf`) is generated
  correctly with all three SMT solver paths.

**Workaround adopted here:**
Use Nix for `opam`, then use opam to pin Why3 1.7.2 and Alt-Ergo
2.5.4 in a repository-local switch. This matches MoonBit's
documented recommendation while keeping the global opam state out
of the repo workflow.

The honest picking conclusion: **MoonBit's verification pipeline
is structurally complete but operationally dependent on a tight
Why3 ↔ SMT-solver version window**. The opam path makes that
window explicit and reproducible.
