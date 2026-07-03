#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export OPAMROOT="${OPAMROOT:-"$repo_root/.opam-root"}"
export OPAMYES="${OPAMYES:-1}"
switch_name="${MOONBIT_PROVE_SWITCH:-moonbit-prove}"
ocaml_version="${MOONBIT_PROVE_OCAML:-ocaml-base-compiler.4.14.2}"
why3_version="${MOONBIT_PROVE_WHY3:-why3.1.7.2}"
alt_ergo_version="${MOONBIT_PROVE_ALT_ERGO:-alt-ergo.2.5.4}"

opam init --bare --disable-sandboxing --no-setup

if ! opam switch list --short | grep -qx "$switch_name"; then
  opam switch create "$switch_name" "$ocaml_version"
fi

why3_install_target="$why3_version"
if [ "$why3_version" = "why3.1.7.2" ] &&
   ! opam list --switch="$switch_name" --installed --short why3 | grep -qx why3; then
  # Why3 1.7.2 has an old signal handler declaration that GCC/glibc on
  # current Ubuntu rejects. MoonBit currently accepts this Why3 line, so
  # keep the version pinned and patch only the C callback signature.
  why3_patch_dir="$OPAMROOT/pins/why3-1.7.2-patched"
  rm -rf "$why3_patch_dir"
  mkdir -p "$(dirname "$why3_patch_dir")"
  opam source "$why3_version" --dir "$why3_patch_dir"
  sed -i.bak \
    's/void wallclock_timelimit_reached()/void wallclock_timelimit_reached(int _signum)/' \
    "$why3_patch_dir/src/server/cpulimit-unix.c"
  opam pin add --switch="$switch_name" why3 "$why3_patch_dir" --no-action
  why3_install_target="why3"
fi

opam install \
  --switch="$switch_name" \
  --assume-depexts \
  "$why3_install_target" \
  "$alt_ergo_version"

opam exec --switch="$switch_name" -- why3 --version
opam exec --switch="$switch_name" -- alt-ergo --version
