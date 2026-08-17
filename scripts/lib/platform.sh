# Platform detection and path translation. Sourced by scripts/lib/install-lib.sh,
# so every driver that loads install-lib gets these helpers too.
#
# On macOS and Linux every function here is the identity: `agent_home` is $HOME,
# `native_path` echoes its argument, and the junction helpers are never reached.
# Windows means Git Bash / MSYS, which is the only supported native Windows
# shell for these scripts.
#
# Public API (functions):
#   os_kind
#   is_windows
#   agent_home
#   native_path <path>            — forward-slash path for a config file value
#   windows_path <path>           — backslash path for a cmd.exe argument
#   posix_path <path>             — POSIX path for this shell
#   is_junction <path>
#   is_same_dir <path> <path>
#   create_junction <target> <source>
#   remove_junction <target>
#
# Public globals (set on first source):
#   OS_KIND      — macos | linux | windows
#   AGENT_HOME   — POSIX path of the directory that holds .claude, .codex, .agents

if [[ -z "${AGENT_CONFIG_PLATFORM_LOADED:-}" ]]; then
  AGENT_CONFIG_PLATFORM_LOADED=1

  case "$(uname -s)" in
    Darwin)               OS_KIND=macos ;;
    MINGW*|MSYS*|CYGWIN*) OS_KIND=windows ;;
    *)                    OS_KIND=linux ;;
  esac

  # Git Bash derives $HOME from HOMEDRIVE/HOMEPATH, which corporate profiles
  # point at a network share. Claude Code itself reads %USERPROFILE%\.claude,
  # so the install has to follow USERPROFILE, not $HOME.
  AGENT_HOME="$HOME"
  if [[ "$OS_KIND" == "windows" && -n "${USERPROFILE:-}" ]] \
     && command -v cygpath >/dev/null 2>&1; then
    AGENT_HOME="$(cygpath -u "$USERPROFILE")"
  fi
fi

os_kind() {
  printf '%s' "$OS_KIND"
}

is_windows() {
  [[ "$OS_KIND" == "windows" ]]
}

agent_home() {
  printf '%s' "$AGENT_HOME"
}

native_path() {
  if is_windows && command -v cygpath >/dev/null 2>&1; then
    cygpath -m "$1"
    return
  fi
  printf '%s' "$1"
}

windows_path() {
  if is_windows && command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$1"
    return
  fi
  printf '%s' "$1"
}

posix_path() {
  if is_windows && command -v cygpath >/dev/null 2>&1; then
    cygpath -u "$1"
    return
  fi
  printf '%s' "$1"
}

is_junction() {
  local path="$1"
  [[ -d "$path" ]] || return 1
  if command -v fsutil >/dev/null 2>&1; then
    fsutil reparsepoint query "$(windows_path "$path")" >/dev/null 2>&1
    return
  fi
  [[ -L "$path" ]]
}

is_same_dir() {
  local left right
  left="$( (cd "$1" 2>/dev/null && pwd -P) )"
  right="$( (cd "$2" 2>/dev/null && pwd -P) )"
  [[ -n "$left" && "$left" == "$right" ]]
}

create_junction() {
  cmd //c mklink //J "$(windows_path "$1")" "$(windows_path "$2")" >/dev/null
}

remove_junction() {
  cmd //c rmdir "$(windows_path "$1")" >/dev/null
}
