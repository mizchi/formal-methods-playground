set shell := ["zsh", "-cu"]

default:
    just --list

check: test-moonbit check-z3

check-ci: check-z3 check-alloy check-tla check-quint check-fizzbee check-dafny check-fstar check-lean test-lean-wasm check-rocq check-mermaid test-moonbit check-p

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
    "$LEAN_WASM_CLANG" --version | head -1
    "$LEAN_WASM_LD" --version
    "$LEAN_WASM_RUNTIME" --version
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
    ./languages/z3/check_schema_evolution.sh
    ./usecases/campaign-targeting/check.sh

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
    dafny verify languages/dafny/checkout_form.dfy languages/dafny/rbac_screens.dfy languages/dafny/dijkstra.dfy

translate-dafny-dijkstra: check-dafny
    mkdir -p build/dafny
    dafny translate js languages/dafny/dijkstra.dfy -o build/dafny/dijkstra.js --include-runtime --no-verify
    dafny translate go languages/dafny/dijkstra.dfy -o build/dafny/dijkstra.go --include-runtime --no-verify

run-dafny-dijkstra-js: translate-dafny-dijkstra
    pnpm add --dir build/dafny --save-exact bignumber.js@11.1.5
    node build/dafny/dijkstra.js

run-dafny-dijkstra-go: translate-dafny-dijkstra
    cd build/dafny/dijkstra-go && env GO111MODULE=off GOPATH="$PWD" go run src/dijkstra.go

benchmark-dafny-dijkstra-js: translate-dafny-dijkstra
    pnpm add --dir build/dafny --save-exact bignumber.js@11.1.5
    node scripts/benchmark-dafny-dijkstra-js.mjs

check-fstar:
    fstar.exe languages/fstar/CheckoutForm.fst

check-lean:
    lean languages/lean/Rbac.lean
    lean languages/lean/wasm/LeanWasm.lean
    lean languages/lean/wasm/LeanWasmRuntime.lean

build-lean-wasm:
    ./scripts/build-lean-wasm.sh

inspect-lean-wasm: build-lean-wasm
    "$LEAN_WASM_OBJDUMP" -x build/lean-wasm/lean_wasm.wasm

run-lean-wasm: build-lean-wasm
    "$LEAN_WASM_RUNTIME" run --invoke lean_wasm_add build/lean-wasm/lean_wasm.wasm 20 22

test-lean-wasm: build-lean-wasm
    node scripts/test-lean-wasm.mjs build/lean-wasm/lean_wasm.wasm

# Run these inside `nix develop .#emscripten`.
build-lean-wasm-emscripten:
    ./scripts/build-lean-wasm-emscripten.sh

test-lean-wasm-emscripten: build-lean-wasm-emscripten
    node scripts/test-lean-wasm-emscripten.mjs "$PWD/build/lean-wasm-emscripten/LeanWasm.mjs"

# Network-heavy on the first run: builds Lean's patched wasm32 runtime and libuv.
build-lean-wasm-emscripten-runtime:
    ./scripts/build-lean-wasm-emscripten-runtime.sh

test-lean-wasm-emscripten-runtime: build-lean-wasm-emscripten-runtime
    node scripts/test-lean-wasm-emscripten-runtime.mjs "$PWD/build/lean-wasm-emscripten/LeanWasmRuntime.mjs"

inspect-lean-wasm-emscripten: build-lean-wasm-emscripten build-lean-wasm-emscripten-runtime
    "$LEAN_WASM_OBJDUMP" -x build/lean-wasm-emscripten/LeanWasm.wasm
    "$LEAN_WASM_OBJDUMP" -x build/lean-wasm-emscripten/LeanWasmRuntime.wasm

check-rocq:
    ./scripts/check-rocq.sh

check-mermaid:
    ./scripts/check-mermaid.sh

check-p:
    cd languages/p/PingPong && p compile && p check --schedules 1000
