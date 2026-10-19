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
  AGENT_HOME="$TMP_ROOT/home"
  DSH_HOME="$TMP_ROOT/home/.dsh"
  mkdir -p "$DSH_HOME" "$AGENT_HOME"
  printf 'body\n' > "$DSH_HOME/AGENTS.md"
  # A code-skeleton bin the MCP row can point at.
  mkdir -p "$TMP_ROOT/bin"
  printf '#!/usr/bin/env bash\n' > "$TMP_ROOT/bin/code-skeleton-mcp"
  chmod +x "$TMP_ROOT/bin/code-skeleton-mcp"
}

with_skeleton_bin() {
  PATH="$TMP_ROOT/bin:$PATH"
}

assert_contains() {
  local haystack="$1" needle="$2"
  printf '%s' "$haystack" | grep -F -- "$needle" >/dev/null
}

assert_lacks() {
  local haystack="$1" needle="$2"
  ! printf '%s' "$haystack" | grep -F -- "$needle" >/dev/null
}

test_deepseek_patch_is_created_when_missing() {
  sandbox
  PATH="$TMP_ROOT/bin:$PATH" install_deepseek_profile_rows "$ROOT" 196608 0 0 >/dev/null

  [[ -f "$DSH_HOME/cordis.patch.yml" ]] \
    && assert_contains "$(cat "$DSH_HOME/cordis.patch.yml")" "# managed rows start: # coding-agent-config"
}

test_deepseek_mcp_row_mounts_the_client() {
  sandbox
  PATH="$TMP_ROOT/bin:$PATH" install_deepseek_profile_rows "$ROOT" 196608 0 0 >/dev/null
  local written
  written="$(cat "$DSH_HOME/cordis.patch.yml")"

  assert_contains "$written" "id: mcp-code-skeleton" \
    && assert_contains "$written" "name: '@deepseek-ai/dsh-mcp-client'" \
    && assert_contains "$written" "serverName: code-skeleton" \
    && assert_contains "$written" "command: \"$TMP_ROOT/bin/code-skeleton-mcp\""
}

test_deepseek_mcp_row_is_skipped_without_the_bin() {
  sandbox
  local written
  written="$(PATH="/usr/bin:/bin" install_deepseek_profile_rows "$ROOT" 196608 0 0 2>/dev/null || true)"
  written="$(cat "$DSH_HOME/cordis.patch.yml" 2>/dev/null || true)"

  assert_lacks "$written" "mcp-code-skeleton"
}

test_deepseek_instructions_budget_covers_the_file() {
  sandbox
  install_deepseek_profile_rows "$ROOT" 196608 0 0 >/dev/null 2>&1 || true
  local written
  written="$(cat "$DSH_HOME/cordis.patch.yml")"

  assert_contains "$written" "id: agent-instructions" \
    && assert_contains "$written" "maxBytes: 196608"
}

test_deepseek_review_hook_row_is_opt_in() {
  sandbox
  PATH="$TMP_ROOT/bin:$PATH" install_deepseek_profile_rows "$ROOT" 196608 0 0 >/dev/null
  local without
  without="$(cat "$DSH_HOME/cordis.patch.yml")"

  PATH="$TMP_ROOT/bin:$PATH" install_deepseek_profile_rows "$ROOT" 196608 1 0 >/dev/null
  local with_hook
  with_hook="$(cat "$DSH_HOME/cordis.patch.yml")"

  assert_lacks "$without" "id: commit-review" \
    && assert_contains "$with_hook" "id: commit-review" \
    && assert_contains "$with_hook" "name: '@deepseek-ai/dsh-user-approval/hooks'" \
    && assert_contains "$with_hook" "command: \"$AGENT_HOME/.agents/hooks/deepseek-commit-review.sh\""
}

test_deepseek_teams_row_is_opt_in_and_removed_again() {
  sandbox
  PATH="$TMP_ROOT/bin:$PATH" install_deepseek_profile_rows "$ROOT" 196608 0 1 >/dev/null
  local with_teams
  with_teams="$(cat "$DSH_HOME/cordis.patch.yml")"

  PATH="$TMP_ROOT/bin:$PATH" install_deepseek_profile_rows "$ROOT" 196608 0 0 >/dev/null
  local without
  without="$(cat "$DSH_HOME/cordis.patch.yml")"

  assert_contains "$with_teams" "id: teams" \
    && assert_contains "$with_teams" "name: '@deepseek-ai/dsh-system-prompt/persona'" \
    && assert_lacks "$without" "id: teams"
}

test_deepseek_rows_reproduce_the_same_file_on_reinstall() {
  sandbox
  PATH="$TMP_ROOT/bin:$PATH" install_deepseek_profile_rows "$ROOT" 196608 1 1 >/dev/null
  local first
  first="$(cat "$DSH_HOME/cordis.patch.yml")"

  PATH="$TMP_ROOT/bin:$PATH" install_deepseek_profile_rows "$ROOT" 196608 1 1 >/dev/null

  [[ "$(cat "$DSH_HOME/cordis.patch.yml")" == "$first" ]]
}

test_deepseek_rows_leave_the_users_own_entries_alone() {
  sandbox
  local patch="$DSH_HOME/cordis.patch.yml"
  cat > "$patch" <<'YAML'
# my own patch layer
- id: permission
  name: '@deepseek-ai/dsh-permission-presets'
  config:
    defaultPreset: read-only
YAML

  PATH="$TMP_ROOT/bin:$PATH" install_deepseek_profile_rows "$ROOT" 196608 1 1 >/dev/null
  local written
  written="$(cat "$patch")"

  # Every row sits inside the block this installer owns; the user entry above
  # it is byte-identical to what the test wrote.
  assert_contains "$written" "# my own patch layer" \
    && assert_contains "$written" "defaultPreset: read-only" \
    && [[ "$(sed -n '1,5p' "$patch")" == "$(printf '%s' "# my own patch layer
- id: permission
  name: '@deepseek-ai/dsh-permission-presets'
  config:
    defaultPreset: read-only")" ]]
}

test_deepseek_rows_keep_one_blank_line_between_blocks() {
  sandbox
  PATH="$TMP_ROOT/bin:$PATH" install_deepseek_profile_rows "$ROOT" 196608 1 1 >/dev/null
  PATH="$TMP_ROOT/bin:$PATH" install_deepseek_profile_rows "$ROOT" 196608 1 1 >/dev/null
  local written
  written="$(cat "$DSH_HOME/cordis.patch.yml")"

  # Between the insert and the update row: their ids must not share a line,
  # which is what a missing newline would do.
  assert_contains "$written" $'you.\n\n- id: agent-instructions'
}

test_deepseek_build_writes_its_own_agents_file() {
  sandbox
  local out="$TMP_ROOT/build/AGENTS.deepseek.md"

  bash "$ROOT/scripts/build.sh" --out="$out" >/dev/null

  [[ -f "$out" ]] \
    && assert_contains "$(cat "$out")" "# Global Instructions"
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

run_test test_deepseek_patch_is_created_when_missing
run_test test_deepseek_mcp_row_mounts_the_client
run_test test_deepseek_mcp_row_is_skipped_without_the_bin
run_test test_deepseek_instructions_budget_covers_the_file
run_test test_deepseek_review_hook_row_is_opt_in
run_test test_deepseek_teams_row_is_opt_in_and_removed_again
run_test test_deepseek_rows_reproduce_the_same_file_on_reinstall
run_test test_deepseek_rows_leave_the_users_own_entries_alone
run_test test_deepseek_rows_keep_one_blank_line_between_blocks
run_test test_deepseek_build_writes_its_own_agents_file
