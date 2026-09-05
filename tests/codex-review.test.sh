#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS_SOURCE="$ROOT/codex-review/skills"

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
}

# A failing assertion inside a test function does not abort it: `set -e` is
# suppressed for functions called from an `if` condition, which is how run_test
# invokes them. Every assertion therefore reports through its own exit status.
assert_contains() {
  local haystack="$1" needle="$2"
  printf '%s' "$haystack" | grep -F -- "$needle" >/dev/null
}

test_review_skills_are_copied_when_requested() {
  sandbox

  install_codex_review_skills 1 "$SKILLS_SOURCE" "$TMP_ROOT/skills" >/dev/null

  cmp -s "$SKILLS_SOURCE/code-review/SKILL.md" "$TMP_ROOT/skills/code-review/SKILL.md" || return 1
  cmp -s "$SKILLS_SOURCE/codex-cli-review/scripts/codex_review.py" \
    "$TMP_ROOT/skills/codex-cli-review/scripts/codex_review.py"
}

test_review_skills_are_removed_when_not_requested() {
  sandbox
  install_codex_review_skills 1 "$SKILLS_SOURCE" "$TMP_ROOT/skills" >/dev/null

  install_codex_review_skills 0 "$SKILLS_SOURCE" "$TMP_ROOT/skills" >/dev/null

  [[ ! -e "$TMP_ROOT/skills/code-review" ]] || return 1
  [[ ! -e "$TMP_ROOT/skills/codex-cli-review" ]]
}

write_functions() {
  local path="$1" count="$2" name="$3" line
  mkdir -p "$(dirname "$path")"
  for line in $(seq 1 "$count"); do
    printf 'def %s_%s():\n    return None\n' "$name" "$line" >> "$path"
  done
}

write_list_entries() {
  local path="$1" count="$2" line
  mkdir -p "$(dirname "$path")"
  for line in $(seq 1 "$count"); do
    printf -- '- item %s\n' "$line" >> "$path"
  done
}

write_dash_comments() {
  local path="$1" count="$2" line
  mkdir -p "$(dirname "$path")"
  for line in $(seq 1 "$count"); do
    printf -- '-- comment %s\n' "$line" >> "$path"
  done
}

HOOK_SKILL_SCRIPT_DIR=".claude/skills/codex-cli-review/scripts"

# A git working copy with one staged file, a stub review script where the hook
# expects the installed codex-cli-review skill, and a codex stand-in that
# records any call, so a pass writing to the working copy would show up.
# The staged file is large enough to clear the hook's line floor; a test that
# wants the floor to bite stages a smaller one over it.
hook_sandbox() {
  local staged="${1:-service.py}"
  sandbox
  mkdir -p "$TMP_ROOT/bin" "$TMP_ROOT/home/$HOOK_SKILL_SCRIPT_DIR" "$TMP_ROOT/repo"

  cat > "$TMP_ROOT/home/$HOOK_SKILL_SCRIPT_DIR/codex_review.py" <<EOF
import pathlib
import sys

arguments = sys.argv[1:]
scope = pathlib.Path(arguments[arguments.index("--scope-file") + 1]).read_text()
pathlib.Path("$TMP_ROOT/review-call").write_text(" ".join(arguments) + "\n" + scope)
print('{"findings": [], "summary": "STUB REVIEW", "residual_risks": [], "tests_not_run": []}')
EOF

  cat > "$TMP_ROOT/bin/codex" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$TMP_ROOT/codex-call"
EOF
  chmod +x "$TMP_ROOT/bin/codex"

  git -C "$TMP_ROOT/repo" init -q
  write_functions "$TMP_ROOT/repo/$staged" 12 charge
  git -C "$TMP_ROOT/repo" add "$staged"
}

# Index and tracked content of the sandbox repository — what a pass writing to
# the working copy would move.
repo_state() {
  git -C "$TMP_ROOT/repo" status --porcelain
  git -C "$TMP_ROOT/repo" diff --cached
  git -C "$TMP_ROOT/repo" diff
}

# Any argument is passed to `env`, so a test can set the hook's knobs.
run_hook() {
  printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m wip"},"cwd":"%s"}' "$TMP_ROOT/repo" \
    | HOME="$TMP_ROOT/home" PATH="$TMP_ROOT/bin:$PATH" env "$@" bash "$ROOT/hooks/codex-commit-review.sh"
}

run_cursor_hook() {
  local command="${1:-git commit -m wip}"
  printf '{"command":"%s","cwd":"%s","hook_event_name":"beforeShellExecution"}' "$command" "$TMP_ROOT/repo" \
    | HOME="$TMP_ROOT/home" PATH="$TMP_ROOT/bin:$PATH" bash "$ROOT/hooks/cursor-commit-review.sh"
}

test_commit_review_reviews_the_staged_diff_through_the_skill_script() {
  hook_sandbox

  local output
  output="$(run_hook)" || return 1

  assert_contains "$(cat "$TMP_ROOT/review-call")" "service.py" || return 1
  assert_contains "$output" "STUB REVIEW"
}

test_commit_review_denies_the_commit_and_reports_the_review() {
  hook_sandbox

  local output
  output="$(run_hook)" || return 1

  [[ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision')" == "deny" ]] \
    && assert_contains "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason')" "STUB REVIEW"
}

test_commit_review_lets_the_retry_through() {
  hook_sandbox
  run_hook >/dev/null || return 1

  local output
  output="$(run_hook)" || return 1

  [[ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision')" == "allow" ]]
}

test_commit_review_leaves_the_working_copy_alone() {
  hook_sandbox
  local before
  before="$(repo_state)"

  run_hook >/dev/null || return 1

  [[ "$(repo_state)" == "$before" ]]
}

test_commit_review_spawns_no_second_codex_pass() {
  hook_sandbox

  run_hook >/dev/null || return 1

  [[ ! -e "$TMP_ROOT/codex-call" ]]
}

test_commit_review_allows_the_commit_when_the_retry_marker_cannot_be_stored() {
  hook_sandbox
  printf 'not a directory\n' > "$TMP_ROOT/home/.cache"

  local output
  output="$(run_hook)" || return 1

  [[ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision')" == "allow" ]] \
    && assert_contains "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')" "STUB REVIEW"
}

test_commit_review_allows_the_commit_when_the_review_script_is_absent() {
  hook_sandbox
  rm "$TMP_ROOT/home/$HOOK_SKILL_SCRIPT_DIR/codex_review.py"

  local output
  output="$(run_hook)" || return 1

  assert_contains "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision')" "allow" || return 1
  assert_contains "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason')" "review skipped" || return 1
  [[ ! -e "$TMP_ROOT/codex-call" ]]
}

test_review_skills_keep_a_same_name_skill_owned_by_the_user() {
  sandbox
  mkdir -p "$TMP_ROOT/skills/code-review"
  printf 'hand-rolled\n' > "$TMP_ROOT/skills/code-review/SKILL.md"

  install_codex_review_skills 0 "$SKILLS_SOURCE" "$TMP_ROOT/skills" >/dev/null

  assert_contains "$(cat "$TMP_ROOT/skills/code-review/SKILL.md")" "hand-rolled"
}

test_commit_review_finds_the_skill_installed_for_the_other_harnesses() {
  hook_sandbox
  mkdir -p "$TMP_ROOT/home/.agents/skills/codex-cli-review/scripts"
  mv "$TMP_ROOT/home/$HOOK_SKILL_SCRIPT_DIR/codex_review.py" \
    "$TMP_ROOT/home/.agents/skills/codex-cli-review/scripts/codex_review.py"

  local output
  output="$(run_hook)" || return 1

  assert_contains "$output" "STUB REVIEW"
}

test_cursor_commit_review_denies_the_commit_and_reports_the_review() {
  hook_sandbox

  local output
  output="$(run_cursor_hook)" || return 1

  [[ "$(printf '%s' "$output" | jq -r '.permission')" == "deny" ]] \
    && assert_contains "$(printf '%s' "$output" | jq -r '.agent_message')" "STUB REVIEW"
}

test_cursor_commit_review_lets_the_retry_through() {
  hook_sandbox
  run_cursor_hook >/dev/null || return 1

  local output
  output="$(run_cursor_hook)" || return 1

  [[ "$(printf '%s' "$output" | jq -r '.permission')" == "allow" ]]
}

test_cursor_commit_review_reviews_again_after_the_change_moves_on() {
  hook_sandbox
  run_cursor_hook >/dev/null || return 1
  printf 'def refund():\n    return None\n' >> "$TMP_ROOT/repo/service.py"
  git -C "$TMP_ROOT/repo" add service.py

  local output
  output="$(run_cursor_hook)" || return 1

  [[ "$(printf '%s' "$output" | jq -r '.permission')" == "deny" ]]
}

test_cursor_commit_review_ignores_a_command_that_is_not_a_commit() {
  hook_sandbox

  local output
  output="$(run_cursor_hook "git status")" || return 1

  [[ -z "$output" ]] \
    && [[ ! -e "$TMP_ROOT/codex-call" ]]
}

test_cursor_commit_review_allows_the_commit_when_the_review_script_is_absent() {
  hook_sandbox
  rm "$TMP_ROOT/home/$HOOK_SKILL_SCRIPT_DIR/codex_review.py"

  local output
  output="$(run_cursor_hook)" || return 1

  [[ "$(printf '%s' "$output" | jq -r '.permission')" == "allow" ]] \
    && assert_contains "$(printf '%s' "$output" | jq -r '.user_message')" "review skipped" \
    && [[ ! -e "$TMP_ROOT/codex-call" ]]
}

test_review_home_carries_only_the_review_scoped_rules() {
  sandbox

  install_codex_review_home 1 "$ROOT" "$TMP_ROOT/review-home" "$TMP_ROOT/codex" >/dev/null

  local instructions
  instructions="$(cat "$TMP_ROOT/review-home/AGENTS.md")"
  assert_contains "$instructions" "Naming Conventions" || return 1
  assert_contains "$instructions" "Self-Review Checklist" || return 1
  ! assert_contains "$instructions" "Development Workflow" || return 1
  ! assert_contains "$instructions" "Delegation is a default execution mode"
}

test_review_home_drops_the_interactive_extras() {
  sandbox

  install_codex_review_home 1 "$ROOT" "$TMP_ROOT/review-home" "$TMP_ROOT/codex" >/dev/null

  local config
  config="$(cat "$TMP_ROOT/review-home/config.toml")"
  assert_contains "$config" "web_search = false" || return 1
  assert_contains "$config" "model_reasoning_effort" || return 1
  ! assert_contains "$config" "mcp_servers"
}

test_review_home_shares_the_operator_login() {
  sandbox

  install_codex_review_home 1 "$ROOT" "$TMP_ROOT/review-home" "$TMP_ROOT/codex" >/dev/null

  [[ -L "$TMP_ROOT/review-home/auth.json" ]] \
    && [[ "$(readlink "$TMP_ROOT/review-home/auth.json")" == "$TMP_ROOT/codex/auth.json" ]]
}

test_review_home_is_skipped_when_the_operator_selects_a_provider() {
  sandbox
  mkdir -p "$TMP_ROOT/codex"
  install_codex_review_home 1 "$ROOT" "$TMP_ROOT/review-home" "$TMP_ROOT/codex" >/dev/null
  printf 'model_provider = "azure"\n' > "$TMP_ROOT/codex/config.toml"

  install_codex_review_home 1 "$ROOT" "$TMP_ROOT/review-home" "$TMP_ROOT/codex" >/dev/null

  [[ ! -e "$TMP_ROOT/review-home" ]]
}

test_review_home_is_removed_when_not_requested() {
  sandbox
  install_codex_review_home 1 "$ROOT" "$TMP_ROOT/review-home" "$TMP_ROOT/codex" >/dev/null

  install_codex_review_home 0 "$ROOT" "$TMP_ROOT/review-home" "$TMP_ROOT/codex" >/dev/null

  [[ ! -e "$TMP_ROOT/review-home" ]]
}

test_commit_review_skips_a_documentation_only_change() {
  hook_sandbox docs/guide.md

  local output
  output="$(run_hook)" || return 1

  [[ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision')" == "allow" ]] \
    && [[ ! -e "$TMP_ROOT/review-call" ]]
}

test_commit_review_reviews_documentation_when_the_path_gate_is_empty() {
  hook_sandbox docs/guide.md

  run_hook CODEX_REVIEW_SKIP_PATHS= >/dev/null || return 1

  assert_contains "$(cat "$TMP_ROOT/review-call")" "docs/guide.md"
}

test_commit_review_skips_a_change_below_the_line_floor() {
  hook_sandbox
  printf 'def charge():\n    return None\n' > "$TMP_ROOT/repo/service.py"
  git -C "$TMP_ROOT/repo" add service.py

  local output
  output="$(run_hook)" || return 1

  [[ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision')" == "allow" ]] \
    && [[ ! -e "$TMP_ROOT/review-call" ]]
}

test_commit_review_counts_a_new_untracked_directory_against_the_line_floor() {
  hook_sandbox
  git -C "$TMP_ROOT/repo" reset -q
  rm -f "$TMP_ROOT/repo/service.py"
  write_functions "$TMP_ROOT/repo/feature/refund.py" 12 refund

  run_hook >/dev/null || return 1

  assert_contains "$(cat "$TMP_ROOT/review-call")" "feature/"
}

test_commit_review_reviews_again_after_an_edit_past_the_scope_cap() {
  hook_sandbox
  write_functions "$TMP_ROOT/repo/refund.py" 12 refund
  git -C "$TMP_ROOT/repo" add refund.py
  run_hook CODEX_REVIEW_MAX_SCOPE_BYTES=200 >/dev/null || return 1
  # Same length, same status, changed only in the part the scope cut away. The
  # diff is ordered by path, so service.py and its blob hash sit past the cap.
  sed -i.bak 's/def charge_12()/def rebate_12()/' "$TMP_ROOT/repo/service.py"
  rm -f "$TMP_ROOT/repo/service.py.bak"
  git -C "$TMP_ROOT/repo" add service.py

  local output
  output="$(run_hook CODEX_REVIEW_MAX_SCOPE_BYTES=200)" || return 1

  [[ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision')" == "deny" ]]
}

test_commit_review_truncates_a_scope_over_the_cap() {
  hook_sandbox

  run_hook CODEX_REVIEW_MAX_SCOPE_BYTES=200 >/dev/null || return 1

  local scope
  scope="$(cat "$TMP_ROOT/review-call")"
  assert_contains "$scope" "truncated" || return 1
  [[ "$(printf '%s' "$scope" | wc -c)" -lt 2000 ]]
}

test_commit_review_keeps_a_truncated_scope_readable_as_utf8() {
  hook_sandbox
  printf 'def refund():\n    """Возврат платежа, полностью на кириллице."""\n' \
    >> "$TMP_ROOT/repo/service.py"
  git -C "$TMP_ROOT/repo" add service.py

  # 564 bytes into this diff is the middle of a two-byte character.
  run_hook CODEX_REVIEW_MAX_SCOPE_BYTES=564 >/dev/null || return 1

  python3 -c 'import pathlib, sys; pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")' \
    "$TMP_ROOT/review-call"
}

test_commit_review_counts_an_untracked_path_with_a_space() {
  hook_sandbox
  git -C "$TMP_ROOT/repo" reset -q
  rm -f "$TMP_ROOT/repo/service.py"
  write_functions "$TMP_ROOT/repo/new feature/refund.py" 12 refund

  run_hook >/dev/null || return 1

  assert_contains "$(cat "$TMP_ROOT/review-call")" "new feature"
}

test_commit_review_reviews_a_dependency_manifest() {
  hook_sandbox requirements.txt

  run_hook >/dev/null || return 1

  assert_contains "$(cat "$TMP_ROOT/review-call")" "requirements.txt"
}

test_commit_review_counts_a_changed_line_that_starts_with_a_dash() {
  hook_sandbox
  git -C "$TMP_ROOT/repo" reset -q
  rm -f "$TMP_ROOT/repo/service.py"
  git -C "$TMP_ROOT/repo" commit -q --allow-empty -m base
  write_list_entries "$TMP_ROOT/repo/values.yaml" 12
  git -C "$TMP_ROOT/repo" add values.yaml

  run_hook >/dev/null || return 1

  assert_contains "$(cat "$TMP_ROOT/review-call")" "values.yaml"
}

test_commit_review_reviews_a_rename_out_of_a_reviewed_path() {
  hook_sandbox
  git -C "$TMP_ROOT/repo" commit -q -m base
  git -C "$TMP_ROOT/repo" mv service.py notes.md

  run_hook >/dev/null || return 1

  assert_contains "$(cat "$TMP_ROOT/review-call")" "service.py"
}

test_commit_review_skips_a_documentation_path_with_a_space() {
  hook_sandbox "docs/user guide.md"

  local output
  output="$(run_hook)" || return 1

  [[ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision')" == "allow" ]] \
    && [[ ! -e "$TMP_ROOT/review-call" ]]
}

test_commit_review_counts_a_removed_line_that_starts_with_two_dashes() {
  hook_sandbox
  write_dash_comments "$TMP_ROOT/repo/schema.sql" 12
  git -C "$TMP_ROOT/repo" add schema.sql
  git -C "$TMP_ROOT/repo" commit -q -m base
  : > "$TMP_ROOT/repo/schema.sql"
  git -C "$TMP_ROOT/repo" add schema.sql

  run_hook >/dev/null || return 1

  assert_contains "$(cat "$TMP_ROOT/review-call")" "schema.sql"
}

test_commit_review_skips_a_new_directory_of_documentation() {
  hook_sandbox
  git -C "$TMP_ROOT/repo" reset -q
  rm -f "$TMP_ROOT/repo/service.py"
  mkdir -p "$TMP_ROOT/repo/docs"
  write_dash_comments "$TMP_ROOT/repo/docs/guide.md" 12
  write_dash_comments "$TMP_ROOT/repo/docs/design.md" 12

  local output
  output="$(run_hook)" || return 1

  [[ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision')" == "allow" ]] \
    && [[ ! -e "$TMP_ROOT/review-call" ]]
}

test_commit_review_skips_a_new_directory_whose_code_is_ignored() {
  hook_sandbox
  git -C "$TMP_ROOT/repo" reset -q
  rm -f "$TMP_ROOT/repo/service.py"
  printf 'vendor/\n' > "$TMP_ROOT/repo/.gitignore"
  git -C "$TMP_ROOT/repo" add .gitignore
  git -C "$TMP_ROOT/repo" commit -q -m base
  write_dash_comments "$TMP_ROOT/repo/docs/guide.md" 12
  write_functions "$TMP_ROOT/repo/docs/vendor/lib.py" 30 charge

  local output
  output="$(run_hook)" || return 1

  [[ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision')" == "allow" ]] \
    && [[ ! -e "$TMP_ROOT/review-call" ]]
}

test_commit_review_reviews_a_mode_change() {
  hook_sandbox
  git -C "$TMP_ROOT/repo" commit -q -m base
  chmod +x "$TMP_ROOT/repo/service.py"
  git -C "$TMP_ROOT/repo" add service.py

  run_hook >/dev/null || return 1

  assert_contains "$(cat "$TMP_ROOT/review-call")" "service.py"
}

test_commit_review_reviews_a_replaced_binary() {
  hook_sandbox
  printf 'a\000b\n' > "$TMP_ROOT/repo/logo.bin"
  git -C "$TMP_ROOT/repo" add logo.bin
  git -C "$TMP_ROOT/repo" commit -q -m base
  printf 'c\000d\n' > "$TMP_ROOT/repo/logo.bin"
  git -C "$TMP_ROOT/repo" add logo.bin

  run_hook >/dev/null || return 1

  assert_contains "$(cat "$TMP_ROOT/review-call")" "logo.bin"
}

test_commit_review_counts_changed_lines_when_the_vcs_colours_its_diff() {
  hook_sandbox
  git -C "$TMP_ROOT/repo" config color.ui always

  run_hook >/dev/null || return 1

  assert_contains "$(cat "$TMP_ROOT/review-call")" "service.py"
}

test_commit_review_counts_an_untracked_last_line_without_a_newline() {
  hook_sandbox
  git -C "$TMP_ROOT/repo" reset -q
  rm -f "$TMP_ROOT/repo/service.py"
  write_functions "$TMP_ROOT/repo/late.py" 4 charge
  printf 'def charge_5():' >> "$TMP_ROOT/repo/late.py"

  local output
  output="$(run_hook CODEX_REVIEW_MIN_LINES=9)" || return 1

  [[ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision')" == "deny" ]]
}

test_commit_review_reviews_a_coloured_rename() {
  hook_sandbox
  git -C "$TMP_ROOT/repo" commit -q -m base
  git -C "$TMP_ROOT/repo" config color.ui always
  git -C "$TMP_ROOT/repo" mv service.py notes.md

  run_hook >/dev/null || return 1

  assert_contains "$(cat "$TMP_ROOT/review-call")" "service.py"
}

test_commit_review_hands_over_an_escape_sequence_in_the_change() {
  hook_sandbox
  printf 'BANNER = "\033[31mred\033[0m"\n' >> "$TMP_ROOT/repo/service.py"
  git -C "$TMP_ROOT/repo" add service.py

  run_hook >/dev/null || return 1

  grep -q $'\033\[31m' "$TMP_ROOT/review-call"
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

run_test test_review_home_carries_only_the_review_scoped_rules
run_test test_review_home_drops_the_interactive_extras
run_test test_review_home_shares_the_operator_login
run_test test_review_home_is_skipped_when_the_operator_selects_a_provider
run_test test_review_home_is_removed_when_not_requested
run_test test_review_skills_are_copied_when_requested
run_test test_review_skills_are_removed_when_not_requested
run_test test_review_skills_keep_a_same_name_skill_owned_by_the_user
run_test test_commit_review_reviews_the_staged_diff_through_the_skill_script
run_test test_commit_review_denies_the_commit_and_reports_the_review
run_test test_commit_review_lets_the_retry_through
run_test test_commit_review_leaves_the_working_copy_alone
run_test test_commit_review_spawns_no_second_codex_pass
run_test test_commit_review_skips_a_documentation_only_change
run_test test_commit_review_reviews_documentation_when_the_path_gate_is_empty
run_test test_commit_review_skips_a_change_below_the_line_floor
run_test test_commit_review_counts_a_new_untracked_directory_against_the_line_floor
run_test test_commit_review_reviews_again_after_an_edit_past_the_scope_cap
run_test test_commit_review_truncates_a_scope_over_the_cap
run_test test_commit_review_keeps_a_truncated_scope_readable_as_utf8
run_test test_commit_review_counts_an_untracked_path_with_a_space
run_test test_commit_review_reviews_a_dependency_manifest
run_test test_commit_review_counts_changed_lines_when_the_vcs_colours_its_diff
run_test test_commit_review_reviews_a_coloured_rename
run_test test_commit_review_hands_over_an_escape_sequence_in_the_change
run_test test_commit_review_counts_an_untracked_last_line_without_a_newline
run_test test_commit_review_counts_a_changed_line_that_starts_with_a_dash
run_test test_commit_review_counts_a_removed_line_that_starts_with_two_dashes
run_test test_commit_review_skips_a_new_directory_of_documentation
run_test test_commit_review_skips_a_new_directory_whose_code_is_ignored
run_test test_commit_review_reviews_a_rename_out_of_a_reviewed_path
run_test test_commit_review_reviews_a_mode_change
run_test test_commit_review_reviews_a_replaced_binary
run_test test_commit_review_skips_a_documentation_path_with_a_space
run_test test_commit_review_allows_the_commit_when_the_retry_marker_cannot_be_stored
run_test test_commit_review_allows_the_commit_when_the_review_script_is_absent
run_test test_commit_review_finds_the_skill_installed_for_the_other_harnesses
run_test test_cursor_commit_review_denies_the_commit_and_reports_the_review
run_test test_cursor_commit_review_lets_the_retry_through
run_test test_cursor_commit_review_reviews_again_after_the_change_moves_on
run_test test_cursor_commit_review_ignores_a_command_that_is_not_a_commit
run_test test_cursor_commit_review_allows_the_commit_when_the_review_script_is_absent
