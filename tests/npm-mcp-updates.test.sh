#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=scripts/lib/npm-mcp-updates.sh
source "$ROOT/scripts/lib/npm-mcp-updates.sh"

ORIGINAL_PATH="$PATH"
TMP_ROOT=""
FAKE_NPM_STATE=""
FAKE_NPM_LOG=""
FAKE_NPM_BIN_DIR=""

cleanup() {
  [[ -z "$TMP_ROOT" ]] || rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

safe_pkg() {
  printf '%s' "$1" | tr '/@' '__'
}

setup_fake_npm() {
  cleanup
  TMP_ROOT="$(mktemp -d)"
  FAKE_NPM_STATE="$TMP_ROOT/state"
  FAKE_NPM_LOG="$TMP_ROOT/npm.log"
  FAKE_NPM_BIN_DIR="$TMP_ROOT/bin"
  mkdir -p \
    "$FAKE_NPM_STATE/installed" \
    "$FAKE_NPM_STATE/latest" \
    "$FAKE_NPM_STATE/bins" \
    "$FAKE_NPM_STATE/fail-view" \
    "$FAKE_NPM_STATE/fail-install" \
    "$FAKE_NPM_BIN_DIR"
  : > "$FAKE_NPM_LOG"

  cat > "$FAKE_NPM_BIN_DIR/npm" <<'FAKE_NPM'
#!/usr/bin/env bash
set -euo pipefail

safe_pkg() {
  printf '%s' "$1" | tr '/@' '__'
}

printf '%s\n' "$*" >> "$FAKE_NPM_LOG"

case "${1:-}" in
  list)
    pkg="${3:-}"
    safe="$(safe_pkg "$pkg")"
    if [[ -f "$FAKE_NPM_STATE/installed/$safe" ]]; then
      version="$(cat "$FAKE_NPM_STATE/installed/$safe")"
      printf '{"dependencies":{"%s":{"version":"%s"}}}\n' "$pkg" "$version"
      exit 0
    fi
    printf '{"dependencies":{}}\n'
    exit 1
    ;;
  view)
    pkg="${2%@latest}"
    safe="$(safe_pkg "$pkg")"
    [[ ! -f "$FAKE_NPM_STATE/fail-view/$safe" ]] || exit 1
    cat "$FAKE_NPM_STATE/latest/$safe"
    exit 0
    ;;
  install)
    spec="${3:-}"
    pkg="${spec%@latest}"
    safe="$(safe_pkg "$pkg")"
    [[ ! -f "$FAKE_NPM_STATE/fail-install/$safe" ]] || exit 1
    version="$(cat "$FAKE_NPM_STATE/latest/$safe")"
    bin="$(cat "$FAKE_NPM_STATE/bins/$safe")"
    printf '%s' "$version" > "$FAKE_NPM_STATE/installed/$safe"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$FAKE_NPM_BIN_DIR/$bin"
    chmod +x "$FAKE_NPM_BIN_DIR/$bin"
    exit 0
    ;;
esac

exit 2
FAKE_NPM
  chmod +x "$FAKE_NPM_BIN_DIR/npm"

  PATH="$FAKE_NPM_BIN_DIR:$ORIGINAL_PATH"
  export FAKE_NPM_STATE FAKE_NPM_LOG FAKE_NPM_BIN_DIR PATH
}

set_latest() {
  local pkg="$1" version="$2" bin="$3"
  local safe
  safe="$(safe_pkg "$pkg")"
  printf '%s' "$version" > "$FAKE_NPM_STATE/latest/$safe"
  printf '%s' "$bin" > "$FAKE_NPM_STATE/bins/$safe"
}

set_installed() {
  local pkg="$1" version="$2" bin="$3"
  local safe
  safe="$(safe_pkg "$pkg")"
  printf '%s' "$version" > "$FAKE_NPM_STATE/installed/$safe"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$FAKE_NPM_BIN_DIR/$bin"
  chmod +x "$FAKE_NPM_BIN_DIR/$bin"
}

assert_contains() {
  local file="$1" pattern="$2"
  grep -F -- "$pattern" "$file" >/dev/null
}

assert_not_contains() {
  local file="$1" pattern="$2"
  ! grep -F -- "$pattern" "$file" >/dev/null
}

test_missing_package_installs_latest() {
  setup_fake_npm
  set_latest "demo-mcp" "1.0.0" "demo-mcp"

  ensure_mcp_npm_global "demo-mcp" "demo-mcp" > "$TMP_ROOT/out" 2> "$TMP_ROOT/err"

  assert_contains "$FAKE_NPM_LOG" "install -g demo-mcp@latest"
  assert_contains "$TMP_ROOT/out" "$FAKE_NPM_BIN_DIR/demo-mcp"
}

test_installed_latest_does_not_reinstall() {
  setup_fake_npm
  set_latest "demo-mcp" "1.0.0" "demo-mcp"
  set_installed "demo-mcp" "1.0.0" "demo-mcp"

  ensure_mcp_npm_global "demo-mcp" "demo-mcp" > "$TMP_ROOT/out" 2> "$TMP_ROOT/err"

  assert_not_contains "$FAKE_NPM_LOG" "install -g demo-mcp@latest"
  assert_contains "$TMP_ROOT/out" "$FAKE_NPM_BIN_DIR/demo-mcp"
}

test_installed_behind_prompts_in_normal_mode() {
  setup_fake_npm
  set_latest "demo-mcp" "1.1.0" "demo-mcp"
  set_installed "demo-mcp" "1.0.0" "demo-mcp"
  UPDATE_MCPS=0
  PROMPTED=0
  _mcp_npm_can_prompt() { return 0; }
  _mcp_npm_prompt_update() { PROMPTED=1; return 0; }

  ensure_mcp_npm_global "demo-mcp" "demo-mcp" > "$TMP_ROOT/out" 2> "$TMP_ROOT/err"

  [[ "$PROMPTED" == "1" ]]
  assert_contains "$FAKE_NPM_LOG" "install -g demo-mcp@latest"
}

test_no_tty_skips_update_in_normal_mode() {
  setup_fake_npm
  set_latest "demo-mcp" "1.1.0" "demo-mcp"
  set_installed "demo-mcp" "1.0.0" "demo-mcp"
  UPDATE_MCPS=0
  _mcp_npm_can_prompt() { return 1; }

  ensure_mcp_npm_global "demo-mcp" "demo-mcp" > "$TMP_ROOT/out" 2> "$TMP_ROOT/err"

  assert_not_contains "$FAKE_NPM_LOG" "install -g demo-mcp@latest"
  assert_contains "$TMP_ROOT/err" "--update-mcps"
}

test_update_flag_updates_without_prompt() {
  setup_fake_npm
  set_latest "demo-mcp" "1.1.0" "demo-mcp"
  set_installed "demo-mcp" "1.0.0" "demo-mcp"
  UPDATE_MCPS=1
  _mcp_npm_prompt_update() { return 1; }

  ensure_mcp_npm_global "demo-mcp" "demo-mcp" > "$TMP_ROOT/out" 2> "$TMP_ROOT/err"

  assert_contains "$FAKE_NPM_LOG" "install -g demo-mcp@latest"
}

test_view_failure_warns_and_keeps_installed_bin() {
  setup_fake_npm
  set_latest "demo-mcp" "1.1.0" "demo-mcp"
  set_installed "demo-mcp" "1.0.0" "demo-mcp"
  touch "$FAKE_NPM_STATE/fail-view/$(safe_pkg "demo-mcp")"

  ensure_mcp_npm_global "demo-mcp" "demo-mcp" > "$TMP_ROOT/out" 2> "$TMP_ROOT/err"

  assert_contains "$TMP_ROOT/err" "cannot check latest"
  assert_contains "$TMP_ROOT/out" "$FAKE_NPM_BIN_DIR/demo-mcp"
}

test_update_install_failure_warns_and_keeps_installed_bin() {
  setup_fake_npm
  set_latest "demo-mcp" "1.1.0" "demo-mcp"
  set_installed "demo-mcp" "1.0.0" "demo-mcp"
  UPDATE_MCPS=1
  touch "$FAKE_NPM_STATE/fail-install/$(safe_pkg "demo-mcp")"

  ensure_mcp_npm_global "demo-mcp" "demo-mcp" > "$TMP_ROOT/out" 2> "$TMP_ROOT/err"

  assert_contains "$TMP_ROOT/err" "failed"
  assert_contains "$TMP_ROOT/out" "$FAKE_NPM_BIN_DIR/demo-mcp"
}

test_missing_install_failure_warns_and_returns_nonzero() {
  setup_fake_npm
  set_latest "demo-mcp" "1.0.0" "demo-mcp"
  touch "$FAKE_NPM_STATE/fail-install/$(safe_pkg "demo-mcp")"

  if ensure_mcp_npm_global "demo-mcp" "demo-mcp" > "$TMP_ROOT/out" 2> "$TMP_ROOT/err"; then
    return 1
  fi

  assert_contains "$TMP_ROOT/err" "failed"
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

run_test test_missing_package_installs_latest
run_test test_installed_latest_does_not_reinstall
run_test test_installed_behind_prompts_in_normal_mode
run_test test_no_tty_skips_update_in_normal_mode
run_test test_update_flag_updates_without_prompt
run_test test_view_failure_warns_and_keeps_installed_bin
run_test test_update_install_failure_warns_and_keeps_installed_bin
run_test test_missing_install_failure_warns_and_returns_nonzero
