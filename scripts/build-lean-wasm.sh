#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
repo_root="$(dirname -- "$script_dir")"
source_file="$repo_root/languages/lean/wasm/LeanWasm.lean"
build_dir="$repo_root/build/lean-wasm"

: "${LEAN_WASM_CLANG:?run inside nix develop: LEAN_WASM_CLANG is unset}"
: "${LEAN_WASM_LD:?run inside nix develop: LEAN_WASM_LD is unset}"

lean_prefix="$(lean --print-prefix)"
generated_c="$build_dir/LeanWasm.c"
generated_object="$build_dir/LeanWasm.o"
wasm_file="$build_dir/lean_wasm.wasm"

mkdir -p "$build_dir"

# Verification is an explicit gate; `lean -c` is then only code generation.
lean "$source_file"
lean -c "$generated_c" "$source_file"

common_flags=(
  --target=wasm32
  -O3
  -ffunction-sections
  -fdata-sections
  -I"$lean_prefix/include"
)

"$LEAN_WASM_CLANG" "${common_flags[@]}" -c "$generated_c" -o "$generated_object"

"$LEAN_WASM_LD" \
  --no-entry \
  --export=lean_wasm_add \
  --gc-sections \
  --strip-all \
  "$generated_object" \
  -o "$wasm_file"

echo "built $wasm_file ($(wc -c < "$wasm_file" | tr -d ' ') bytes)"
