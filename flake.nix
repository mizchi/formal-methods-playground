{
  description = "Proof assistants & verifiers learning playground";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    quintLlmKit = {
      url = "github:quint-co/quint-llm-kit/cc75369f741af7d490936f82002c2d28e3b3d78d";
      flake = false;
    };
    choreo = {
      url = "github:quint-co/choreo/000cf4eed315187dc6f216a148781cff7dde6521";
      flake = false;
    };
    quintConnect = {
      url = "github:quint-co/quint-connect/4f018f54fc7dd4cef341d10111427bab59d3b307";
      flake = false;
    };
    quintTraceExplorer = {
      url = "github:quint-co/quint-trace-explorer/d6b3d1fddea79f93bb8cca9fbc70b508e49e8e48";
      flake = false;
    };
    lean4Source = {
      url = "github:leanprover/lean4/68218e876d2a38b1985b8590fff244a83c321783";
      flake = false;
    };
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    quintLlmKit,
    choreo,
    quintConnect,
    quintTraceExplorer,
    lean4Source,
  }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
        fizzbeeVersion = "0.5.2";
        fizzbeeSources = {
          "aarch64-darwin" = {
            asset = "macos_arm";
            hash = "sha256-qrIj4LrI8MBSz3dNwlhy9ywTjaMPQHm5FLuciSGRCQQ=";
          };
          "x86_64-darwin" = {
            asset = "macos_x86";
            hash = "sha256-YpO9erkMebhgfcn7LwlAf94OEaxlluiEvvf2YBeFl/o=";
          };
          "aarch64-linux" = {
            asset = "linux_arm";
            hash = "sha256-AAEbv+m/THvLA6W/H1t/5zkBEa1vBhHGvnHoaSUE2k4=";
          };
          "x86_64-linux" = {
            asset = "linux_x86";
            hash = "sha256-9JS3sq/MfOJFde2Ro4m0a7u+WXb55LXNcXMnAS9eA5U=";
          };
        };
        fizzbeeSource = fizzbeeSources.${system};
        fizzbee = pkgs.stdenvNoCC.mkDerivation {
          pname = "fizzbee";
          version = fizzbeeVersion;
          src = pkgs.fetchurl {
            url = "https://github.com/fizzbee-io/fizzbee/releases/download/v${fizzbeeVersion}/fizzbee-v${fizzbeeVersion}-${fizzbeeSource.asset}.tar.gz";
            inherit (fizzbeeSource) hash;
          };
          nativeBuildInputs = [ pkgs.makeWrapper ];
          installPhase = ''
            runHook preInstall
            mkdir -p "$out/libexec/fizzbee" "$out/bin"
            cp -R . "$out/libexec/fizzbee"
            makeWrapper "$out/libexec/fizzbee/fizz" "$out/bin/fizz" \
              --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.bash pkgs.coreutils pkgs.python3 ]}
            runHook postInstall
          '';
          meta = {
            description = "Python-like formal specification and model checker for distributed systems";
            homepage = "https://fizzbee.io/";
            license = pkgs.lib.licenses.asl20;
            mainProgram = "fizz";
            platforms = builtins.attrNames fizzbeeSources;
          };
        };
      in {
        packages.fizzbee = fizzbee;

        devShells.default = pkgs.mkShell {
          packages = (with pkgs; [
            # Model finder (Alloy 6 has the temporal extension)
            alloy6

            # TLA+ tool suite: tlc (model checker) + tla2tex
            tlaplus

            # Executable TLA-style specifications with a typed surface syntax
            quint

            # Python-like distributed-system design specification and model checker
            fizzbee

            # SMT-backed program verifier
            dafny

            # Dafny JavaScript / Go code-generation targets
            nodejs_24
            pnpm
            go
            gotools

            # Proof-oriented programming language: refinement types + SMT + tactics
            fstar

            # Interactive theorem prover core + standard library (Rocq, formerly Coq)
            rocqPackages.rocq-core
            rocqPackages.stdlib

            # Lean 4 toolchain manager (lake / lean handled per-project)
            elan

            # Lean-generated C -> freestanding WebAssembly toolchain
            llvmPackages.clang-unwrapped
            lld
            wabt
            wasmtime

            # Z3 + CVC5 for direct SMT experiments
            z3
            cvc5

            # Shared task runner for local and CI-style checks
            just
            zsh

            # Rust-based Quint Connect and Trace Explorer evaluation
            cargo
            rustc
            git
            jq
            expect

            # Mermaid diagram renderer / syntax checker for GitBook docs
            mermaid-cli

            # OCaml package manager; useful for MoonBit's Why3 1.7.x workaround.
            opam
            pkg-config
            gmp
            zlib

            # Why3 — backend for MoonBit's `moon prove`
            why3
            alt-ergo

            # .NET SDK for the P language (actor-model verifier).
            # P itself is installed via `dotnet tool install --global P`
            # on first entry; the shellHook handles it idempotently.
            dotnet-sdk_8
          ]) ++ pkgs.lib.optionals pkgs.stdenv.isLinux [
            # Browser used by mermaid-cli / Puppeteer in CI.
            pkgs.chromium
          ];

          shellHook = ''
            ${pkgs.lib.optionalString pkgs.stdenv.isLinux ''
            export PUPPETEER_EXECUTABLE_PATH=${pkgs.chromium}/bin/chromium
            ''}

            # MoonBit toolchain is host-installed (~/.moon/bin), not
            # packaged in nixpkgs. Make `moon` / `moonc` visible here.
            export PATH="$HOME/.moon/bin:$PATH"

            # P is a .NET tool installed per-user; make ~/.dotnet/tools
            # discoverable. DOTNET_ROOT must point at the runtime that
            # backs the SDK or `p` aborts with "App host version: 8.0.26".
            export PATH="$HOME/.dotnet/tools:$PATH"
            export DOTNET_ROOT=${pkgs.dotnet-sdk_8}/share/dotnet
            export DOTNET_CLI_TELEMETRY_OPTOUT=1

            # Use the unwrapped compiler here: the normal Nix clang wrapper
            # rejects cross-target builds without an explicit cross stdenv.
            export LEAN_WASM_CLANG=${pkgs.llvmPackages.clang-unwrapped}/bin/clang
            export LEAN_WASM_LD=${pkgs.lld}/bin/wasm-ld
            export LEAN_WASM_OBJDUMP=${pkgs.wabt}/bin/wasm-objdump
            export LEAN_WASM_RUNTIME=${pkgs.wasmtime}/bin/wasmtime

            # Pinned upstream sources used by `just evaluate-quint-ecosystem`.
            export QUINT_EVAL_LLM_KIT_SRC=${quintLlmKit}
            export QUINT_EVAL_CHOREO_SRC=${choreo}
            export QUINT_EVAL_CONNECT_SRC=${quintConnect}
            export QUINT_EVAL_TRACE_EXPLORER_SRC=${quintTraceExplorer}

            echo "formal-methods-playground devShell"
            echo "  alloy6 : (Alloy 6 GUI / CLI; no --version flag)"
            echo "  tlc    : $(tlc 2>&1 | head -1 || echo not-found)"
            echo "  quint  : $(quint --version 2>&1 | head -1 || echo not-found)"
            echo "  fizz   : $(command -v fizz >/dev/null && echo v${fizzbeeVersion} || echo not-found)"
            echo "  dafny  : $(dafny --version 2>&1 | head -1 || echo not-found)"
            echo "  fstar  : $(fstar.exe --version 2>&1 | head -1 || echo not-found)"
            echo "  rocq   : $(rocq -v 2>&1 | head -1 || echo not-found)"
            echo "  elan   : $(elan --version 2>&1 | head -1 || echo not-found)"
            echo "  wasm32 : $($LEAN_WASM_CLANG --version 2>&1 | head -1 || echo not-found)"
            echo "  wasmtime: $($LEAN_WASM_RUNTIME --version 2>&1 | head -1 || echo not-found)"
            echo "  z3     : $(z3 --version 2>&1 | head -1 || echo not-found)"
            echo "  cvc5   : $(cvc5 --version 2>&1 | head -1 || echo not-found)"
            echo "  just   : $(just --version 2>&1 | head -1 || echo not-found)"
            echo "  rustc  : $(rustc --version 2>&1 | head -1 || echo not-found)"
            echo "  cargo  : $(cargo --version 2>&1 | head -1 || echo not-found)"
            echo "  mmdc   : $(mmdc --version 2>&1 | head -1 || echo not-found)"
            echo "  opam   : $(opam --version 2>&1 | head -1 || echo not-found)"
            echo "  why3   : $(why3 --version 2>&1 | head -1 || echo not-found)"
            echo "  moon   : $(moon version 2>&1 | head -1 || echo not-installed)"
            echo "  dotnet : $(dotnet --version 2>&1 | head -1 || echo not-found)"
            echo "  P      : $(p --version 2>&1 | head -1 || echo 'not-installed (run: dotnet tool install --global P)')"
          '';
        };

        # Kept separate because Emscripten adds roughly 2 GiB of unpacked
        # dependencies and the runtime-backed build downloads patched libuv.
        devShells.emscripten = pkgs.mkShell {
          packages = with pkgs; [
            elan
            nodejs_24
            emscripten
            cmake
            gnumake
            patch
            git
            just
            wabt
          ];

          shellHook = ''
            export LEAN4_WASM_SOURCE=${lean4Source}
            export LEAN_WASM_EMCC=${pkgs.emscripten}/bin/emcc
            export LEAN_WASM_EMXX=${pkgs.emscripten}/bin/em++
            export LEAN_WASM_OBJDUMP=${pkgs.wabt}/bin/wasm-objdump

            echo "formal-methods-playground Emscripten devShell"
            echo "  lean : $(lean --version 2>&1 | head -1 || echo not-found)"
            echo "  emcc : $($LEAN_WASM_EMCC --version 2>&1 | head -1 || echo not-found)"
            echo "  node : $(node --version 2>&1 | head -1 || echo not-found)"
          '';
        };
      });
}
