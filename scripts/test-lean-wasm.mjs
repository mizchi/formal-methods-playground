import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const wasmPath = process.argv[2];
assert.ok(wasmPath, "usage: node scripts/test-lean-wasm.mjs <module.wasm>");

const bytes = await readFile(wasmPath);
const { instance } = await WebAssembly.instantiate(bytes);
const add = instance.exports.lean_wasm_add;

assert.equal(typeof add, "function", "lean_wasm_add must be exported");

const cases = [
  [20, 22, 42],
  [0, 7, 7],
  [0xffff_ffff, 1, 0],
];

for (const [left, right, expected] of cases) {
  // JavaScript exposes WebAssembly i32 results as signed numbers. Convert the
  // result back to UInt32 before comparing it with Lean's UInt32 semantics.
  assert.equal(add(left, right) >>> 0, expected);
}

console.log(`lean_wasm_add: ${cases.length} cases passed`);
