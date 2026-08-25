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

HOOK_SKILL_SCRIPT_DIR=".claude/skills/codex-cli-review/scripts"

# A git working copy with one staged file, a stub review script where the hook
# expects the installed codex-cli-review skill, and a codex stand-in for the
# fix pass that records the environment it was called with.
hook_sandbox() {
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
printf 'CODE_REVIEW_HOOK_ACTIVE=%s\n' "\${CODE_REVIEW_HOOK_ACTIVE:-unset}" >> "$TMP_ROOT/codex-call"
cat >> "$TMP_ROOT/codex-call"
printf 'APPLIED: nothing\nSKIPPED: nothing\n'
EOF
  chmod +x "$TMP_ROOT/bin/codex"

  git -C "$TMP_ROOT/repo" init -q
  printf 'def charge():\n    return None\n' > "$TMP_ROOT/repo/service.py"
  git -C "$TMP_ROOT/repo" add service.py
}

run_hook() {
  printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m wip"},"cwd":"%s"}' "$TMP_ROOT/repo" \
    | HOME="$TMP_ROOT/home" PATH="$TMP_ROOT/bin:$PATH" bash "$ROOT/hooks/codex-commit-review.sh"
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

test_commit_review_keeps_the_fix_pass_from_starting_a_nested_review() {
  hook_sandbox

  run_hook >/dev/null || return 1

  assert_contains "$(cat "$TMP_ROOT/codex-call")" "CODE_REVIEW_HOOK_ACTIVE=1"
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

run_test() {
  local name="$1"
  if "$name"; then
    printf 'ok - %s\n' "$name"
  else
    printf 'not ok - %s\n' "$name" >&2
    exit 1
  fi
}

run_test test_review_skills_are_copied_when_requested
run_test test_review_skills_are_removed_when_not_requested
run_test test_review_skills_keep_a_same_name_skill_owned_by_the_user
run_test test_commit_review_reviews_the_staged_diff_through_the_skill_script
run_test test_commit_review_keeps_the_fix_pass_from_starting_a_nested_review
run_test test_commit_review_allows_the_commit_when_the_review_script_is_absent
run_test test_commit_review_finds_the_skill_installed_for_the_other_harnesses
run_test test_cursor_commit_review_denies_the_commit_and_reports_the_review
run_test test_cursor_commit_review_lets_the_retry_through
run_test test_cursor_commit_review_reviews_again_after_the_change_moves_on
run_test test_cursor_commit_review_ignores_a_command_that_is_not_a_commit
run_test test_cursor_commit_review_allows_the_commit_when_the_review_script_is_absent
