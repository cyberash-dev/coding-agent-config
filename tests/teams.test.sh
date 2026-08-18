#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=scripts/lib/install-lib.sh
source "$ROOT/scripts/lib/install-lib.sh"

TMP_ROOT=""
ORIGINAL_PATH="$PATH"

cleanup() {
  [[ -z "$TMP_ROOT" ]] || rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

sandbox() {
  cleanup
  TMP_ROOT="$(mktemp -d)"
  CODEX_CONFIG_TOML="$TMP_ROOT/config.toml"
  CODEX_CONFIG_BACKED_UP=0
  PATH="$ORIGINAL_PATH"
  fake_codex true
}

# A failing assertion inside a test function does not abort it: `set -e` is
# suppressed for functions called from an `if` condition, which is how run_test
# invokes them. Every assertion therefore reports through its own exit status.
assert_contains() {
  local haystack="$1" needle="$2"
  printf '%s' "$haystack" | grep -F -- "$needle" >/dev/null
}

assert_lacks() {
  local haystack="$1" needle="$2"
  ! printf '%s' "$haystack" | grep -F -- "$needle" >/dev/null
}

# Stand in for the codex binary: reports <state> for every feature and records
# what the installer asked it to enable. A state of `fail` makes the query itself
# exit non-zero, as an older codex without the subcommand would.
fake_codex() {
  local feature_state="$1"
  mkdir -p "$TMP_ROOT/bin"
  cat > "$TMP_ROOT/bin/codex" <<EOF
#!/usr/bin/env bash
if [[ "\$1 \$2" == "features list" ]]; then
  [[ "$feature_state" == "fail" ]] && exit 1
  printf 'multi_agent  stable  %s\n' "$feature_state"
  exit 0
fi
if [[ "\$1 \$2" == "features enable" ]]; then
  printf '%s' "\$3" >> "$TMP_ROOT/enabled-features"
  exit 0
fi
exit 1
EOF
  chmod +x "$TMP_ROOT/bin/codex"
  PATH="$TMP_ROOT/bin:$PATH"
}

test_teams_section_is_empty_when_teams_are_not_requested() {
  local output
  output="$(teams_section 0 "$ROOT/templates/teams")" || return 1

  [[ -z "$output" ]]
}

test_teams_section_imports_the_orchestration_rule() {
  assert_contains "$(teams_section 1 "$ROOT/templates/teams")" "@rules/orchestration.md"
}

test_teams_section_fails_on_a_missing_fragment() {
  local rc=0
  (teams_section 1 "$ROOT/templates/absent") >/dev/null 2>&1 || rc=$?

  [[ "$rc" -ne 0 ]]
}

test_codex_subagents_enables_a_fresh_config() {
  sandbox

  install_codex_subagents 1 >/dev/null

  local written
  written="$(cat "$CODEX_CONFIG_TOML")"
  assert_contains "$written" "[agents]" || return 1
  assert_contains "$written" "enabled = true"
}

test_codex_subagents_flips_a_disabled_table() {
  sandbox
  printf '[agents]\nenabled = false\nmax_concurrent_threads_per_session = 4\n' > "$CODEX_CONFIG_TOML"

  install_codex_subagents 1 >/dev/null

  local written
  written="$(cat "$CODEX_CONFIG_TOML")"
  assert_contains "$written" "enabled = true" || return 1
  assert_lacks "$written" "enabled = false" || return 1
  assert_contains "$written" "max_concurrent_threads_per_session = 4"
}

test_codex_subagents_keeps_neighbouring_tables() {
  sandbox
  printf '[mcp_servers.code-skeleton]\ncommand = "code-skeleton-mcp"\n\n[agents]\nenabled = false\n' > "$CODEX_CONFIG_TOML"

  install_codex_subagents 1 >/dev/null

  local written
  written="$(cat "$CODEX_CONFIG_TOML")"
  assert_contains "$written" "[mcp_servers.code-skeleton]" || return 1
  assert_contains "$written" 'command = "code-skeleton-mcp"'
}

test_codex_subagents_appends_the_table_below_a_role_subtable() {
  sandbox
  printf '[agents.explorer]\ndescription = "read-only explorer"\n' > "$CODEX_CONFIG_TOML"

  install_codex_subagents 1 >/dev/null

  assert_contains "$(cat "$CODEX_CONFIG_TOML")" 'description = "read-only explorer"' || return 1
  [[ "$(tail -n 2 "$CODEX_CONFIG_TOML")" == "[agents]
enabled = true" ]]
}

test_codex_subagents_reuses_a_table_header_carrying_a_comment() {
  sandbox
  printf '[agents]  # sub-agent runtime\nenabled = false\n' > "$CODEX_CONFIG_TOML"

  install_codex_subagents 1 >/dev/null

  [[ "$(grep -c '^\[agents\]' "$CODEX_CONFIG_TOML")" -eq 1 ]] || return 1
  assert_contains "$(cat "$CODEX_CONFIG_TOML")" "enabled = true"
}

test_codex_subagents_rewrites_a_dotted_key_in_place() {
  sandbox
  printf 'agents.enabled = false\nmodel = "gpt-5.6-sol"\n' > "$CODEX_CONFIG_TOML"

  install_codex_subagents 1 >/dev/null

  local written
  written="$(cat "$CODEX_CONFIG_TOML")"
  assert_contains "$written" "agents.enabled = true" || return 1
  assert_contains "$written" 'model = "gpt-5.6-sol"' || return 1
  assert_lacks "$written" "[agents]"
}

test_codex_subagents_reads_a_dotted_key_on_a_rerun() {
  sandbox
  printf 'agents.enabled = true\n' > "$CODEX_CONFIG_TOML"

  local output
  output="$(install_codex_subagents 1)"

  assert_contains "$output" "already"
}

test_codex_subagents_refuses_an_inline_agents_table() {
  sandbox
  printf 'agents = { enabled = false }\n' > "$CODEX_CONFIG_TOML"

  local output
  output="$(install_codex_subagents 1 2>&1)"

  [[ "$(cat "$CODEX_CONFIG_TOML")" == "agents = { enabled = false }" ]] || return 1
  assert_contains "$output" "by hand"
}

test_codex_subagents_enables_a_disabled_multi_agent_feature() {
  sandbox
  fake_codex false

  install_codex_subagents 1 >/dev/null

  [[ -f "$TMP_ROOT/enabled-features" ]] || return 1
  [[ "$(cat "$TMP_ROOT/enabled-features")" == "multi_agent" ]]
}

test_codex_subagents_leaves_an_already_enabled_feature_alone() {
  sandbox

  install_codex_subagents 1 >/dev/null

  [[ ! -e "$TMP_ROOT/enabled-features" ]]
}

test_codex_subagents_survives_a_failing_feature_query() {
  sandbox
  fake_codex fail
  printf '[agents]\nenabled = false\n' > "$CODEX_CONFIG_TOML"

  # A driver runs under `set -euo pipefail`, and a subshell on the left of `||`
  # would suppress it — hence a separate bash process.
  local rc=0
  bash -c '
    set -euo pipefail
    source "$1"
    PATH="$2:$PATH"
    CODEX_CONFIG_TOML="$3"
    install_codex_subagents 1
  ' _ "$ROOT/scripts/lib/install-lib.sh" "$TMP_ROOT/bin" "$CODEX_CONFIG_TOML" >/dev/null 2>&1 || rc=$?

  [[ "$rc" -eq 0 ]] || return 1
  assert_contains "$(cat "$CODEX_CONFIG_TOML")" "enabled = true"
}

test_codex_subagents_writes_the_key_once_on_a_rerun() {
  sandbox
  install_codex_subagents 1 >/dev/null

  local output
  output="$(install_codex_subagents 1)"

  [[ "$(grep -c 'enabled = true' "$CODEX_CONFIG_TOML")" -eq 1 ]] || return 1
  assert_contains "$output" "already"
}

test_codex_subagents_leaves_the_config_untouched_when_not_requested() {
  sandbox
  printf '[agents]\nenabled = false\n' > "$CODEX_CONFIG_TOML"

  install_codex_subagents 0 >/dev/null

  [[ "$(cat "$CODEX_CONFIG_TOML")" == "[agents]
enabled = false" ]]
}

test_codex_subagents_creates_no_config_when_not_requested() {
  sandbox

  install_codex_subagents 0 >/dev/null

  [[ ! -e "$CODEX_CONFIG_TOML" ]]
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

run_test test_teams_section_is_empty_when_teams_are_not_requested
run_test test_teams_section_imports_the_orchestration_rule
run_test test_teams_section_fails_on_a_missing_fragment
run_test test_codex_subagents_enables_a_fresh_config
run_test test_codex_subagents_flips_a_disabled_table
run_test test_codex_subagents_keeps_neighbouring_tables
run_test test_codex_subagents_appends_the_table_below_a_role_subtable
run_test test_codex_subagents_reuses_a_table_header_carrying_a_comment
run_test test_codex_subagents_rewrites_a_dotted_key_in_place
run_test test_codex_subagents_reads_a_dotted_key_on_a_rerun
run_test test_codex_subagents_refuses_an_inline_agents_table
run_test test_codex_subagents_enables_a_disabled_multi_agent_feature
run_test test_codex_subagents_leaves_an_already_enabled_feature_alone
run_test test_codex_subagents_survives_a_failing_feature_query
run_test test_codex_subagents_writes_the_key_once_on_a_rerun
run_test test_codex_subagents_leaves_the_config_untouched_when_not_requested
run_test test_codex_subagents_creates_no_config_when_not_requested
