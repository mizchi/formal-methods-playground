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

            # Interactive theorem prover (Rocq, formerly Coq)
            coq

            # Lean 4 toolchain manager (lake / lean handled per-project)
            elan

            # Z3 + CVC5 for direct SMT experiments
            z3
            cvc5
          ];

          shellHook = ''
            echo "prove-playground devShell"
            echo "  alloy6 : (Alloy 6 GUI / CLI; no --version flag)"
            echo "  tlc    : $(tlc 2>&1 | head -1 || echo not-found)"
            echo "  dafny  : $(dafny --version 2>&1 | head -1 || echo not-found)"
            echo "  coqc   : $(coqc --version 2>&1 | head -1 || echo not-found)"
            echo "  elan   : $(elan --version 2>&1 | head -1 || echo not-found)"
            echo "  z3     : $(z3 --version 2>&1 | head -1 || echo not-found)"
            echo "  cvc5   : $(cvc5 --version 2>&1 | head -1 || echo not-found)"
          '';
        };
      });
}
