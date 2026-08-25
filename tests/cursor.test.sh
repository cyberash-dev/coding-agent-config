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

# A failing assertion inside a test function does not abort it: `set -e` is
# suppressed for functions called from an `if` condition, which is how run_test
# invokes them. Assertions are chained so the first failure decides the test.
sandbox() {
  cleanup
  TMP_ROOT="$(mktemp -d)"
  CURSOR_MCP="$TMP_ROOT/cursor/mcp.json"
  CURSOR_MCP_BACKED_UP=0
  mkdir -p "$TMP_ROOT/rules" "$TMP_ROOT/out"
  printf '# Naming\nbody line\n' > "$TMP_ROOT/rules/naming.md"
  printf '# Testing\nanother body\n' > "$TMP_ROOT/rules/testing.md"
  cat > "$TMP_ROOT/CLAUDE.md" <<'INDEX'
# Global Instructions

## Code conventions
- @rules/naming.md — naming for classes, methods, variables
- @rules/testing.md — AAA: mocking only at boundaries
INDEX
}

assert_contains() {
  local haystack="$1" needle="$2"
  printf '%s' "$haystack" | grep -F -- "$needle" >/dev/null
}

assert_lacks() {
  local haystack="$1" needle="$2"
  ! printf '%s' "$haystack" | grep -F -- "$needle" >/dev/null
}

test_cursor_rules_are_written_one_per_index_entry() {
  sandbox

  build_cursor_rules "$TMP_ROOT/CLAUDE.md" "$TMP_ROOT" "$TMP_ROOT/out" >/dev/null

  [[ -f "$TMP_ROOT/out/naming.mdc" ]] \
    && [[ -f "$TMP_ROOT/out/testing.mdc" ]]
}

test_cursor_rule_always_applies_and_keeps_the_body() {
  sandbox

  build_cursor_rules "$TMP_ROOT/CLAUDE.md" "$TMP_ROOT" "$TMP_ROOT/out" >/dev/null

  local written
  written="$(cat "$TMP_ROOT/out/naming.mdc")"
  assert_contains "$written" "alwaysApply: true" \
    && assert_contains "$written" "body line" \
    && assert_contains "$written" "# Naming"
}

test_cursor_rule_carries_the_description_from_the_index() {
  sandbox

  build_cursor_rules "$TMP_ROOT/CLAUDE.md" "$TMP_ROOT" "$TMP_ROOT/out" >/dev/null

  assert_contains "$(cat "$TMP_ROOT/out/naming.mdc")" \
    'description: "naming for classes, methods, variables"'
}

test_cursor_rule_quotes_a_description_holding_a_colon() {
  sandbox

  build_cursor_rules "$TMP_ROOT/CLAUDE.md" "$TMP_ROOT" "$TMP_ROOT/out" >/dev/null

  assert_contains "$(cat "$TMP_ROOT/out/testing.mdc")" \
    'description: "AAA: mocking only at boundaries"'
}

test_cursor_rules_skip_an_import_outside_the_rules_prefix() {
  sandbox
  printf -- '- @sdd/workflow-sdd.md — sdd workflow\n' >> "$TMP_ROOT/CLAUDE.md"

  build_cursor_rules "$TMP_ROOT/CLAUDE.md" "$TMP_ROOT" "$TMP_ROOT/out" >/dev/null

  [[ ! -e "$TMP_ROOT/out/workflow-sdd.mdc" ]]
}

test_cursor_rules_fail_on_an_index_entry_without_a_rule_file() {
  sandbox
  printf -- '- @rules/absent.md — missing rule\n' >> "$TMP_ROOT/CLAUDE.md"

  local rc=0 output
  output="$( (build_cursor_rules "$TMP_ROOT/CLAUDE.md" "$TMP_ROOT" "$TMP_ROOT/out") 2>&1 )" || rc=$?

  [[ "$rc" -ne 0 ]] \
    && assert_contains "$output" "rules/absent.md"
}

test_cursor_rule_without_a_description_omits_the_field() {
  sandbox
  printf '# Head\n- @rules/naming.md\n' > "$TMP_ROOT/CLAUDE.md"

  build_cursor_rules "$TMP_ROOT/CLAUDE.md" "$TMP_ROOT" "$TMP_ROOT/out" >/dev/null

  local written
  written="$(cat "$TMP_ROOT/out/naming.mdc")"
  assert_lacks "$written" "description:" \
    && assert_contains "$written" "alwaysApply: true"
}

test_build_cursor_script_adds_orchestration_only_with_teams() {
  sandbox

  bash "$ROOT/scripts/build-cursor.sh" >/dev/null
  [[ ! -e "$ROOT/build/cursor/rules/orchestration.mdc" ]] || return 1

  bash "$ROOT/scripts/build-cursor.sh" --teams >/dev/null
  [[ -f "$ROOT/build/cursor/rules/orchestration.mdc" ]]
}

test_build_cursor_script_writes_the_language_rule() {
  sandbox

  bash "$ROOT/scripts/build-cursor.sh" --lang=ru >/dev/null

  assert_contains "$(cat "$ROOT/build/cursor/rules/language.mdc")" "in Russian"
}

test_build_cursor_script_rejects_an_unknown_language() {
  sandbox

  local rc=0
  bash "$ROOT/scripts/build-cursor.sh" --lang=de >/dev/null 2>&1 || rc=$?

  [[ "$rc" -ne 0 ]]
}

test_cursor_mcp_registration_keeps_the_servers_already_there() {
  sandbox
  mkdir -p "$(dirname "$CURSOR_MCP")"
  printf '%s' '{"mcpServers":{"Figma":{"url":"http://127.0.0.1:3845/mcp"}}}' > "$CURSOR_MCP"

  register_mcp_cursor "code-skeleton" "/usr/local/bin/code-skeleton-mcp" '[]' '{}' >/dev/null

  local written
  written="$(cat "$CURSOR_MCP")"
  [[ "$(printf '%s' "$written" | jq -r '.mcpServers["code-skeleton"].command')" \
       == "/usr/local/bin/code-skeleton-mcp" ]] \
    && [[ "$(printf '%s' "$written" | jq -r '.mcpServers.Figma.url')" == "http://127.0.0.1:3845/mcp" ]] \
    && [[ "$(printf '%s' "$written" | jq -r '.mcpServers["code-skeleton"] | has("type")')" == "false" ]]
}

test_cursor_mcp_registration_records_args_and_env() {
  sandbox

  register_mcp_cursor "code-skeleton" "node" '["/opt/entry.js"]' '{"TOKEN":"x"}' >/dev/null

  local written
  written="$(cat "$CURSOR_MCP")"
  [[ "$(printf '%s' "$written" | jq -r '.mcpServers["code-skeleton"].args[0]')" == "/opt/entry.js" ]] \
    && [[ "$(printf '%s' "$written" | jq -r '.mcpServers["code-skeleton"].env.TOKEN')" == "x" ]]
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

run_test test_cursor_rules_are_written_one_per_index_entry
run_test test_cursor_rule_always_applies_and_keeps_the_body
run_test test_cursor_rule_carries_the_description_from_the_index
run_test test_cursor_rule_quotes_a_description_holding_a_colon
run_test test_cursor_rules_skip_an_import_outside_the_rules_prefix
run_test test_cursor_rules_fail_on_an_index_entry_without_a_rule_file
run_test test_cursor_rule_without_a_description_omits_the_field
run_test test_build_cursor_script_adds_orchestration_only_with_teams
run_test test_build_cursor_script_writes_the_language_rule
run_test test_build_cursor_script_rejects_an_unknown_language
run_test test_cursor_mcp_registration_keeps_the_servers_already_there
run_test test_cursor_mcp_registration_records_args_and_env
