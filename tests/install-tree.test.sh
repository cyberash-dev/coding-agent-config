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
  mkdir -p "$TMP_ROOT/source/scripts" "$TMP_ROOT/home"
  printf 'rule body\n' > "$TMP_ROOT/source/naming.md"
  printf 'other body\n' > "$TMP_ROOT/source/testing.md"
  printf '#!/usr/bin/env bash\n' > "$TMP_ROOT/source/scripts/hook.sh"
  chmod +x "$TMP_ROOT/source/scripts/hook.sh"
  mkdir -p "$TMP_ROOT/source/scripts/__pycache__"
  printf 'compiled\n' > "$TMP_ROOT/source/scripts/__pycache__/hook.cpython-314.pyc"
  printf 'finder junk\n' > "$TMP_ROOT/source/.DS_Store"
  printf 'stale\n' > "$TMP_ROOT/source/naming.md.bak.1700000000"
}

assert_contains() {
  local haystack="$1" needle="$2"
  printf '%s' "$haystack" | grep -F -- "$needle" >/dev/null
}

backup_count() {
  find "$1" -name '*.bak.*' | wc -l | tr -d ' '
}

test_install_tree_copies_the_source_files() {
  sandbox

  install_tree "$TMP_ROOT/source" "$TMP_ROOT/home/rules" >/dev/null

  [[ "$(cat "$TMP_ROOT/home/rules/naming.md")" == "rule body" ]] \
    && [[ "$(cat "$TMP_ROOT/home/rules/scripts/hook.sh")" == "#!/usr/bin/env bash" ]] \
    && [[ ! -L "$TMP_ROOT/home/rules" ]]
}

test_install_tree_skips_local_build_junk() {
  sandbox

  install_tree "$TMP_ROOT/source" "$TMP_ROOT/home/rules" >/dev/null

  [[ ! -e "$TMP_ROOT/home/rules/scripts/__pycache__" ]] \
    && [[ ! -e "$TMP_ROOT/home/rules/.DS_Store" ]] \
    && [[ ! -e "$TMP_ROOT/home/rules/naming.md.bak.1700000000" ]] \
    && [[ -f "$TMP_ROOT/home/rules/scripts/hook.sh" ]]
}

test_install_tree_keeps_the_executable_bit() {
  sandbox

  install_tree "$TMP_ROOT/source" "$TMP_ROOT/home/rules" >/dev/null

  [[ -x "$TMP_ROOT/home/rules/scripts/hook.sh" ]]
}

test_install_tree_rewrites_a_changed_file() {
  sandbox
  install_tree "$TMP_ROOT/source" "$TMP_ROOT/home/rules" >/dev/null
  printf 'new body\n' > "$TMP_ROOT/source/naming.md"

  install_tree "$TMP_ROOT/source" "$TMP_ROOT/home/rules" >/dev/null

  [[ "$(cat "$TMP_ROOT/home/rules/naming.md")" == "new body" ]]
}

test_install_tree_is_a_no_op_when_nothing_changed() {
  sandbox
  install_tree "$TMP_ROOT/source" "$TMP_ROOT/home/rules" >/dev/null

  local output
  output="$(install_tree "$TMP_ROOT/source" "$TMP_ROOT/home/rules")"

  assert_contains "$output" "up to date" \
    && [[ "$(backup_count "$TMP_ROOT/home")" == "0" ]]
}

test_install_tree_removes_a_file_dropped_from_the_source() {
  sandbox
  install_tree "$TMP_ROOT/source" "$TMP_ROOT/home/rules" >/dev/null
  rm "$TMP_ROOT/source/testing.md"

  install_tree "$TMP_ROOT/source" "$TMP_ROOT/home/rules" >/dev/null

  [[ ! -e "$TMP_ROOT/home/rules/testing.md" ]] \
    && [[ -f "$TMP_ROOT/home/rules/naming.md" ]]
}

test_install_tree_leaves_a_foreign_file_alone() {
  sandbox
  mkdir -p "$TMP_ROOT/home/rules"
  printf 'hand written\n' > "$TMP_ROOT/home/rules/mine.md"

  install_tree "$TMP_ROOT/source" "$TMP_ROOT/home/rules" >/dev/null

  [[ "$(cat "$TMP_ROOT/home/rules/mine.md")" == "hand written" ]]
}

test_install_tree_backs_up_a_foreign_file_it_overwrites() {
  sandbox
  mkdir -p "$TMP_ROOT/home/rules"
  printf 'hand written\n' > "$TMP_ROOT/home/rules/naming.md"

  install_tree "$TMP_ROOT/source" "$TMP_ROOT/home/rules" >/dev/null

  [[ "$(cat "$TMP_ROOT/home/rules/naming.md")" == "rule body" ]] \
    && [[ "$(cat "$TMP_ROOT/home/rules/naming.md.bak.$TS")" == "hand written" ]]
}

test_install_tree_does_not_back_up_its_own_earlier_copy() {
  sandbox
  install_tree "$TMP_ROOT/source" "$TMP_ROOT/home/rules" >/dev/null
  printf 'new body\n' > "$TMP_ROOT/source/naming.md"

  install_tree "$TMP_ROOT/source" "$TMP_ROOT/home/rules" >/dev/null

  [[ "$(backup_count "$TMP_ROOT/home")" == "0" ]]
}

test_install_tree_replaces_a_symlink_left_by_an_older_install() {
  sandbox
  ln -s "$TMP_ROOT/source" "$TMP_ROOT/home/rules"

  install_tree "$TMP_ROOT/source" "$TMP_ROOT/home/rules" >/dev/null

  [[ ! -L "$TMP_ROOT/home/rules" ]] \
    && [[ -d "$TMP_ROOT/home/rules" ]] \
    && [[ "$(cat "$TMP_ROOT/home/rules/naming.md")" == "rule body" ]]
}

test_install_tree_fails_on_a_missing_source() {
  sandbox

  local output rc=0
  output="$( (install_tree "$TMP_ROOT/absent" "$TMP_ROOT/home/rules") 2>&1 )" || rc=$?

  [[ "$rc" -ne 0 ]] \
    && assert_contains "$output" "source missing"
}

test_install_file_copies_a_single_file() {
  sandbox

  install_file "$TMP_ROOT/source/naming.md" "$TMP_ROOT/home/AGENTS.md" >/dev/null

  [[ "$(cat "$TMP_ROOT/home/AGENTS.md")" == "rule body" ]]
}

test_install_file_is_a_no_op_when_nothing_changed() {
  sandbox
  install_file "$TMP_ROOT/source/naming.md" "$TMP_ROOT/home/AGENTS.md" >/dev/null

  local output
  output="$(install_file "$TMP_ROOT/source/naming.md" "$TMP_ROOT/home/AGENTS.md")"

  assert_contains "$output" "up to date"
}

test_install_file_backs_up_a_foreign_file_once() {
  sandbox
  printf 'hand written\n' > "$TMP_ROOT/home/AGENTS.md"
  install_file "$TMP_ROOT/source/naming.md" "$TMP_ROOT/home/AGENTS.md" >/dev/null
  printf 'new body\n' > "$TMP_ROOT/source/naming.md"

  install_file "$TMP_ROOT/source/naming.md" "$TMP_ROOT/home/AGENTS.md" >/dev/null

  [[ "$(cat "$TMP_ROOT/home/AGENTS.md.bak.$TS")" == "hand written" ]] \
    && [[ "$(backup_count "$TMP_ROOT/home")" == "1" ]]
}

test_install_file_replaces_a_symlink_left_by_an_older_install() {
  sandbox
  ln -s "$TMP_ROOT/source/naming.md" "$TMP_ROOT/home/AGENTS.md"

  install_file "$TMP_ROOT/source/naming.md" "$TMP_ROOT/home/AGENTS.md" >/dev/null

  [[ ! -L "$TMP_ROOT/home/AGENTS.md" ]] \
    && [[ "$(cat "$TMP_ROOT/home/AGENTS.md")" == "rule body" ]]
}

test_remove_installed_tree_removes_only_what_was_installed() {
  sandbox
  install_tree "$TMP_ROOT/source" "$TMP_ROOT/home/skill" >/dev/null
  printf 'hand written\n' > "$TMP_ROOT/home/skill/mine.md"

  remove_installed_tree "$TMP_ROOT/home/skill" >/dev/null

  [[ ! -e "$TMP_ROOT/home/skill/naming.md" ]] \
    && [[ "$(cat "$TMP_ROOT/home/skill/mine.md")" == "hand written" ]]
}

test_remove_installed_tree_drops_an_emptied_directory() {
  sandbox
  install_tree "$TMP_ROOT/source" "$TMP_ROOT/home/skill" >/dev/null

  remove_installed_tree "$TMP_ROOT/home/skill" >/dev/null

  [[ ! -e "$TMP_ROOT/home/skill" ]]
}

test_remove_installed_tree_ignores_an_absent_target() {
  sandbox

  remove_installed_tree "$TMP_ROOT/home/absent" >/dev/null
}

test_write_generated_backs_up_a_file_it_does_not_own() {
  sandbox
  printf 'hand written\n' > "$TMP_ROOT/home/CLAUDE.md"

  write_generated "$TMP_ROOT/home/CLAUDE.md" "generated body" >/dev/null

  [[ "$(cat "$TMP_ROOT/home/CLAUDE.md")" == "generated body" ]] \
    && [[ "$(cat "$TMP_ROOT/home/CLAUDE.md.bak.$TS")" == "hand written" ]]
}

test_write_generated_overwrites_its_own_earlier_output() {
  sandbox
  write_generated "$TMP_ROOT/home/CLAUDE.md" "generated body" >/dev/null
  printf 'generated body\n\nappended by another tool\n' > "$TMP_ROOT/home/CLAUDE.md"

  write_generated "$TMP_ROOT/home/CLAUDE.md" "generated body" >/dev/null

  [[ "$(cat "$TMP_ROOT/home/CLAUDE.md")" == "generated body" ]] \
    && [[ "$(backup_count "$TMP_ROOT/home")" == "0" ]]
}

test_write_generated_is_a_no_op_when_the_content_matches() {
  sandbox
  write_generated "$TMP_ROOT/home/CLAUDE.md" "generated body" >/dev/null

  local output
  output="$(write_generated "$TMP_ROOT/home/CLAUDE.md" "generated body")"

  assert_contains "$output" "up to date"
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

run_test test_install_tree_copies_the_source_files
run_test test_install_tree_skips_local_build_junk
run_test test_install_tree_keeps_the_executable_bit
run_test test_install_tree_rewrites_a_changed_file
run_test test_install_tree_is_a_no_op_when_nothing_changed
run_test test_install_tree_removes_a_file_dropped_from_the_source
run_test test_install_tree_leaves_a_foreign_file_alone
run_test test_install_tree_backs_up_a_foreign_file_it_overwrites
run_test test_install_tree_does_not_back_up_its_own_earlier_copy
run_test test_install_tree_replaces_a_symlink_left_by_an_older_install
run_test test_install_tree_fails_on_a_missing_source
run_test test_install_file_copies_a_single_file
run_test test_install_file_is_a_no_op_when_nothing_changed
run_test test_install_file_backs_up_a_foreign_file_once
run_test test_install_file_replaces_a_symlink_left_by_an_older_install
run_test test_remove_installed_tree_removes_only_what_was_installed
run_test test_remove_installed_tree_drops_an_emptied_directory
run_test test_remove_installed_tree_ignores_an_absent_target
run_test test_write_generated_backs_up_a_file_it_does_not_own
run_test test_write_generated_overwrites_its_own_earlier_output
run_test test_write_generated_is_a_no_op_when_the_content_matches
