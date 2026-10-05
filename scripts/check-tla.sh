#!/usr/bin/env bash
set -euo pipefail

# The replayed logs are generated from traces/*.json, so the generated module
# has to be current before anything the replay says can be trusted.
./scripts/trace-to-tla.sh --check

# Expected results are not written here. They live in claims/catalog.json, and
# scripts/check-claims.py is the oracle: it runs every config -- green checks
# and breaking variants alike -- and compares the outcome, the invariant that
# broke, the witness the counterexample must still show, and the state count
# against the claim. It also refuses a .cfg that no claim covers, and a green
# claim with neither a breaking variant nor a written reason for not having one.
#
# This replaces the run_tlc / run_tlc_expect_violation pair that used to live
# here. Same discipline, one more step: the expectations are data rather than
# arguments at a call site, so the READMEs can be checked against them too.
./scripts/check-claims.py --tool tlc
