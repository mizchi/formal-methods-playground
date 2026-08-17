set shell := ["zsh", "-cu"]

default:
    just --list

check: test-moonbit check-z3

check-ci: check-z3 check-alloy check-tla check-quint check-fizzbee check-dafny check-fstar check-lean check-rocq check-mermaid test-moonbit check-p

check-with-prove: check prove-moonbit

tool-versions:
    z3 --version
    command -v alloy6 >/dev/null && echo "alloy6: installed"
    tlc 2>&1 | head -1
    quint --version
    command -v fizz >/dev/null && echo "fizzbee: installed"
    dafny --version
    fstar.exe --version
    lean --version
    rocq -v | head -1
    mmdc --version
    moon version
    dotnet --version
    p --version

test-moonbit:
    cd languages/moonbit/checkout_form && moon test
    cd languages/moonbit/p2p_game_protocol && moon test

setup-moonbit-prove-opam:
    ./scripts/setup-moonbit-prove-opam.sh

prove-moonbit:
    ./scripts/moon-prove-opam.sh

prove-moonbit-nix:
    cd languages/moonbit/checkout_form && nix develop ../../.. -c moon prove

check-z3:
    ./languages/z3/check_checkout_form.sh
    ./languages/z3/check_trust_boundary.sh
    ./languages/z3/check_rate_limit_subsumption.sh
    ./languages/z3/check_wire_contract.sh

check-alloy:
    ./scripts/check-alloy.sh

check-tla:
    ./scripts/check-tla.sh

check-quint:
    ./scripts/check-quint.sh

# Network-heavy, pinned upstream evaluation; intentionally separate from check-ci.
evaluate-quint-ecosystem:
    ./scripts/evaluate-quint-ecosystem.sh

check-fizzbee:
    ./scripts/check-fizzbee.sh

check-dafny:
    dafny verify languages/dafny/checkout_form.dfy languages/dafny/rbac_screens.dfy

check-fstar:
    fstar.exe languages/fstar/CheckoutForm.fst

check-lean:
    lean languages/lean/Rbac.lean

check-rocq:
    ./scripts/check-rocq.sh

check-mermaid:
    ./scripts/check-mermaid.sh

check-p:
    cd languages/p/PingPong && p compile && p check --schedules 1000
