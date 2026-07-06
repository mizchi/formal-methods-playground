#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export OPAMROOT="${OPAMROOT:-"$repo_root/.opam-root"}"
switch_name="${MOONBIT_PROVE_SWITCH:-moonbit-prove}"

if ! opam switch list --short | grep -qx "$switch_name"; then
  cat >&2 <<EOF
opam switch '$switch_name' is missing.
Run:
  nix develop -c just setup-moonbit-prove-opam
EOF
  exit 1
fi

eval "$(opam env --switch="$switch_name" --set-switch)"

why3 --version
alt-ergo --version

for pkg in checkout_form p2p_game_protocol; do
  echo "== moon prove: $pkg"
  (cd "$repo_root/languages/moonbit/$pkg" && moon prove)
done
