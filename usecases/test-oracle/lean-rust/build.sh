#!/usr/bin/env bash
# Lean の実装を C 経由でビルドして、Rust のテストのオラクルにする
set -euo pipefail
cd "$(dirname "$0")"
lean -c lean/MidOracle.c lean/MidOracle.lean
leanc -O3 lean/MidOracle.c -o lean/mid_oracle
(cd midpoint && LEAN_ORACLE="$PWD/../lean/mid_oracle" cargo test -- --nocapture)
