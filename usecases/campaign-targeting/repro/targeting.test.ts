import { test } from "node:test";
import assert from "node:assert/strict";
import { matches } from "./targeting.ts";
import type { Config } from "./targeting.ts";

// The config as shipped.
const live: Config = {
  campaign: "SummerPromo",
  include: { country: ["JP"], age: { gte: 30, lt: 30 } },
  exclude: { country: ["JP"] },
  allowlist: [],
};

// The config the docs describe.
const documented: Config = {
  campaign: "SummerPromo",
  include: { country: ["JP"], age: { gte: 20, lt: 30 } },
  allowlist: [],
};

// Z3 check 4 witness: country = JP, age = 20, not denylisted.
const witness = { id: "u1", country: "JP", age: 20 };

test("dead config: the live config does not target the documented audience", () => {
  assert.equal(matches(witness, live), false);
});

test("each defect alone kills the config", () => {
  const ageOnly = { ...documented, include: { ...documented.include, age: { gte: 30, lt: 30 } } };
  const excludeOnly = { ...documented, exclude: { country: ["JP"] } };
  assert.equal(matches(witness, ageOnly), false);
  assert.equal(matches(witness, excludeOnly), false);
});

test("sanity: the documented config targets the witness", () => {
  assert.equal(matches(witness, documented), true);
});

test("denylisted users never match", () => {
  assert.equal(matches(witness, documented, new Set(["u1"])), false);
});

test("fail-close holds for the documented rule, because include.country requires JP", () => {
  for (const country of [undefined, "", "jp", "ZZ"]) {
    assert.equal(matches({ ...witness, country }, documented), false, String(country));
  }
});

test("observation, not a decision: empty allowlist is read as no restriction", () => {
  // Pinned so that changing the reading shows up as a failing test and a
  // domain decision, not as a silent behaviour change.
  assert.equal(matches(witness, { ...documented, allowlist: [] }), true);
  assert.equal(matches(witness, { ...documented, allowlist: ["u2"] }), false);
});

test("finding: an exclude-only rule lets a malformed country through (fail-open)", () => {
  // Z3 check 9. include.country is what made the earlier fail-close test pass;
  // without it, a malformed country is in no list and survives the exclude.
  const exceptJP: Config = { campaign: "NotJP", exclude: { country: ["JP"] }, allowlist: [] };
  assert.equal(matches({ id: "u3", country: "ZZ", age: 40 }, exceptJP), true);
});
