#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
repo_root="$(dirname -- "$script_dir")"
source_file="$repo_root/languages/lean/wasm/LeanWasm.lean"
build_dir="$repo_root/build/lean-wasm-emscripten"

: "${LEAN_WASM_EMCC:?run inside nix develop .#emscripten}"

lean_prefix="$(lean --print-prefix)"
generated_c="$build_dir/LeanWasm.c"
module_file="$build_dir/LeanWasm.mjs"

mkdir -p "$build_dir"

lean "$source_file"
lean -c "$generated_c" "$source_file"

"$LEAN_WASM_EMCC" "$generated_c" \
  -I"$lean_prefix/include" \
  -O3 \
  -flto \
  -sMODULARIZE=1 \
  -sEXPORT_ES6=1 \
  -sENVIRONMENT=node,web \
  -sFILESYSTEM=0 \
  -sEXPORTED_FUNCTIONS=_lean_wasm_add \
  --no-entry \
  -o "$module_file"

echo "built Emscripten scalar module"
wc -c "$module_file" "$build_dir/LeanWasm.wasm"
