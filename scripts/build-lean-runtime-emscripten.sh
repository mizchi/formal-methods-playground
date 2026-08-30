#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
repo_root="$(dirname -- "$script_dir")"
runtime_root="$repo_root/build/lean-runtime-emscripten"
source_root="$runtime_root/source"
source_dir="$source_root/src"
runtime_build="$runtime_root/runtime"
patch_file="$repo_root/languages/lean/wasm/lean-4.31.0-emscripten.patch"
patch_stamp="$source_root/.patched-lean-4.31.0"

: "${LEAN4_WASM_SOURCE:?run inside nix develop .#emscripten}"
: "${LEAN_WASM_EMXX:?run inside nix develop .#emscripten}"

lean_version="$(lean --version)"
case "$lean_version" in
  *"version 4.31.0"*"68218e876d2a38b1985b8590fff244a83c321783"*) ;;
  *) echo "Lean 4.31.0 commit 68218e8 is required to match the runtime source" >&2; exit 1 ;;
esac

if [[ -f "$patch_stamp" ]] && [[ "$(< "$patch_stamp")" != "$LEAN4_WASM_SOURCE" ]]; then
  echo "runtime source changed; remove $runtime_root and rebuild" >&2
  exit 1
fi

if [[ ! -f "$patch_stamp" ]]; then
  if [[ -e "$source_dir" ]]; then
    echo "incomplete runtime source at $source_dir; remove its build root and retry" >&2
    exit 1
  fi

  mkdir -p "$source_root"
  cp -R "$LEAN4_WASM_SOURCE/src" "$source_dir"
  chmod -R u+w "$source_dir"
  patch -d "$source_dir" -p1 < "$patch_file"
  printf '%s\n' "$LEAN4_WASM_SOURCE" > "$patch_stamp"
fi

emcmake cmake "$source_dir" \
  -B "$runtime_build" \
  -G "Unix Makefiles" \
  -DSTAGE=0 \
  -DUSE_GITHASH=OFF \
  -DUSE_GMP=OFF \
  -DUSE_MIMALLOC=OFF \
  -DMMAP=OFF \
  -DMULTI_THREAD=OFF \
  -DUSE_LAKE=OFF \
  -DCMAKE_BUILD_TYPE=Release

cmake --build "$runtime_build" --target leanrt -j "${LEAN_WASM_JOBS:-4}"

runtime_archive="$runtime_build/lib/lean/libleanrt.a"
test -f "$runtime_archive"
echo "built $runtime_archive ($(wc -c < "$runtime_archive" | tr -d ' ') bytes)"
