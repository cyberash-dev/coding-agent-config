#!/usr/bin/env bash
# Reusable helpers for coding-agent-config and downstream extension repos.
# Source this file from a driver script that orchestrates installation
# and build steps.
#
# Idempotent: safe to source multiple times; globals are initialised once.
#
# Public API (functions):
#   link <source> <target>
#   write_generated <target> <content>
#   install_hook <script> <matcher> <event>
#   remove_hook <basename> <event>
#   install_skills <source_root> <target_root>
#   cleanup_legacy_codex_skills <source_root> [<source_root>...]
#   unlink_if_repo_owned <target> <abs_source_root>
#   inline_imports <source_file> <output_file> <prefix>=<root> [<prefix>=<root>...]
#
# Public globals (set on first source):
#   TS                   — install timestamp, used for `.bak.<TS>` backups
#   SETTINGS             — path to ~/.claude/settings.json
#   SETTINGS_BACKED_UP   — 0/1 flag, mutated by install_hook/remove_hook

if [[ -z "${AGENT_CONFIG_LIB_LOADED:-}" ]]; then
  AGENT_CONFIG_LIB_LOADED=1

  TS="$(date +%s)"
  SETTINGS="$HOME/.claude/settings.json"
  SETTINGS_BACKED_UP=0

  CLAUDE_CONFIG="$HOME/.claude.json"
  CLAUDE_CONFIG_BACKED_UP=0

  CODEX_CONFIG_TOML="${CODEX_HOME:-$HOME/.codex}/config.toml"
  CODEX_CONFIG_BACKED_UP=0
fi

link() {
  local source="$1"
  local target="$2"

  if [[ ! -e "$source" ]]; then
    echo "install-lib: source missing: $source" >&2
    exit 1
  fi

  mkdir -p "$(dirname "$target")"

  if [[ -L "$target" ]]; then
    local current
    current="$(readlink "$target")"
    if [[ "$current" == "$source" ]]; then
      echo "  = $target -> $source (already linked)"
      return 0
    fi
  fi

  if [[ -e "$target" || -L "$target" ]]; then
    local backup="${target}.bak.${TS}"
    mv "$target" "$backup"
    echo "  ~ backed up $target -> $backup"
  fi

  ln -snf "$source" "$target"
  echo "  + $target -> $source"
}

write_generated() {
  local target="$1"
  local content="$2"

  mkdir -p "$(dirname "$target")"

  if [[ -e "$target" || -L "$target" ]]; then
    local backup="${target}.bak.${TS}"
    mv "$target" "$backup"
    echo "  ~ backed up $target -> $backup"
  fi

  printf '%s' "$content" > "$target"
  echo "  + $target (generated)"
}

# Idempotently register a hook in $SETTINGS.
# Removes any prior entries whose command ends with the same basename, then
# appends a fresh entry pointing at the canonical path.
install_hook() {
  local script="$1"
  local matcher="$2"
  local event="$3"
  local basename
  basename="$(basename "$script")"

  if ! command -v jq >/dev/null 2>&1; then
    echo "install-lib: jq is required to register hooks" >&2
    exit 1
  fi

  mkdir -p "$(dirname "$SETTINGS")"
  if [[ ! -f "$SETTINGS" ]]; then
    echo '{}' > "$SETTINGS"
  fi

  if [[ "$SETTINGS_BACKED_UP" -eq 0 ]]; then
    cp "$SETTINGS" "${SETTINGS}.bak.${TS}"
    echo "  ~ backed up $SETTINGS -> ${SETTINGS}.bak.${TS}"
    SETTINGS_BACKED_UP=1
  fi

  local tmp
  tmp="$(mktemp)"
  jq --arg script "$script" \
     --arg matcher "$matcher" \
     --arg event "$event" \
     --arg basename "$basename" '
    .hooks //= {}
    | .hooks[$event] //= []
    | .hooks[$event] |= (
        map(
          .hooks |= map(select((.command // "") | endswith($basename) | not))
        )
        | map(select((.hooks // []) | length > 0))
      )
    | .hooks[$event] += [
        ( {hooks: [{type: "command", command: $script}]}
          + ( if $matcher == "" then {} else {matcher: $matcher} end )
        )
      ]
  ' "$SETTINGS" > "$tmp"
  mv "$tmp" "$SETTINGS"
  echo "  + hook $event${matcher:+ ($matcher)} -> $script"
}

# Drop any hook entries whose command ends with <basename> from <event>.
remove_hook() {
  local basename="$1"
  local event="$2"

  [[ -f "$SETTINGS" ]] || return 0

  if ! command -v jq >/dev/null 2>&1; then
    echo "install-lib: jq is required to manage hooks" >&2
    exit 1
  fi

  local has_match
  has_match="$(jq --arg event "$event" --arg basename "$basename" '
    [ (.hooks[$event] // [])[]?.hooks[]?.command // ""
      | select(endswith($basename))
    ] | length
  ' "$SETTINGS")"

  if [[ "$has_match" == "0" ]]; then
    return 0
  fi

  if [[ "$SETTINGS_BACKED_UP" -eq 0 ]]; then
    cp "$SETTINGS" "${SETTINGS}.bak.${TS}"
    echo "  ~ backed up $SETTINGS -> ${SETTINGS}.bak.${TS}"
    SETTINGS_BACKED_UP=1
  fi

  local tmp
  tmp="$(mktemp)"
  jq --arg event "$event" --arg basename "$basename" '
    .hooks //= {}
    | if .hooks[$event] then
        .hooks[$event] |= (
          map(
            .hooks |= map(select((.command // "") | endswith($basename) | not))
          )
          | map(select((.hooks // []) | length > 0))
        )
      else . end
  ' "$SETTINGS" > "$tmp"
  mv "$tmp" "$SETTINGS"
  echo "  - hook $event ($basename) removed"
}

# Symlink each repo skill from <source_root>/* into <target_root>/<name>.
install_skills() {
  local source_root="$1"
  local target_root="$2"
  [[ -d "$source_root" ]] || return 0
  local src
  for src in "$source_root"/*/; do
    [[ -d "$src" ]] || continue
    local name
    name="$(basename "$src")"
    link "${src%/}" "$target_root/$name"
  done
}

# Remove same-name symlinks under ~/.codex/skills that point at any of the
# given source roots. Removes the legacy ~/.codex/skills directory if empty.
cleanup_legacy_codex_skills() {
  local legacy_root="$HOME/.codex/skills"
  [[ -d "$legacy_root" ]] || return 0

  local source_root
  for source_root in "$@"; do
    [[ -d "$source_root" ]] || continue
    local src
    for src in "$source_root"/*/; do
      [[ -d "$src" ]] || continue
      local name legacy
      name="$(basename "$src")"
      legacy="$legacy_root/$name"
      [[ -L "$legacy" ]] || continue
      rm "$legacy"
      echo "  - removed legacy Codex skill $legacy"
    done
  done

  rmdir "$legacy_root" 2>/dev/null || true
}

# Remove a symlink at <target> only if it resolves inside <abs_source_root>.
# Never touches a real file/dir or a symlink pointing outside the given root.
unlink_if_repo_owned() {
  local target="$1"
  local source_root="$2"
  [[ -L "$target" ]] || return 0
  local resolved
  resolved="$(readlink "$target")"
  case "$resolved" in
    "$source_root"|"$source_root"/*)
      rm "$target"
      echo "  - removed $target"
      ;;
  esac
}

# Inline @<prefix>/<file>.md references in <source_file> by reading the file
# from <root>/<prefix>/<file>.md and writing the expanded result to <output_file>.
# Multiple <prefix>=<root> pairs may be passed; unknown prefixes are passed
# through untouched.
inline_imports() {
  local source_file="$1"
  local output_file="$2"
  shift 2

  local roots=""
  local pair
  for pair in "$@"; do
    [[ -n "$roots" ]] && roots+=":"
    roots+="$pair"
  done

  awk -v roots="$roots" '
    BEGIN {
      n = split(roots, pairs, ":")
      for (i = 1; i <= n; i++) {
        eq = index(pairs[i], "=")
        if (eq > 0) {
          p = substr(pairs[i], 1, eq - 1)
          r = substr(pairs[i], eq + 1)
          root_for[p] = r
        }
      }
    }
    /^- @[A-Za-z0-9_-]+\/[^ ]+\.md/ {
      if (match($0, /@[A-Za-z0-9_-]+\/[^ ]+\.md/)) {
        rel = substr($0, RSTART + 1, RLENGTH - 1)
        slash = index(rel, "/")
        prefix = substr(rel, 1, slash - 1)
        if (prefix in root_for) {
          full = root_for[prefix] "/" rel
          print ""
          print "<!-- inlined from " rel " -->"
          while ((getline line < full) > 0) {
            print line
          }
          close(full)
          print ""
          next
        }
      }
    }
    { print }
  ' "$source_file" > "$output_file"
}

# ----------------------------------------------------------------------------
# MCP server registration helpers
# ----------------------------------------------------------------------------

# Idempotently install a Node MCP server from npm globally.
# Args: <pkg> <bin>
# Stdout: absolute path to the bin (on success).
# Returns: 0 on success, 1 if install failed or bin not on PATH afterwards.
ensure_npm_global() {
  local pkg="$1"
  local bin="$2"

  if ! command -v npm >/dev/null 2>&1; then
    echo "  ! npm not on PATH; cannot install $pkg" >&2
    return 1
  fi

  if command -v "$bin" >/dev/null 2>&1; then
    echo "  = $pkg ($bin already on PATH)" >&2
    command -v "$bin"
    return 0
  fi

  echo "  installing $pkg ..." >&2
  if ! npm install -g "$pkg" >/dev/null 2>&1; then
    echo "  ! npm install -g $pkg failed" >&2
    return 1
  fi

  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "  ! $pkg installed but $bin still not on PATH" >&2
    return 1
  fi

  echo "  + installed $pkg" >&2
  command -v "$bin"
}

# Read the current value of an env key in ~/.claude.json mcpServers.<name>.env.
# Args: <name> <env_key>
# Stdout: value or empty string if not found.
existing_mcp_env_claude() {
  local name="$1"
  local key="$2"
  [[ -f "$CLAUDE_CONFIG" ]] || return 0
  jq -r --arg name "$name" --arg key "$key" \
    '.mcpServers[$name].env[$key] // ""' "$CLAUDE_CONFIG" 2>/dev/null
}

# Resolve an OAuth token by precedence:
#   1. exported shell env var named <env_var>
#   2. existing value in ~/.claude.json mcpServers.<mcp_name>.env.<env_var>
#   3. interactive prompt on /dev/tty (silent input — token is not echoed)
#   4. empty string (when no TTY available, or user just hits Enter)
#
# Args: <env_var_name> <mcp_name> <prompt_label> [<hint>]
#   <hint>: optional one-line reminder of where to mint the token (URL,
#           CLI command, etc.). Shown only when the interactive prompt
#           actually fires; ignored when shell/config already supplied
#           a value.
# Stdout: resolved token value (or empty string).
# Stderr: status line per source ("from $VAR", "preserved", "skipped — no TTY"),
#         or the prompt itself.
prompt_or_resolve_token() {
  local env_var="$1"
  local mcp_name="$2"
  local label="$3"
  local hint="${4:-}"

  local current="${!env_var:-}"
  if [[ -n "$current" ]]; then
    printf '  %-22s [from $%s]\n' "$label" "$env_var" >&2
    printf '%s' "$current"
    return 0
  fi

  local existing
  existing="$(existing_mcp_env_claude "$mcp_name" "$env_var")"
  if [[ -n "$existing" ]]; then
    printf '  %-22s [preserved from existing config]\n' "$label" >&2
    printf '%s' "$existing"
    return 0
  fi

  if ! { : > /dev/tty; } 2>/dev/null; then
    printf '  %-22s [skipped — no TTY]\n' "$label" >&2
    return 0
  fi

  local val=""
  if [[ -n "$hint" ]]; then
    printf '  %s\n    where to get: %s\n  Enter to skip: ' "$label" "$hint" > /dev/tty
  else
    printf '  %s (Enter to skip): ' "$label" > /dev/tty
  fi
  IFS= read -r -s val < /dev/tty || val=""
  printf '\n' > /dev/tty
  printf '%s' "$val"
}

_backup_claude_config_once() {
  if [[ "$CLAUDE_CONFIG_BACKED_UP" -eq 0 ]]; then
    if [[ -f "$CLAUDE_CONFIG" ]]; then
      cp "$CLAUDE_CONFIG" "${CLAUDE_CONFIG}.bak.${TS}"
      echo "  ~ backed up $CLAUDE_CONFIG -> ${CLAUDE_CONFIG}.bak.${TS}"
    fi
    CLAUDE_CONFIG_BACKED_UP=1
  fi
}

_backup_codex_config_once() {
  if [[ "$CODEX_CONFIG_BACKED_UP" -eq 0 ]]; then
    if [[ -f "$CODEX_CONFIG_TOML" ]]; then
      cp "$CODEX_CONFIG_TOML" "${CODEX_CONFIG_TOML}.bak.${TS}"
      echo "  ~ backed up $CODEX_CONFIG_TOML -> ${CODEX_CONFIG_TOML}.bak.${TS}"
    fi
    CODEX_CONFIG_BACKED_UP=1
  fi
}

# Register an MCP server in ~/.claude.json mcpServers.<name>.
# Args:
#   $1 = name (key in mcpServers)
#   $2 = command (string)
#   $3 = args   as JSON array string (e.g. '[]' or '["--foo","bar"]')
#   $4 = env    as JSON object string (e.g. '{}' or '{"K":"v"}')
# Idempotent: backs up ~/.claude.json once per run, then upserts.
register_mcp_claude() {
  local name="$1"
  local command="$2"
  local args_json="$3"
  local env_json="$4"
  [[ -z "$args_json" ]] && args_json='[]'
  [[ -z "$env_json"  ]] && env_json='{}'

  if ! command -v jq >/dev/null 2>&1; then
    echo "  ! jq required to register MCP $name in claude config" >&2
    return 1
  fi

  mkdir -p "$(dirname "$CLAUDE_CONFIG")"
  if [[ ! -f "$CLAUDE_CONFIG" ]]; then
    echo '{}' > "$CLAUDE_CONFIG"
  fi

  _backup_claude_config_once

  local tmp
  tmp="$(mktemp)"
  if jq --arg name "$name" \
        --arg command "$command" \
        --argjson args "$args_json" \
        --argjson env "$env_json" '
    .mcpServers //= {}
    | .mcpServers[$name] = (
        {type: "stdio", command: $command}
        + (if ($args | length) > 0 then {args: $args} else {} end)
        + (if ($env | length) > 0 then {env: $env} else {} end)
      )
  ' "$CLAUDE_CONFIG" > "$tmp"; then
    mv "$tmp" "$CLAUDE_CONFIG"
    echo "  + claude MCP $name -> $command"
  else
    rm -f "$tmp"
    echo "  ! jq update failed for claude MCP $name (config left untouched)" >&2
    return 1
  fi
}

# Register an MCP server in ~/.codex/config.toml [mcp_servers.<name>].
# Args: same shape as register_mcp_claude.
# Removes any existing [mcp_servers.<name>] and [mcp_servers.<name>.env]
# blocks first, then appends fresh ones.
register_mcp_codex() {
  local name="$1"
  local command="$2"
  local args_json="$3"
  local env_json="$4"
  [[ -z "$args_json" ]] && args_json='[]'
  [[ -z "$env_json"  ]] && env_json='{}'

  if ! command -v jq >/dev/null 2>&1; then
    echo "  ! jq required to register MCP $name in codex config" >&2
    return 1
  fi

  mkdir -p "$(dirname "$CODEX_CONFIG_TOML")"
  [[ -f "$CODEX_CONFIG_TOML" ]] || : > "$CODEX_CONFIG_TOML"

  _backup_codex_config_once

  local target_regex='^\\[mcp_servers\\.'"$name"'(\\.env)?\\][[:space:]]*$'
  local tmp
  tmp="$(mktemp)"
  awk -v target="$target_regex" '
    BEGIN { skip = 0 }
    /^\[/ {
      if (match($0, target)) { skip = 1; next }
      skip = 0
    }
    !skip
  ' "$CODEX_CONFIG_TOML" > "$tmp"

  # Trim trailing blank lines so we add exactly one separator.
  awk 'BEGIN { blank = 0 } /^$/ { blank++; next } { for (i=0;i<blank;i++) print ""; blank=0; print } END {}' "$tmp" > "${tmp}.trim"
  mv "${tmp}.trim" "$tmp"

  {
    if [[ -s "$tmp" ]]; then
      cat "$tmp"
      printf '\n'
    fi
    printf '[mcp_servers.%s]\n' "$name"
    # command line — JSON-quote produces a TOML-safe basic string.
    printf 'command = '
    jq -n --arg v "$command" '$v'
    # args
    local args_count
    args_count="$(printf '%s' "$args_json" | jq 'length')"
    if [[ "$args_count" -gt 0 ]]; then
      printf 'args = '
      printf '%s\n' "$args_json"
    fi
    # env block
    local env_keys
    env_keys="$(printf '%s' "$env_json" | jq -r 'keys_unsorted[]?' || true)"
    if [[ -n "$env_keys" ]]; then
      printf '\n[mcp_servers.%s.env]\n' "$name"
      while IFS= read -r key; do
        local val
        val="$(printf '%s' "$env_json" | jq -r --arg k "$key" '.[$k]')"
        printf '%s = ' "$key"
        jq -n --arg v "$val" '$v'
      done <<< "$env_keys"
    fi
  } > "${tmp}.out"

  mv "${tmp}.out" "$CODEX_CONFIG_TOML"
  rm -f "$tmp"
  echo "  + codex MCP $name -> $command"
}

# Build a JSON array of strings from positional args.
# Usage: json_str_array a b c   →   ["a","b","c"]
json_str_array() {
  if [[ $# -eq 0 ]]; then
    printf '[]'
    return
  fi
  printf '%s' "$@" | jq -Rs --null-input '[$ARGS.positional[]]' --args -- "$@"
}

# Build a JSON object {KEY: VALUE, ...} from KEY=VALUE positional args.
# Empty values are KEPT (caller decides).
# Usage: json_str_object FOO=1 BAR=2   →   {"FOO":"1","BAR":"2"}
json_str_object() {
  if [[ $# -eq 0 ]]; then
    printf '{}'
    return
  fi
  jq -n --args '
    [$ARGS.positional[]
      | capture("^(?<k>[^=]+)=(?<v>.*)$")
      | {(.k): .v}
    ] | add // {}
  ' -- "$@"
}
