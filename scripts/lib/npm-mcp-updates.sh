# Helpers for npm-backed MCP packages: install a missing package at @latest,
# then offer an update whenever a newer version is published. Sourced by
# scripts/lib/install-lib.sh, so every driver script that loads install-lib
# gets `ensure_mcp_npm_global` as well.
#
# UPDATE_MCPS=1 (the `--update-mcps` flag) updates without prompting.

_mcp_npm_global_version() {
  local pkg="$1"
  local json
  if ! json="$(npm list -g "$pkg" --depth=0 --json 2>/dev/null)"; then
    return 1
  fi

  node -e '
    const fs = require("fs");
    const pkg = process.argv[1];
    const data = JSON.parse(fs.readFileSync(0, "utf8"));
    const dep = data && data.dependencies && data.dependencies[pkg];
    const version = dep && dep.version ? dep.version : "";
    if (!version) process.exit(1);
    console.log(version);
  ' "$pkg" <<< "$json"
}

_mcp_npm_latest_version() {
  local pkg="$1"
  local version
  if ! version="$(npm view "${pkg}@latest" version 2>/dev/null)"; then
    return 1
  fi
  version="$(printf '%s\n' "$version" | awk 'NF { last = $0 } END { print last }')"
  [[ -n "$version" ]] || return 1
  printf '%s' "$version"
}

_mcp_npm_can_prompt() {
  { : > /dev/tty; } 2>/dev/null
}

_mcp_npm_prompt_update() {
  local pkg="$1" installed="$2" latest="$3"
  local answer=""
  printf '  %s update available: %s -> %s. Update now? [y/N]: ' \
    "$pkg" "$installed" "$latest" > /dev/tty
  IFS= read -r answer < /dev/tty || return 1
  case "$answer" in
    y|Y|yes|YES|Yes) return 0 ;;
    *) return 1 ;;
  esac
}

_mcp_npm_install_latest() {
  local pkg="$1"
  npm install -g "${pkg}@latest" >/dev/null 2>&1
}

ensure_mcp_npm_global() {
  local pkg="$1" bin="$2"

  if ! command -v npm >/dev/null 2>&1; then
    echo "  ! npm not on PATH; cannot install $pkg" >&2
    return 1
  fi

  local bin_path
  bin_path="$(command -v "$bin" 2>/dev/null || true)"

  if [[ -z "$bin_path" ]]; then
    echo "  installing $pkg@latest ..." >&2
    if ! _mcp_npm_install_latest "$pkg"; then
      echo "  ! npm install -g ${pkg}@latest failed" >&2
      return 1
    fi

    bin_path="$(command -v "$bin" 2>/dev/null || true)"
    if [[ -z "$bin_path" ]]; then
      echo "  ! $pkg installed but $bin still not on PATH" >&2
      return 1
    fi

    echo "  + installed $pkg@latest" >&2
    printf '%s\n' "$bin_path"
    return 0
  fi

  local installed_version
  installed_version="$(_mcp_npm_global_version "$pkg" 2>/dev/null || true)"
  if [[ -z "$installed_version" ]]; then
    echo "  = $pkg ($bin already on PATH; installed version unknown)" >&2
    printf '%s\n' "$bin_path"
    return 0
  fi

  local latest_version
  latest_version="$(_mcp_npm_latest_version "$pkg" 2>/dev/null || true)"
  if [[ -z "$latest_version" ]]; then
    echo "  ! cannot check latest $pkg version; keeping $installed_version" >&2
    printf '%s\n' "$bin_path"
    return 0
  fi

  if [[ "$installed_version" == "$latest_version" ]]; then
    echo "  = $pkg@$installed_version ($bin already on PATH)" >&2
    printf '%s\n' "$bin_path"
    return 0
  fi

  local should_update=0
  if [[ "${UPDATE_MCPS:-0}" -eq 1 ]]; then
    should_update=1
  elif _mcp_npm_can_prompt; then
    if _mcp_npm_prompt_update "$pkg" "$installed_version" "$latest_version"; then
      should_update=1
    else
      echo "  = kept $pkg@$installed_version" >&2
    fi
  else
    echo "  ! $pkg update available ($installed_version -> $latest_version); skipped without TTY" >&2
    echo "    rerun with --update-mcps to update npm-backed MCP packages" >&2
  fi

  if [[ "$should_update" -eq 1 ]]; then
    echo "  updating $pkg $installed_version -> $latest_version ..." >&2
    if _mcp_npm_install_latest "$pkg"; then
      echo "  + updated $pkg@$latest_version" >&2
    else
      echo "  ! npm install -g ${pkg}@latest failed; keeping $installed_version" >&2
    fi
  fi

  bin_path="$(command -v "$bin" 2>/dev/null || true)"
  if [[ -z "$bin_path" ]]; then
    echo "  ! $bin not on PATH after npm MCP check" >&2
    return 1
  fi

  printf '%s\n' "$bin_path"
}
