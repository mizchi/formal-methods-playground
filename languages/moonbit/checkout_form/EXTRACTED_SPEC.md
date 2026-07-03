# Extracted specification ledger: checkout form

Source implementation:

- `checkout_form.mbt`
- public decision function: `is_valid_checkout(kind, has_shipping, email_len, total)`

This file is the playbook ledger for one concrete pass:

1. extract implementation claims
2. refute / prove them mechanically
3. keep the surviving claims as regression contracts

## Declared specification

The implementation comment states the branch-specific product rule:

- every valid order must have a strictly positive total
- physical orders require a shipping address
- digital orders require a non-empty email
- unknown order kinds fail closed

The executable decision function is:

```text
valid =
  if total > 0 then
    if kind == physical_kind then has_shipping
    else if kind == digital_kind then email_len > 0
    else false
  else false
```

## Implicit behavior extracted from code

| Input surface | Observed behavior | Risk class |
| --- | --- | --- |
| `kind` outside `{0, 1}` | rejected | fail-closed boundary |
| `email_len <= 0` for digital | rejected | missing precondition / boundary |
| `has_shipping = false` for digital | allowed | branch-specific field |
| `email_len > 0` for physical | ignored | branch-specific field |
| `total <= 0` | rejected for every kind | global guard |

## Mechanical checks

| Check | Tool | Result | Meaning |
| --- | --- | --- | --- |
| public examples | MoonBit `moon test` | pass | implementation matches public API expectations |
| implementation equality contract | MoonBit `moon prove` | pass | opam Why3 1.7.2 + Alt-Ergo 2.5.4 proves all 5 goals |
| unknown kind can validate | Z3 | `unsat` | fail-closed is locked |
| digital empty-email can validate | Z3 | `unsat` | digital email guard is locked |
| digital boundary `email_len = 1` | Z3 | `sat` | positive case is reachable |
| broken digital branch | Z3 | `sat` | harness catches a missing guard |
| extracted vs broken equivalence | Z3 | `sat` | broken model is observably different |

Run:

```sh
moon test
./languages/z3/check_checkout_form.sh
nix develop -c just prove-moonbit
```

From the package directory, `moon prove` attempts to discharge the
MoonBit proof annotations through Why3 and an SMT solver. Use the
repository-local opam switch to pin the Why3 version MoonBit expects:

```sh
nix develop -c just setup-moonbit-prove-opam
nix develop -c just prove-moonbit
```

Current observed result with MoonBit 0.1.20260629, opam Why3 1.7.2,
and Alt-Ergo 2.5.4:

- MoonBit generates `_build/verif/pkg_6_mizchi_14_checkout_uform.mlw`
- that Why3 file contains the `is_valid_checkout` `ensures` clause
- proof discharge succeeds: 5 goals proved

## Domain questions

1. Is `kind` intentionally an integer wire value, or should it be a
   closed enum at the API boundary?
2. Should `email_len < 0` be impossible by construction, or is
   rejecting it as an invalid digital order sufficient?
3. Should physical orders reject a supplied email, or is the current
   "ignored extra field" behavior intentional?
4. Should digital orders reject a supplied shipping address, or is it
   intentionally allowed?

Until those are answered, the current implementation is treated as
the de-facto specification and locked by tests / Z3 checks.
