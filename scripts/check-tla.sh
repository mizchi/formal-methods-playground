#!/usr/bin/env bash
set -euo pipefail

# The replayed logs are generated from traces/*.json, so the generated module
# has to be current before anything the replay says can be trusted.
./scripts/trace-to-tla.sh --check

# Expected results are not written here. They live in claims/catalog.json, and
# scripts/check-claims.py is the oracle: it runs every config -- green checks
# and breaking variants alike -- and compares the outcome, the invariant that
# broke and the witness against the claim. Asserting only "tlc exited 0" let a
# weakened invariant leave the green checks green and the breaking variants
# quietly not breaking.
./scripts/check-claims.py --tool tlc
