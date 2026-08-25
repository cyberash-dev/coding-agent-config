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
  SETTINGS="$TMP_ROOT/claude/settings.json"
  SETTINGS_BACKED_UP=0
  CURSOR_HOOKS="$TMP_ROOT/cursor/hooks.json"
  CURSOR_HOOKS_BACKED_UP=0
}

assert_contains() {
  local haystack="$1" needle="$2"
  printf '%s' "$haystack" | grep -F -- "$needle" >/dev/null
}

test_claude_hook_is_registered_with_its_matcher() {
  sandbox

  install_hook "$TMP_ROOT/hooks/code-navigation-reminder.sh" "Grep|Read" "PreToolUse" >/dev/null

  local entry
  entry="$(jq -c '.hooks.PreToolUse[0]' "$SETTINGS")"
  [[ "$(printf '%s' "$entry" | jq -r '.matcher')" == "Grep|Read" ]] \
    && [[ "$(printf '%s' "$entry" | jq -r '.hooks[0].command')" \
          == "$TMP_ROOT/hooks/code-navigation-reminder.sh" ]] \
    && [[ "$(printf '%s' "$entry" | jq -r '.hooks[0].type')" == "command" ]]
}

test_claude_hook_registration_leaves_the_file_alone_when_already_registered() {
  sandbox
  install_hook "$TMP_ROOT/hooks/code-navigation-reminder.sh" "Grep|Read" "PreToolUse" >/dev/null
  install_hook "$TMP_ROOT/hooks/codex-commit-review.sh" "Bash" "PreToolUse" >/dev/null
  local before
  before="$(cat "$SETTINGS")"

  install_hook "$TMP_ROOT/hooks/code-navigation-reminder.sh" "Grep|Read" "PreToolUse" >/dev/null
  install_hook "$TMP_ROOT/hooks/codex-commit-review.sh" "Bash" "PreToolUse" >/dev/null

  [[ "$(cat "$SETTINGS")" == "$before" ]]
}

test_claude_hook_registration_keeps_a_hook_the_user_added() {
  sandbox
  mkdir -p "$(dirname "$SETTINGS")"
  printf '%s' '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"/opt/mine.sh"}]}]}}' > "$SETTINGS"

  install_hook "$TMP_ROOT/hooks/code-navigation-reminder.sh" "Grep|Read" "PreToolUse" >/dev/null

  assert_contains "$(cat "$SETTINGS")" "/opt/mine.sh"
}

test_claude_hook_is_removed_on_request() {
  sandbox
  install_hook "$TMP_ROOT/hooks/code-navigation-reminder.sh" "Grep|Read" "PreToolUse" >/dev/null

  remove_hook "code-navigation-reminder.sh" "PreToolUse" >/dev/null

  [[ "$(jq '.hooks.PreToolUse | length' "$SETTINGS")" == "0" ]]
}

test_cursor_hook_is_registered_with_the_schema_version() {
  sandbox

  install_cursor_hook "$TMP_ROOT/hooks/cursor-commit-review.sh" "beforeShellExecution" >/dev/null

  local written
  written="$(cat "$CURSOR_HOOKS")"
  [[ "$(printf '%s' "$written" | jq -r '.version')" == "1" ]] \
    && [[ "$(printf '%s' "$written" | jq -r '.hooks.beforeShellExecution[0].command')" \
          == "$TMP_ROOT/hooks/cursor-commit-review.sh" ]]
}

test_cursor_hook_registration_does_not_duplicate_itself() {
  sandbox
  install_cursor_hook "$TMP_ROOT/hooks/cursor-commit-review.sh" "beforeShellExecution" >/dev/null

  install_cursor_hook "$TMP_ROOT/hooks/cursor-commit-review.sh" "beforeShellExecution" >/dev/null

  [[ "$(jq '.hooks.beforeShellExecution | length' "$CURSOR_HOOKS")" == "1" ]]
}

test_cursor_hook_registration_keeps_a_hook_the_user_added() {
  sandbox
  mkdir -p "$(dirname "$CURSOR_HOOKS")"
  printf '%s' '{"version":1,"hooks":{"beforeShellExecution":[{"command":"/opt/mine.sh"}]}}' > "$CURSOR_HOOKS"

  install_cursor_hook "$TMP_ROOT/hooks/cursor-commit-review.sh" "beforeShellExecution" >/dev/null

  assert_contains "$(cat "$CURSOR_HOOKS")" "/opt/mine.sh"
}

test_cursor_hook_is_removed_on_request() {
  sandbox
  install_cursor_hook "$TMP_ROOT/hooks/cursor-commit-review.sh" "beforeShellExecution" >/dev/null

  remove_cursor_hook "cursor-commit-review.sh" "beforeShellExecution" >/dev/null

  [[ "$(jq '.hooks.beforeShellExecution | length' "$CURSOR_HOOKS")" == "0" ]]
}

test_cursor_hook_registration_leaves_the_file_alone_when_already_registered() {
  sandbox
  install_cursor_hook "$TMP_ROOT/hooks/cursor-commit-review.sh" "beforeShellExecution" >/dev/null
  local before
  before="$(cat "$CURSOR_HOOKS")"

  install_cursor_hook "$TMP_ROOT/hooks/cursor-commit-review.sh" "beforeShellExecution" >/dev/null

  [[ "$(cat "$CURSOR_HOOKS")" == "$before" ]]
}

test_claude_hook_moves_off_an_event_it_no_longer_belongs_to() {
  sandbox
  mkdir -p "$(dirname "$SETTINGS")"
  printf '%s' '{"hooks":{"PostToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"HOOKS/code-navigation-reminder.sh"}]}]}}' \
    | sed "s|HOOKS|$TMP_ROOT/hooks|" > "$SETTINGS"

  install_hook "$TMP_ROOT/hooks/code-navigation-reminder.sh" "Grep|Read" "PreToolUse" >/dev/null

  [[ "$(jq '.hooks.PostToolUse | length' "$SETTINGS")" == "0" ]] \
    && [[ "$(jq '.hooks.PreToolUse | length' "$SETTINGS")" == "1" ]]
}

test_claude_hook_keeps_a_same_name_hook_the_user_owns() {
  sandbox
  mkdir -p "$(dirname "$SETTINGS")"
  printf '%s' '{"hooks":{"PreToolUse":[{"matcher":"Grep","hooks":[{"type":"command","command":"/my/own/code-navigation-reminder.sh"}]}]}}' > "$SETTINGS"

  local output
  output="$(install_hook "$TMP_ROOT/hooks/code-navigation-reminder.sh" "Grep|Read" "PreToolUse" 2>&1)"

  assert_contains "$(cat "$SETTINGS")" "/my/own/code-navigation-reminder.sh" \
    && assert_contains "$(cat "$SETTINGS")" "$TMP_ROOT/hooks/code-navigation-reminder.sh" \
    && assert_contains "$output" "also registers code-navigation-reminder.sh"
}

test_claude_hook_collapses_repeats_keeping_the_latest_registration() {
  sandbox
  mkdir -p "$(dirname "$SETTINGS")"
  printf '%s' '{"hooks":{"PreToolUse":[
    {"matcher":"Edit|Write|MultiEdit","hooks":[{"type":"command","command":"/sdd/lint.sh"}]},
    {"matcher":"Edit|Write","hooks":[{"type":"command","command":"/sdd/lint.sh"}]}]}}' > "$SETTINGS"

  install_hook "$TMP_ROOT/hooks/code-navigation-reminder.sh" "Grep|Read" "PreToolUse" >/dev/null

  [[ "$(jq '[.hooks.PreToolUse[].hooks[].command | select(. == "/sdd/lint.sh")] | length' "$SETTINGS")" == "1" ]] \
    && assert_contains "$(jq -r '.hooks.PreToolUse[0].matcher' "$SETTINGS")" "Edit|Write"
}

test_claude_hook_removal_leaves_a_same_name_hook_the_user_owns() {
  sandbox
  mkdir -p "$(dirname "$SETTINGS")"
  printf '%s' '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"/my/own/codex-commit-review.sh"}]}]}}' > "$SETTINGS"

  remove_hook "$TMP_ROOT/hooks/codex-commit-review.sh" "PreToolUse" >/dev/null

  assert_contains "$(cat "$SETTINGS")" "/my/own/codex-commit-review.sh"
}

test_cursor_hook_moves_off_an_event_it_no_longer_belongs_to() {
  sandbox
  mkdir -p "$(dirname "$CURSOR_HOOKS")"
  printf '%s' '{"version":1,"hooks":{"afterShellExecution":[{"command":"HOOKS/cursor-commit-review.sh"}]}}' \
    | sed "s|HOOKS|$TMP_ROOT/hooks|" > "$CURSOR_HOOKS"

  install_cursor_hook "$TMP_ROOT/hooks/cursor-commit-review.sh" "beforeShellExecution" >/dev/null

  [[ "$(jq '.hooks.afterShellExecution | length' "$CURSOR_HOOKS")" == "0" ]] \
    && [[ "$(jq '.hooks.beforeShellExecution | length' "$CURSOR_HOOKS")" == "1" ]]
}

test_cursor_hook_collapses_repeats_of_one_script_in_the_event() {
  sandbox
  mkdir -p "$(dirname "$CURSOR_HOOKS")"
  printf '%s' '{"version":1,"hooks":{"beforeShellExecution":[{"command":"/other/guard.sh"},{"command":"/other/guard.sh","matcher":"git"}]}}' > "$CURSOR_HOOKS"

  install_cursor_hook "$TMP_ROOT/hooks/cursor-commit-review.sh" "beforeShellExecution" >/dev/null

  [[ "$(jq '[.hooks.beforeShellExecution[].command | select(. == "/other/guard.sh")] | length' "$CURSOR_HOOKS")" == "1" ]]
}

test_cursor_hook_keeps_a_same_name_hook_the_user_owns() {
  sandbox
  mkdir -p "$(dirname "$CURSOR_HOOKS")"
  printf '%s' '{"version":1,"hooks":{"beforeShellExecution":[{"command":"/my/own/cursor-commit-review.sh"}]}}' > "$CURSOR_HOOKS"

  local output
  output="$(install_cursor_hook "$TMP_ROOT/hooks/cursor-commit-review.sh" "beforeShellExecution" 2>&1)"

  assert_contains "$(cat "$CURSOR_HOOKS")" "/my/own/cursor-commit-review.sh" \
    && assert_contains "$output" "also registers cursor-commit-review.sh"
}

test_dedupe_hooks_collapses_repeats_left_by_another_tool() {
  sandbox
  mkdir -p "$(dirname "$SETTINGS")"
  printf '%s' '{"hooks":{"PreToolUse":[
    {"matcher":"Edit|Write|MultiEdit","hooks":[{"type":"command","command":"/sdd/lint.sh"}]},
    {"matcher":"Grep","hooks":[{"type":"command","command":"/other/guard.sh"}]},
    {"matcher":"Edit|Write","hooks":[{"type":"command","command":"/sdd/lint.sh"}]}]}}' > "$SETTINGS"

  dedupe_hooks >/dev/null

  [[ "$(jq '.hooks.PreToolUse | length' "$SETTINGS")" == "2" ]] \
    && [[ "$(jq -r '.hooks.PreToolUse[-1].matcher' "$SETTINGS")" == "Edit|Write" ]] \
    && assert_contains "$(cat "$SETTINGS")" "/other/guard.sh"
}

test_dedupe_hooks_leaves_a_clean_file_untouched() {
  sandbox
  install_hook "$TMP_ROOT/hooks/code-navigation-reminder.sh" "Grep|Read" "PreToolUse" >/dev/null
  local before
  before="$(cat "$SETTINGS")"

  dedupe_hooks >/dev/null

  [[ "$(cat "$SETTINGS")" == "$before" ]]
}

test_dedupe_cursor_hooks_collapses_repeats() {
  sandbox
  mkdir -p "$(dirname "$CURSOR_HOOKS")"
  printf '%s' '{"version":1,"hooks":{"beforeShellExecution":[{"command":"/a.sh"},{"command":"/b.sh"},{"command":"/a.sh","matcher":"git"}]}}' > "$CURSOR_HOOKS"

  dedupe_cursor_hooks >/dev/null

  [[ "$(jq '.hooks.beforeShellExecution | length' "$CURSOR_HOOKS")" == "2" ]]
}

test_claude_hook_keeps_the_file_formatting_when_the_entry_is_there() {
  sandbox
  mkdir -p "$(dirname "$SETTINGS")"
  printf '%s' '{"hooks":{"PreToolUse":[{"matcher":"Grep|Read","hooks":[{"type":"command","command":"HOOKS/code-navigation-reminder.sh"}]}]}}' \
    | sed "s|HOOKS|$TMP_ROOT/hooks|" > "$SETTINGS"
  local before
  before="$(cat "$SETTINGS")"

  install_hook "$TMP_ROOT/hooks/code-navigation-reminder.sh" "Grep|Read" "PreToolUse" >/dev/null

  [[ "$(cat "$SETTINGS")" == "$before" ]]
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

run_test test_claude_hook_is_registered_with_its_matcher
run_test test_claude_hook_registration_leaves_the_file_alone_when_already_registered
run_test test_claude_hook_registration_keeps_a_hook_the_user_added
run_test test_claude_hook_is_removed_on_request
run_test test_cursor_hook_is_registered_with_the_schema_version
run_test test_cursor_hook_registration_does_not_duplicate_itself
run_test test_cursor_hook_registration_keeps_a_hook_the_user_added
run_test test_cursor_hook_is_removed_on_request
run_test test_cursor_hook_registration_leaves_the_file_alone_when_already_registered
run_test test_claude_hook_moves_off_an_event_it_no_longer_belongs_to
run_test test_claude_hook_keeps_a_same_name_hook_the_user_owns
run_test test_claude_hook_collapses_repeats_keeping_the_latest_registration
run_test test_claude_hook_removal_leaves_a_same_name_hook_the_user_owns
run_test test_cursor_hook_moves_off_an_event_it_no_longer_belongs_to
run_test test_cursor_hook_collapses_repeats_of_one_script_in_the_event
run_test test_cursor_hook_keeps_a_same_name_hook_the_user_owns
run_test test_dedupe_hooks_collapses_repeats_left_by_another_tool
run_test test_dedupe_hooks_leaves_a_clean_file_untouched
run_test test_dedupe_cursor_hooks_collapses_repeats
run_test test_claude_hook_keeps_the_file_formatting_when_the_entry_is_there
