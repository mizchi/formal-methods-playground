import assert from "node:assert/strict";
import { pathToFileURL } from "node:url";

const modulePath = process.argv[2];
assert.ok(modulePath, "usage: node scripts/test-lean-wasm-emscripten-runtime.mjs <module.mjs>");

const { default: createModule } = await import(pathToFileURL(modulePath));
const module = await createModule();

const cases = [
  ["Lean", 4],
  ["λ", 2],
  ["こんにちは", 15],
];

for (const [value, expected] of cases) {
  const actual = module.ccall(
    "lean_wasm_utf8_length_utf8",
    "number",
    ["string"],
    [value],
  ) >>> 0;
  assert.equal(actual, expected);
}

console.log(`Emscripten runtime-backed module: ${cases.length} cases passed`);
