import assert from "node:assert/strict";
import { pathToFileURL } from "node:url";

const modulePath = process.argv[2];
assert.ok(modulePath, "usage: node scripts/test-lean-wasm-emscripten.mjs <module.mjs>");

const { default: createModule } = await import(pathToFileURL(modulePath));
const module = await createModule();

assert.equal(module._lean_wasm_add(20, 22) >>> 0, 42);
assert.equal(module._lean_wasm_add(0xffff_ffff, 1) >>> 0, 0);

console.log("Emscripten scalar module: 2 cases passed");
