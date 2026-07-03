{
  description = "Proof assistants & verifiers learning playground";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
      in {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            # Model finder (Alloy 6 has the temporal extension)
            alloy6

            # TLA+ tool suite: tlc (model checker) + tla2tex
            tlaplus

            # SMT-backed program verifier
            dafny

            # Proof-oriented programming language: refinement types + SMT + tactics
            fstar

            # Interactive theorem prover (Rocq, formerly Coq)
            coq

            # Lean 4 toolchain manager (lake / lean handled per-project)
            elan

            # Z3 + CVC5 for direct SMT experiments
            z3
            cvc5

            # Why3 — backend for MoonBit's `moon prove`
            why3
            alt-ergo

            # .NET SDK for the P language (actor-model verifier).
            # P itself is installed via `dotnet tool install --global P`
            # on first entry; the shellHook handles it idempotently.
            dotnet-sdk_8
          ];

          shellHook = ''
            # MoonBit toolchain is host-installed (~/.moon/bin), not
            # packaged in nixpkgs. Make `moon` / `moonc` visible here.
            export PATH="$HOME/.moon/bin:$PATH"

            # P is a .NET tool installed per-user; make ~/.dotnet/tools
            # discoverable. DOTNET_ROOT must point at the runtime that
            # backs the SDK or `p` aborts with "App host version: 8.0.26".
            export PATH="$HOME/.dotnet/tools:$PATH"
            export DOTNET_ROOT=${pkgs.dotnet-sdk_8}/share/dotnet
            export DOTNET_CLI_TELEMETRY_OPTOUT=1

            echo "prove-playground devShell"
            echo "  alloy6 : (Alloy 6 GUI / CLI; no --version flag)"
            echo "  tlc    : $(tlc 2>&1 | head -1 || echo not-found)"
            echo "  dafny  : $(dafny --version 2>&1 | head -1 || echo not-found)"
            echo "  fstar  : $(fstar.exe --version 2>&1 | head -1 || echo not-found)"
            echo "  coqc   : $(coqc --version 2>&1 | head -1 || echo not-found)"
            echo "  elan   : $(elan --version 2>&1 | head -1 || echo not-found)"
            echo "  z3     : $(z3 --version 2>&1 | head -1 || echo not-found)"
            echo "  cvc5   : $(cvc5 --version 2>&1 | head -1 || echo not-found)"
            echo "  why3   : $(why3 --version 2>&1 | head -1 || echo not-found)"
            echo "  moon   : $(moon version 2>&1 | head -1 || echo not-installed)"
            echo "  dotnet : $(dotnet --version 2>&1 | head -1 || echo not-found)"
            echo "  P      : $(p --version 2>&1 | head -1 || echo 'not-installed (run: dotnet tool install --global P)')"
          '';
        };
      });
}
