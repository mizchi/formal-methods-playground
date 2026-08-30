#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
repo_root="$(dirname -- "$script_dir")"
source_file="$repo_root/languages/lean/wasm/LeanWasmRuntime.lean"
bridge_file="$repo_root/languages/lean/wasm/lean_wasm_runtime_bridge.c"
build_dir="$repo_root/build/lean-wasm-emscripten"
runtime_archive="$repo_root/build/lean-runtime-emscripten/runtime/lib/lean/libleanrt.a"

: "${LEAN_WASM_EMCC:?run inside nix develop .#emscripten}"
: "${LEAN_WASM_EMXX:?run inside nix develop .#emscripten}"

"$repo_root/scripts/build-lean-runtime-emscripten.sh"

lean_prefix="$(lean --print-prefix)"
generated_c="$build_dir/LeanWasmRuntime.c"
generated_object="$build_dir/LeanWasmRuntime.o"
bridge_object="$build_dir/lean_wasm_runtime_bridge.o"
module_file="$build_dir/LeanWasmRuntime.mjs"

mkdir -p "$build_dir"

lean "$source_file"
lean -c "$generated_c" "$source_file"

common_flags=(
  -I"$lean_prefix/include"
  -O3
  -flto
  -fwasm-exceptions
  -pthread
  -DLEAN_EMSCRIPTEN
)

"$LEAN_WASM_EMCC" "${common_flags[@]}" -c "$generated_c" -o "$generated_object"
"$LEAN_WASM_EMCC" "${common_flags[@]}" -c "$bridge_file" -o "$bridge_object"

"$LEAN_WASM_EMXX" "$generated_object" "$bridge_object" "$runtime_archive" \
  -I"$lean_prefix/include" \
  -O3 \
  -flto \
  -fwasm-exceptions \
  -pthread \
  -DLEAN_EMSCRIPTEN \
  -sALLOW_MEMORY_GROWTH=1 \
  -sMODULARIZE=1 \
  -sEXPORT_ES6=1 \
  -sENVIRONMENT=node,web \
  -sFILESYSTEM=0 \
  -sEXPORTED_FUNCTIONS=_lean_wasm_utf8_length_utf8 \
  -sEXPORTED_RUNTIME_METHODS=ccall \
  --no-entry \
  -o "$module_file"

echo "built Emscripten runtime-backed module"
wc -c "$module_file" "$build_dir/LeanWasmRuntime.wasm"
