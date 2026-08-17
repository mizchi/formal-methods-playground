#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

required_env=(
  QUINT_EVAL_LLM_KIT_SRC
  QUINT_EVAL_CHOREO_SRC
  QUINT_EVAL_CONNECT_SRC
  QUINT_EVAL_TRACE_EXPLORER_SRC
)

for env_name in "${required_env[@]}"; do
  if [ -z "${!env_name:-}" ] || [ ! -d "${!env_name}" ]; then
    echo "$env_name is unavailable. Run this task inside 'nix develop'." >&2
    exit 1
  fi
done

for tool_name in quint cargo rustc git jq expect; do
  if ! command -v "$tool_name" >/dev/null 2>&1; then
    echo "$tool_name is required. Run this task inside 'nix develop'." >&2
    exit 127
  fi
done

eval_tmp_parent="${TMPDIR:-/tmp}"
eval_tmp_dir="$(mktemp -d "${eval_tmp_parent%/}/quint-ecosystem.XXXXXX")"

cleanup() {
  case "$eval_tmp_dir" in
    "${eval_tmp_parent%/}"/quint-ecosystem.*)
      rm -rf -- "$eval_tmp_dir"
      ;;
    *)
      echo "Refusing to clean unexpected path: $eval_tmp_dir" >&2
      ;;
  esac
}
trap cleanup EXIT

copy_writable() {
  local source_dir="$1"
  local target_dir="$2"
  mkdir -p "$target_dir"
  cp -R "$source_dir"/. "$target_dir"
  chmod -R u+w "$target_dir"
}

llm_review="$QUINT_EVAL_LLM_KIT_SRC/quint-llm-kit-plugin/skills/quint-modeling/guidelines/review.md"
choreo_spec="$QUINT_EVAL_CHOREO_SRC/examples/two_phase_commit/two_phase_commit.qnt"
itf_trace="$eval_tmp_dir/two-phase-commit.itf.json"

echo "== LLM Kit: pinned review workflow is present"
test -f "$llm_review"
rg -q 'Witnesses present & per-action' "$llm_review"
rg -q 'counterexample observed in the runs executed' "$llm_review"

echo "== Choreo: typecheck the pinned two-phase commit model"
quint typecheck "$choreo_spec"

echo "== Choreo: run the deterministic commit scenario and export ITF"
quint test "$choreo_spec" \
  --main two_phase_commit \
  --match commitTest \
  --max-samples 1 \
  --out-itf "$itf_trace"

echo "== Choreo: sample the consistency invariant"
quint run "$choreo_spec" \
  --main two_phase_commit \
  --invariant consistency \
  --max-samples 1000 \
  --max-steps 20 \
  --verbosity 0

state_count="$(jq '.states | length' "$itf_trace")"
if [ "$state_count" -ne 8 ]; then
  echo "Expected the commit scenario to export 8 states, got $state_count" >&2
  exit 1
fi
echo "Choreo/ITF positive control passed: commitTest exported $state_count states"

connect_work="$eval_tmp_dir/quint-connect"
copy_writable "$QUINT_EVAL_CONNECT_SRC" "$connect_work"
connect_manifest="$connect_work/Cargo.toml"
connect_target="$eval_tmp_dir/connect-target"

echo "== Quint Connect: replay the model against the correct Rust implementation"
CARGO_TARGET_DIR="$connect_target" cargo test \
  --manifest-path "$connect_manifest" \
  --locked \
  -p quint-connect \
  --example two_phase_commit \
  -- --nocapture

echo "== Quint Connect: the deliberately broken Rust implementation must be rejected"
git -C "$connect_work" apply "$repo_root/experiments/quint-ecosystem/broken-connect.patch"
if CARGO_TARGET_DIR="$connect_target" cargo test \
  --manifest-path "$connect_manifest" \
  --locked \
  -p quint-connect \
  --example two_phase_commit \
  -- --nocapture >"$eval_tmp_dir/connect-negative.log" 2>&1; then
  echo "Expected Quint Connect to reject the broken participant commit transition" >&2
  exit 1
fi

if ! rg -q 'states diverge|State invariant failed|stage.*Committed|stage.*Aborted' \
  "$eval_tmp_dir/connect-negative.log"; then
  echo "The broken Connect probe failed for an unexpected reason" >&2
  sed -n '1,240p' "$eval_tmp_dir/connect-negative.log" >&2
  exit 1
fi
echo "Quint Connect negative control passed: Committed vs Aborted drift was detected"

trace_work="$eval_tmp_dir/quint-trace-explorer"
copy_writable "$QUINT_EVAL_TRACE_EXPLORER_SRC" "$trace_work"
trace_target="$eval_tmp_dir/trace-target"

echo "== Trace Explorer: build and parse the generated ITF in a pseudo-terminal"
CARGO_TARGET_DIR="$trace_target" cargo build \
  --manifest-path "$trace_work/Cargo.toml" \
  --locked

trace_bin="$trace_target/debug/quint-trace-explorer"
"$trace_bin" --help | rg -q 'ITF|trace'

QUINT_EVAL_TRACE_BIN="$trace_bin" \
QUINT_EVAL_TRACE_FILE="$itf_trace" \
expect <<'EXPECT_SCRIPT'
set timeout 10
log_user 0
spawn $env(QUINT_EVAL_TRACE_BIN) $env(QUINT_EVAL_TRACE_FILE)
after 500
send -- "q"
expect eof
set wait_status [wait]
exit [lindex $wait_status 3]
EXPECT_SCRIPT

echo "Trace Explorer positive control passed: generated ITF opened and exited cleanly"
echo "Quint ecosystem evaluation passed"
