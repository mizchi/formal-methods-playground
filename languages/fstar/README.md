# languages/fstar/

F* sample for **verified implementation cores**.

F* is not the cheapest way to hunt for config contradictions or temporal
interleavings. Use it when the code you want to ship should carry the contract:
refinement types, pre/postconditions, and lemmas live next to executable
functions.

## CheckoutForm.fst

`CheckoutForm.fst` mirrors the checkout-form domain used elsewhere in this
repository:

- physical checkout forms need shipping information
- digital checkout forms need a non-empty email
- every valid checkout form needs a positive total

The constructors prove their own postconditions:

```fstar
let make_digital
  (email_len:nat{email_len > 0})
  (amount:int{amount > 0})
  : Tot (f:checkout_form{is_valid f == true /\ f.kind == Digital})
```

Run:

```sh
nix develop -c fstar.exe languages/fstar/CheckoutForm.fst
```

or directly:

```sh
fstar.exe languages/fstar/CheckoutForm.fst
```

Expected result: exit 0, no verification errors.

Breaking variant: remove `{email_len > 0}` from `make_digital`'s first
argument. F* should reject the function because the returned form no longer
proves `is_valid f == true`.

## When this is the right tool

Use F* for:

- parser/serializer round-trip guarantees
- validated loader functions that return only normalized data
- security-sensitive validator cores
- proof-carrying business-rule evaluators
- Low*/HACL*-style high-assurance library code

Do not start here for:

- quick SAT/UNSAT checks over config data
- finite relational counterexample search
- retry/crash/interleaving traces
- domain-owner review artifacts

Those usually start in Z3, Alloy, TLA+, or P, then graduate to F* only if the
implementation itself needs to carry the proof.
