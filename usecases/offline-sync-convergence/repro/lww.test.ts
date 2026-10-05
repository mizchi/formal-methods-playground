import { test } from "node:test";
import assert from "node:assert/strict";
import { mergeNaive, mergeWithTiebreak, replay, monotonicClock, type Update } from "./lww.ts";

// NaiveTieDiverges: two phones edit the same note in the same millisecond.
const a: Update = { value: "from phone A", time: 1000, replica: "A" };
const b: Update = { value: "from phone B", time: 1000, replica: "B" };

test("naive merge: same updates, different arrival order, different state", () => {
  assert.equal(replay(mergeNaive, [a, b]), "from phone A");
  assert.equal(replay(mergeNaive, [b, a]), "from phone B"); // diverged forever
});

test("tiebreak on replica id: both orders converge", () => {
  assert.equal(replay(mergeWithTiebreak, [a, b]), replay(mergeWithTiebreak, [b, a]));
});

// RepeatedStampBreaksTiebreak: one phone stamps two edits with the same Date.now().
const a1: Update = { value: "A first edit", time: 2000, replica: "A" };
const a2: Update = { value: "A second edit", time: 2000, replica: "A" };

test("tiebreak alone: a repeated stamp from one replica diverges again", () => {
  assert.notEqual(replay(mergeWithTiebreak, [a1, a2]), replay(mergeWithTiebreak, [a2, a1]));
});

test("monotonic clock: stamps from one replica never repeat", () => {
  const tick = monotonicClock(() => 2000); // a wall clock stuck on one millisecond
  const s1 = tick(), s2 = tick();
  assert.ok(s2 > s1);
  const u1: Update = { value: "A first edit", time: s1, replica: "A" };
  const u2: Update = { value: "A second edit", time: s2, replica: "A" };
  assert.equal(replay(mergeWithTiebreak, [u1, u2]), replay(mergeWithTiebreak, [u2, u1]));
});
