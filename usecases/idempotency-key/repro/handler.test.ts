import { test } from "node:test";
import assert from "node:assert/strict";
import { createSystem, callWithRetry } from "./handler.ts";

// Counterexample 1 (IdempotentRetry_late.cfg): the key row is written after the charge.
test("late store: a crash after charging makes the retry charge again", () => {
  const sys = createSystem({ reserveFirst: false, takeoverReserved: true, providerIdempotent: false });
  sys.crashOnce("afterCharge");
  assert.equal(callWithRetry(sys.handle, "k1"), "ok");
  assert.equal(sys.charges, 2); // NoDoubleCharge violated
});

// Counterexample 2 (IdempotentRetry_blocking.cfg): reserve first, 409 while reserved.
test("reserve + 409: a crash after reserving wedges the key forever", () => {
  const sys = createSystem({ reserveFirst: true, takeoverReserved: false, providerIdempotent: false });
  sys.crashOnce("afterReserve");
  assert.equal(callWithRetry(sys.handle, "k1"), "gave up"); // EventuallySettled violated
  assert.equal(sys.charges, 0);
});

// Takeover alone is not enough: without provider-side dedupe, resuming re-charges.
test("reserve + takeover without provider dedupe: resuming charges again", () => {
  const sys = createSystem({ reserveFirst: true, takeoverReserved: true, providerIdempotent: false });
  sys.crashOnce("afterCharge");
  assert.equal(callWithRetry(sys.handle, "k1"), "ok");
  assert.equal(sys.charges, 2);
});

// The design IdempotentRetry.cfg checks: every crash point, one charge, and it settles.
for (const point of ["afterReserve", "afterCharge"] as const) {
  test(`fixed design: crash ${point} -> one charge, settles`, () => {
    const sys = createSystem({ reserveFirst: true, takeoverReserved: true, providerIdempotent: true });
    sys.crashOnce(point);
    assert.equal(callWithRetry(sys.handle, "k1"), "ok");
    assert.equal(sys.charges, 1);
  });
}
