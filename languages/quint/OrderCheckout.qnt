// Probe: the same async order-checkout state machine as
// languages/tla/OrderCheckout.tla, expressed in Quint.
//
// Checks:
//   typeOk              - the cart only contains declared items
//   refundedOnlyInRefundedState - the refunded flag is only set in Refunded
//   paymentResolves     - weak fairness prevents PaymentPending forever
//   paymentResolvesWithoutFairness - negative liveness control; must fail
//
// Run from the repository root:
//   just check-quint
//
// Expected: type checking and the safety/liveness verification succeed.
// The check script also selects brokenStep, where cancelling a cart sets the
// refunded flag. That variant must fail refundedOnlyInRefundedState with a trace.
module OrderCheckout {
  type OrderState =
    | Cart
    | PaymentPending
    | Paid
    | Shipped
    | Refunded
    | Cancelled

  pure val items = Set("i1", "i2")

  var state: OrderState
  var cart: Set[str]
  var refunded: bool

  action init = all {
    state' = Cart,
    cart' = Set(),
    refunded' = false,
  }

  action addItem(candidate: str): bool = all {
    state == Cart,
    candidate.in(items),
    not(candidate.in(cart)),
    state' = state,
    cart' = cart.union(Set(candidate)),
    refunded' = refunded,
  }

  action checkout = all {
    state == Cart,
    cart != Set(),
    state' = PaymentPending,
    cart' = cart,
    refunded' = refunded,
  }

  action paymentSucceeded = all {
    state == PaymentPending,
    state' = Paid,
    cart' = cart,
    refunded' = refunded,
  }

  action paymentFailed = all {
    state == PaymentPending,
    state' = Cart,
    cart' = cart,
    refunded' = refunded,
  }

  action paymentTimeout = all {
    state == PaymentPending,
    state' = Cancelled,
    cart' = cart,
    refunded' = refunded,
  }

  action ship = all {
    state == Paid,
    state' = Shipped,
    cart' = cart,
    refunded' = refunded,
  }

  action refund = all {
    state.in(Set(Paid, Shipped)),
    state' = Refunded,
    cart' = cart,
    refunded' = true,
  }

  action cancelCart = all {
    state == Cart,
    state' = Cancelled,
    cart' = cart,
    refunded' = refunded,
  }

  action step = {
    nondet candidate = items.oneOf()
    any {
      addItem(candidate),
      checkout,
      paymentSucceeded,
      paymentFailed,
      paymentTimeout,
      ship,
      refund,
      cancelCart,
    }
  }

  // Deterministic scenario used by implementation adapters. `quint run --mbt`
  // covers randomized traces; this run checks the named-test command path.
  run cancelTest = init.then(cancelCart)

  val typeOk = cart.forall(candidate => candidate.in(items))

  val refundedOnlyInRefundedState = refunded implies state == Refunded

  val vars = (state, cart, refunded)

  temporal paymentResolves =
    and {
      paymentSucceeded.weakFair(vars),
      paymentFailed.weakFair(vars),
      paymentTimeout.weakFair(vars),
    }
      implies (state == PaymentPending leadsTo state.in(Set(Paid, Cart, Cancelled)))

  // Negative control: without a fairness assumption, TLC may choose an
  // infinite stuttering execution in PaymentPending. This must fail.
  temporal paymentResolvesWithoutFairness =
    state == PaymentPending leadsTo state.in(Set(Paid, Cart, Cancelled))

  // Negative control: this action is excluded from step. Selecting brokenStep
  // in the checker proves that refundedOnlyInRefundedState is still load-bearing.
  action brokenCancelCart = all {
    state == Cart,
    state' = Cancelled,
    cart' = cart,
    refunded' = true,
  }

  action brokenStep = any {
    step,
    brokenCancelCart,
  }
}
