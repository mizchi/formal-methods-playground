// Probe: application-level form validation + total computation.
//
// Models the kind of conditional invariant a real checkout form
// carries: "digital orders need an email; physical orders need
// a shipping address; the total must be strictly positive."
//
// Dafny's sweet spot: the predicate is a single readable
// expression, the constructors prove they produce valid forms,
// the loop has invariants the SMT discharges automatically.
//
// Run from this directory inside the formal-methods-playground nix devShell:
//
//   dafny verify checkout_form.dfy
//
// Expect:
//   "Dafny program verifier finished with 4 verified, 0 errors"
//
// To watch the verifier catch a bug, drop the
// `requires |email| > 0` line from MakeDigitalForm. Dafny then
// fails the `ensures IsValidForm(f)` postcondition with a
// concrete counter-example (email = "" violates the digital
// branch of IsValidForm).

datatype Option<T> = None | Some(value: T)

datatype Kind = Physical | Digital

datatype Address = Address(street: string, city: string, zip: string)

datatype Form = Form(
  kind: Kind,
  shipping: Option<Address>,
  email: Option<string>,
  total: int)

// The conditional invariant. Reads top-down:
//   - total is strictly positive
//   - physical forms need a shipping address
//   - digital forms need a non-empty email
predicate IsValidForm(f: Form)
{
  && f.total > 0
  && (match f.kind
        case Physical => f.shipping.Some?
        case Digital  => f.email.Some? && |f.email.value| > 0)
}

// Constructor: physical-kind form. Pre-conditions are just the
// data each branch needs.
method MakePhysicalForm(addr: Address, total: int) returns (f: Form)
  requires total > 0
  ensures IsValidForm(f)
  ensures f.kind == Physical
{
  f := Form(Physical, Some(addr), None, total);
}

// Constructor: digital-kind form. Drop `|email| > 0` to see Dafny
// reject the post-condition.
method MakeDigitalForm(email: string, total: int) returns (f: Form)
  requires total > 0
  requires |email| > 0
  ensures IsValidForm(f)
  ensures f.kind == Digital
{
  f := Form(Digital, None, Some(email), total);
}

// Order-total computation: sum a non-empty sequence of positive
// prices. The loop invariant chain `0 <= i <= |prices|` plus
// `i > 0 ==> total > 0` is enough for SMT to discharge the
// post-condition `total > 0`.
method SumPrices(prices: seq<int>) returns (total: int)
  requires |prices| > 0
  requires forall i :: 0 <= i < |prices| ==> prices[i] > 0
  ensures total > 0
{
  total := 0;
  var i := 0;
  while i < |prices|
    invariant 0 <= i <= |prices|
    invariant total >= 0
    invariant i > 0 ==> total > 0
  {
    total := total + prices[i];
    i := i + 1;
  }
}

// Top-level "assemble + validate" usage: build a digital form
// from a price list. The result is verified IsValidForm by
// construction.
method AssembleDigitalCheckout(email: string, prices: seq<int>) returns (f: Form)
  requires |email| > 0
  requires |prices| > 0
  requires forall i :: 0 <= i < |prices| ==> prices[i] > 0
  ensures IsValidForm(f)
  ensures f.kind == Digital
{
  var total := SumPrices(prices);
  f := MakeDigitalForm(email, total);
}
