#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=scripts/lib/install-lib.sh
source "$ROOT/scripts/lib/install-lib.sh"

TMP_ROOT=""

cleanup() {
  [[ -z "$TMP_ROOT" ]] || rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

sandbox() {
  cleanup
  TMP_ROOT="$(mktemp -d)"
  mkdir -p "$TMP_ROOT/source" "$TMP_ROOT/home"
  printf 'rule body\n' > "$TMP_ROOT/source/rule.md"
}

assert_contains() {
  local haystack="$1" needle="$2"
  printf '%s' "$haystack" | grep -F -- "$needle" >/dev/null
}

test_native_path_round_trips_to_the_same_file() {
  sandbox

  local converted
  converted="$(posix_path "$(native_path "$TMP_ROOT/source/rule.md")")"

  [[ -f "$converted" ]]
  [[ "$(cat "$converted")" == "rule body" ]]
}

test_agent_home_is_an_existing_directory() {
  [[ -d "$(agent_home)" ]]
}

test_link_creates_a_target_resolving_to_the_source() {
  sandbox

  link "$TMP_ROOT/source" "$TMP_ROOT/home/rules" >/dev/null

  is_same_dir "$TMP_ROOT/home/rules" "$TMP_ROOT/source"
}

test_link_reports_an_existing_link_as_unchanged() {
  sandbox
  link "$TMP_ROOT/source" "$TMP_ROOT/home/rules" >/dev/null

  local output
  output="$(link "$TMP_ROOT/source" "$TMP_ROOT/home/rules")"

  assert_contains "$output" "already linked"
}

test_link_backs_up_a_pre_existing_target() {
  sandbox
  printf 'hand written\n' > "$TMP_ROOT/home/rules"

  link "$TMP_ROOT/source" "$TMP_ROOT/home/rules" >/dev/null

  [[ "$(cat "$TMP_ROOT/home/rules.bak.$TS")" == "hand written" ]]
  is_same_dir "$TMP_ROOT/home/rules" "$TMP_ROOT/source"
}

test_link_fails_on_a_missing_source() {
  sandbox

  local output rc=0
  output="$( (link "$TMP_ROOT/absent" "$TMP_ROOT/home/rules") 2>&1 )" || rc=$?

  [[ "$rc" -ne 0 ]]
  assert_contains "$output" "source missing"
}

test_inline_imports_expands_a_known_prefix() {
  sandbox
  mkdir -p "$TMP_ROOT/source/rules"
  printf 'rule body\n' > "$TMP_ROOT/source/rules/naming.md"
  printf '# Head\n- @rules/naming.md — naming\n' > "$TMP_ROOT/source/CLAUDE.md"

  inline_imports "$TMP_ROOT/source/CLAUDE.md" "$TMP_ROOT/out.md" "rules=$TMP_ROOT/source"

  assert_contains "$(cat "$TMP_ROOT/out.md")" "rule body"
  assert_contains "$(cat "$TMP_ROOT/out.md")" "inlined from rules/naming.md"
}

test_inline_imports_leaves_an_unknown_prefix_untouched() {
  sandbox
  printf '# Head\n- @sdd/workflow.md — sdd\n' > "$TMP_ROOT/source/CLAUDE.md"

  inline_imports "$TMP_ROOT/source/CLAUDE.md" "$TMP_ROOT/out.md" "rules=$TMP_ROOT/source"

  assert_contains "$(cat "$TMP_ROOT/out.md")" "- @sdd/workflow.md — sdd"
}

test_mcp_launch_spec_fails_when_the_bin_is_absent() {
  ! mcp_launch_spec "absent-mcp" "absent-mcp-bin" >/dev/null 2>&1
}

test_mcp_launch_spec_names_a_command_for_an_installed_bin() {
  local spec
  spec="$(mcp_launch_spec "jq" "jq")"

  [[ -n "$(printf '%s' "$spec" | jq -r '.command')" ]]
  [[ "$(printf '%s' "$spec" | jq -r '.args | type')" == "array" ]]
}

run_test() {
  local name="$1"
  if "$name"; then
    printf 'ok - %s\n' "$name"
  else
    printf 'not ok - %s\n' "$name" >&2
    exit 1
  fi
}

run_test test_native_path_round_trips_to_the_same_file
run_test test_agent_home_is_an_existing_directory
run_test test_link_creates_a_target_resolving_to_the_source
run_test test_link_reports_an_existing_link_as_unchanged
run_test test_link_backs_up_a_pre_existing_target
run_test test_link_fails_on_a_missing_source
run_test test_inline_imports_expands_a_known_prefix
run_test test_inline_imports_leaves_an_unknown_prefix_untouched
run_test test_mcp_launch_spec_fails_when_the_bin_is_absent
run_test test_mcp_launch_spec_names_a_command_for_an_installed_bin
