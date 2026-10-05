import { test } from "node:test";
import assert from "node:assert/strict";
import * as m from "./orders.ts";

// The records are Z3's witnesses from schema_evolution.smt2.
const v1Record: m.Order = { id: "o1", status: "pending" }; // check 1: status=0, no currency
const v2Record: m.Order = { id: "o2", status: "refunded", currency: "JPY" }; // check 2/5: status=3

test("1. strict v2 reader rejects an old record without currency", () => {
  assert.throws(() => m.v2ReadStrict(v1Record), m.Rejected);
});

test("2. strict v1 reader rejects a new record with status=refunded", () => {
  assert.throws(() => m.v1ReadStrict(v2Record), m.Rejected);
});

test("3. tolerant v2 reader accepts the old record", () => {
  assert.equal(m.v2ReadTolerant(v1Record).currency, "JPY");
});

test("4. tolerant v1 readers accept the new record", () => {
  assert.doesNotThrow(() => m.v1ReadFallbackPending(v2Record));
  assert.doesNotThrow(() => m.v1ReadFallbackHold(v2Record));
});

test("5. fail-open fallback: v1 parses a refunded order and captures it again", () => {
  const captured: string[] = [];
  m.v1Process(m.v1ReadFallbackPending(v2Record), (id) => captured.push(id));
  assert.deepEqual(captured, ["o2"]);
});

test("6. fail-closed fallback: v1 parses a refunded order and does nothing", () => {
  const captured: string[] = [];
  m.v1Process(m.v1ReadFallbackHold(v2Record), (id) => captured.push(id));
  assert.deepEqual(captured, []);
});
