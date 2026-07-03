module CheckoutForm

(*
  Probe: F* as a verified-implementation language.

  This mirrors the checkout-form shape used by the Dafny and Z3 probes,
  but the point is different:

  - Z3 asks "does this predicate have a counterexample?"
  - Dafny/MoonBit prove ask "does this implementation meet its contract?"
  - F* lets the executable constructors carry refinement contracts directly.

  Run from the repository root inside the nix devShell:

    fstar.exe fstar/CheckoutForm.fst

  Expect: exit 0, no verification errors.

  Breaking variant:
    Remove `{email_len > 0}` from `make_digital`'s first argument.
    F* should reject the function because the returned form no longer proves
    `is_valid f == true`.
*)

type order_kind =
  | Physical
  | Digital

type checkout_form = {
  kind: order_kind;
  has_shipping: bool;
  email_len: nat;
  amount: int
}

let is_valid (f:checkout_form) : Tot bool =
  f.amount > 0 &&
  (match f.kind with
   | Physical -> f.has_shipping
   | Digital -> f.email_len > 0)

let make_physical
  (amount:int{amount > 0})
  : Tot (f:checkout_form{is_valid f == true /\ f.kind == Physical})
  =
  {
    kind = Physical;
    has_shipping = true;
    email_len = 0;
    amount = amount
  }

let make_digital
  (email_len:nat{email_len > 0})
  (amount:int{amount > 0})
  : Tot (f:checkout_form{is_valid f == true /\ f.kind == Digital})
  =
  {
    kind = Digital;
    has_shipping = false;
    email_len = email_len;
    amount = amount
  }

let digital_without_email (amount:int) : Tot checkout_form =
  {
    kind = Digital;
    has_shipping = false;
    email_len = 0;
    amount = amount
  }

let physical_without_shipping (amount:int) : Tot checkout_form =
  {
    kind = Physical;
    has_shipping = false;
    email_len = 0;
    amount = amount
  }

let digital_without_email_is_invalid (amount:int)
  : Lemma (is_valid (digital_without_email amount) == false)
  =
  ()

let physical_without_shipping_is_invalid (amount:int)
  : Lemma (is_valid (physical_without_shipping amount) == false)
  =
  ()

let zero_total_digital
  (email_len:nat{email_len > 0})
  : Tot checkout_form
  =
  {
    kind = Digital;
    has_shipping = false;
    email_len = email_len;
    amount = 0
  }

let zero_total_is_invalid (email_len:nat{email_len > 0})
  : Lemma (is_valid (zero_total_digital email_len) == false)
  =
  ()
