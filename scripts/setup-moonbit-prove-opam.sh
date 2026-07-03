#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export OPAMROOT="${OPAMROOT:-"$repo_root/.opam-root"}"
export OPAMYES="${OPAMYES:-1}"
# Why3 1.7.2 has an old signal handler declaration that GCC/glibc on
# current Ubuntu can promote to an error. Keep the pinned Why3 version
# MoonBit accepts, but downgrade that diagnostic during the opam build.
export CFLAGS="${CFLAGS:-} -Wno-error=incompatible-pointer-types"

switch_name="${MOONBIT_PROVE_SWITCH:-moonbit-prove}"
ocaml_version="${MOONBIT_PROVE_OCAML:-ocaml-base-compiler.4.14.2}"
why3_version="${MOONBIT_PROVE_WHY3:-why3.1.7.2}"
alt_ergo_version="${MOONBIT_PROVE_ALT_ERGO:-alt-ergo.2.5.4}"

opam init --bare --disable-sandboxing --no-setup

if ! opam switch list --short | grep -qx "$switch_name"; then
  opam switch create "$switch_name" "$ocaml_version"
fi

opam install \
  --switch="$switch_name" \
  --assume-depexts \
  "$why3_version" \
  "$alt_ergo_version"

opam exec --switch="$switch_name" -- why3 --version
opam exec --switch="$switch_name" -- alt-ergo --version
