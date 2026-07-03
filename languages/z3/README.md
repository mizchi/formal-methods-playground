# languages/z3/

Direct SMT probes for implementation-extracted predicates.

Japanese walkthrough of the workflow:
[`../real-world-adoption.ja.md`](../real-world-adoption.ja.md#z3-で仕様をモデルに落としてドメインに戻す流れ).

## checkout_form.smt2

Mirrors `languages/moonbit/checkout_form/checkout_form.mbt`'s
`is_valid_checkout` decision function.

Run from the repository root:

```sh
./languages/z3/check_checkout_form.sh
```

Expected output:

```text
unsat
unsat
sat
sat
sat
```

The first two checks lock negative contracts:

- no unknown `kind` can validate
- no digital order with `email_len <= 0` can validate

The final two `sat` checks are the broken-variant test. They show
that if the digital branch forgets the non-empty-email guard, Z3
finds a disagreement with the extracted implementation.
