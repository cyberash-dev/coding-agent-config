#!/usr/bin/env bash
# Reusable helpers for coding-agent-config and downstream extension repos.
# Source this file from a driver script that orchestrates installation
# and build steps.
#
# Idempotent: safe to source multiple times; globals are initialised once.
#
# Public API (functions):
#   install_tree <source_dir> <target_dir>
#   install_file <source> <target>
#   remove_installed_tree <target_dir>
#   write_generated <target> <content>
#   install_hook <script> <matcher> <event>
#   remove_hook <script|basename> <event>
#   install_permission_rules <allow|deny|ask> <rule> [<rule>...]
#   install_teams_env <0|1>
#   install_codex_subagents <0|1>
#   install_codex_review_hook <0|1>
#   install_codex_review_home <0|1> <repo_root> <home_dir> <codex_config_dir>
#   install_cursor_hook <script> <event> [<matcher>]
#   remove_cursor_hook <script|basename> <event>
#   install_cursor_review_hook <0|1>
#   dedupe_hooks / dedupe_cursor_hooks
#   install_codex_review_skills <0|1> <source_root> <target_root>
#   install_skills <source_root> <target_root>
#   cleanup_legacy_codex_skills <source_root> [<source_root>...]
#   inline_imports <source_file> <output_file> <prefix>=<root> [<prefix>=<root>...]
#   build_cursor_rules <index_file> <rules_root> <out_dir>
#   write_cursor_rule <out_file> <description> <body_file>
#   teams_section <0|1> <templates_dir>
#   language_section <lang> <templates_dir>
#   ensure_agent_sdd
#   mcp_launch_spec <pkg> <bin>
#   register_core_mcp_claude / register_core_mcp_codex / register_core_mcp_cursor
#
# `ensure_mcp_npm_global <pkg> <bin>` comes from lib/npm-mcp-updates.sh and
# `os_kind` / `is_windows` / `agent_home` / `native_path` from lib/platform.sh,
# both sourced below.
#
# Public globals (set on first source):
#   TS                   — install timestamp, used for `.bak.<TS>` backups
#   AGENT_CONFIG_MANIFEST — name of the per-directory ownership manifest
#   SETTINGS             — path to $AGENT_HOME/.claude/settings.json
#   CURSOR_HOOKS         — path to $AGENT_HOME/.cursor/hooks.json
#   CURSOR_MCP           — path to $AGENT_HOME/.cursor/mcp.json
#   SETTINGS_BACKED_UP   — 0/1 flag, mutated by every $SETTINGS writer; also set
#                          when the installer created the file itself, so an
#                          empty scaffold is never backed up
#
# Targets are anchored at $AGENT_HOME (see lib/platform.sh), which equals $HOME
# everywhere except native Windows.

_AGENT_CONFIG_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=platform.sh
source "$_AGENT_CONFIG_LIB_DIR/platform.sh"
# shellcheck source=npm-mcp-updates.sh
source "$_AGENT_CONFIG_LIB_DIR/npm-mcp-updates.sh"

if [[ -z "${AGENT_CONFIG_LIB_LOADED:-}" ]]; then
  AGENT_CONFIG_LIB_LOADED=1

  TS="$(date +%s)"
  AGENT_CONFIG_MANIFEST=".coding-agent-config"
  SETTINGS="$AGENT_HOME/.claude/settings.json"
  SETTINGS_BACKED_UP=0

  CLAUDE_CONFIG="$AGENT_HOME/.claude.json"
  CLAUDE_CONFIG_BACKED_UP=0

  CODEX_CONFIG_TOML="${CODEX_HOME:-$AGENT_HOME/.codex}/config.toml"
  CODEX_CONFIG_BACKED_UP=0

  CURSOR_HOOKS="$AGENT_HOME/.cursor/hooks.json"
  CURSOR_HOOKS_BACKED_UP=0

  CURSOR_MCP="$AGENT_HOME/.cursor/mcp.json"
  CURSOR_MCP_BACKED_UP=0
fi

# Back up $SETTINGS once per install run (first mutation only).
_backup_settings_once() {
  if [[ "$SETTINGS_BACKED_UP" -eq 0 ]]; then
    cp "$SETTINGS" "${SETTINGS}.bak.${TS}"
    echo "  ~ backed up $SETTINGS -> ${SETTINGS}.bak.${TS}"
    SETTINGS_BACKED_UP=1
  fi
}

# Same for a JSON file, comparing by value rather than by bytes: the agents
# rewrite their own config with their own formatting between installs, and
# reformatting it back would rewrite the file (and back it up) on every run.
_replace_json_if_changed() {
  local file="$1"
  local candidate="$2"
  local backup_fn="$3"

  if cmp -s <(jq -S . "$candidate" 2>/dev/null) <(jq -S . "$file" 2>/dev/null); then
    rm -f "$candidate"
    return 1
  fi

  _replace_if_changed "$file" "$candidate" "$backup_fn"
}

# Replace <file> with the freshly built <candidate> only when the content really
# differs, so a repeat install neither rewrites config nor leaves another backup
# behind. Returns 1 when the file was already what the installer wanted.
_replace_if_changed() {
  local file="$1"
  local candidate="$2"
  local backup_fn="$3"

  if cmp -s "$candidate" "$file"; then
    rm -f "$candidate"
    return 1
  fi

  "$backup_fn"
  mv "$candidate" "$file"
  return 0
}

_backup_cursor_hooks_once() {
  if [[ "$CURSOR_HOOKS_BACKED_UP" -eq 0 ]]; then
    cp "$CURSOR_HOOKS" "${CURSOR_HOOKS}.bak.${TS}"
    echo "  ~ backed up $CURSOR_HOOKS -> ${CURSOR_HOOKS}.bak.${TS}"
    CURSOR_HOOKS_BACKED_UP=1
  fi
}

_backup_cursor_mcp_once() {
  if [[ "$CURSOR_MCP_BACKED_UP" -eq 0 ]]; then
    cp "$CURSOR_MCP" "${CURSOR_MCP}.bak.${TS}"
    echo "  ~ backed up $CURSOR_MCP -> ${CURSOR_MCP}.bak.${TS}"
    CURSOR_MCP_BACKED_UP=1
  fi
}

# Copy <source_dir> into <target_dir>. Files identical to the source are left
# alone, so a repeat install writes nothing. What the installer put there is
# recorded in <target_dir>/.coding-agent-config, which lets the next run take
# its own files back out (a rule dropped from the index, a bundle switched off)
# without touching anything the user keeps in the same directory.
install_tree() {
  local source="$1"
  local target="$2"

  if [[ ! -d "$source" ]]; then
    echo "install-lib: source missing: $source" >&2
    exit 1
  fi

  _clear_linked_target "$target" "$source"
  mkdir -p "$target"

  local -a installed=()
  local copied=0 removed=0
  local rel
  while IFS= read -r rel; do
    installed+=("$rel")
    if _install_one_file "$source/$rel" "$target/$rel" "$target" "$rel"; then
      copied=$((copied + 1))
    fi
  done < <(_tree_files "$source")

  local previous
  while IFS= read -r previous; do
    [[ -n "$previous" ]] || continue
    if _array_has "$previous" ${installed[@]+"${installed[@]}"}; then
      continue
    fi
    [[ -e "$target/$previous" ]] || continue
    rm -f "$target/$previous"
    _prune_empty_dirs "$target" "$(dirname "$target/$previous")"
    echo "  - removed $target/$previous"
    removed=$((removed + 1))
  done < <(_manifest_read "$target")

  _manifest_write "$target" ${installed[@]+"${installed[@]}"}

  if [[ "$copied" -eq 0 && "$removed" -eq 0 ]]; then
    echo "  = $target (up to date)"
  else
    echo "  + $target ($copied copied, $removed removed)"
  fi
}

# Copy a single generated file into place, with the same ownership record as
# install_tree so only a file the user wrote by hand is ever backed up.
install_file() {
  local source="$1"
  local target="$2"

  if [[ ! -f "$source" ]]; then
    echo "install-lib: source missing: $source" >&2
    exit 1
  fi

  _clear_linked_target "$target" "$source"

  local dir base
  dir="$(dirname "$target")"
  base="$(basename "$target")"
  mkdir -p "$dir"

  if _install_one_file "$source" "$target" "$dir" "$base"; then
    echo "  + $target (copied)"
  else
    echo "  = $target (up to date)"
  fi
  _manifest_add "$dir" "$base"
}

# Remove the files this repo installed under <target_dir> and nothing else.
# The directory itself goes only if it is left empty.
remove_installed_tree() {
  local target="$1"
  [[ -d "$target" ]] || return 0

  local rel removed=0
  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    [[ -e "$target/$rel" ]] || continue
    rm -f "$target/$rel"
    _prune_empty_dirs "$target" "$(dirname "$target/$rel")"
    removed=$((removed + 1))
  done < <(_manifest_read "$target")

  rm -f "$(_manifest_path "$target")"
  rmdir "$target" 2>/dev/null || true

  if [[ "$removed" -gt 0 ]]; then
    echo "  - removed $target"
  fi
  return 0
}

# Copy <src> to <dst> unless they already match. Returns 0 when the file was
# written, 1 when it was already in place.
_install_one_file() {
  local src="$1"
  local dst="$2"
  local target="$3"
  local rel="$4"

  if [[ -f "$dst" ]] && cmp -s "$src" "$dst"; then
    return 1
  fi

  mkdir -p "$(dirname "$dst")"
  if [[ -e "$dst" || -L "$dst" ]] && ! _manifest_owns "$target" "$rel"; then
    mv "$dst" "${dst}.bak.${TS}"
    echo "  ~ backed up $dst -> ${dst}.bak.${TS}"
  fi
  cp -p "$src" "$dst"
  return 0
}

# Paths of every file under <dir>, relative to it. What .gitignore keeps out of
# the repo is kept out of the install too: a copy would otherwise carry the
# local build junk of whoever ran install.sh.
_tree_files() {
  (cd "$1" && find . \( -name .git -o -name __pycache__ \) -prune -o \
      -type f ! -name '*.pyc' ! -name '.DS_Store' ! -name '*.bak.*' -print) \
    | sed 's|^\./||' | LC_ALL=C sort
}

# Drop directories the removals just emptied, walking up to <root> and stopping
# at the first one that still holds something.
_prune_empty_dirs() {
  local root="$1"
  local dir="$2"

  while [[ "$dir" != "$root" && "$dir" == "$root"/* ]]; do
    rmdir "$dir" 2>/dev/null || break
    dir="$(dirname "$dir")"
  done
}

_array_has() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

# An earlier version of this installer symlinked the repo into place. Take that
# link out before the copy lands. A junction is unlinked rather than moved
# aside: `mv` on a junction walks into it and drags the contents out of the repo.
_clear_linked_target() {
  local target="$1"
  local source="$2"

  if is_windows && is_junction "$target"; then
    remove_junction "$target"
    echo "  - unlinked $target (copied from now on)"
    return 0
  fi

  [[ -L "$target" ]] || return 0

  if [[ "$(readlink "$target")" == "$source" ]]; then
    rm -f "$target"
    echo "  - unlinked $target (copied from now on)"
    return 0
  fi

  mv "$target" "${target}.bak.${TS}"
  echo "  ~ backed up $target -> ${target}.bak.${TS}"
}

_manifest_path() {
  printf '%s/%s' "$1" "$AGENT_CONFIG_MANIFEST"
}

_manifest_read() {
  local manifest
  manifest="$(_manifest_path "$1")"
  [[ -f "$manifest" ]] || return 0
  cat "$manifest"
}

_manifest_owns() {
  _manifest_read "$1" | grep -Fxq -- "$2"
}

_manifest_write() {
  local target="$1"
  shift

  local manifest
  manifest="$(_manifest_path "$target")"
  if [[ $# -eq 0 ]]; then
    rm -f "$manifest"
    return 0
  fi
  printf '%s\n' "$@" > "$manifest"
}

_manifest_add() {
  local target="$1"
  local entry="$2"

  if _manifest_owns "$target" "$entry"; then
    return 0
  fi
  printf '%s\n' "$entry" >> "$(_manifest_path "$target")"
}

# Write a file this installer owns. Recorded in the same manifest install_tree
# uses, so the first version of a file the user wrote by hand is backed up and
# later regenerations just overwrite what this installer put there.
write_generated() {
  local target="$1"
  local content="$2"

  local dir base
  dir="$(dirname "$target")"
  base="$(basename "$target")"
  mkdir -p "$dir"

  if [[ -f "$target" && ! -L "$target" ]] && [[ "$(cat "$target")" == "$content" ]]; then
    _manifest_add "$dir" "$base"
    echo "  = $target (up to date)"
    return 0
  fi

  if [[ -e "$target" || -L "$target" ]] && ! _manifest_owns "$dir" "$base"; then
    local backup="${target}.bak.${TS}"
    mv "$target" "$backup"
    echo "  ~ backed up $target -> $backup"
  fi

  printf '%s' "$content" > "$target"
  _manifest_add "$dir" "$base"
  echo "  + $target (generated)"
}

# jq helpers shared by both hook writers.
#   is_named     — an entry for a script with this file name, whoever wrote it
#   is_ours      — that name, installed from the directory this install uses
#   is_removable — what remove_hook may delete: ours, or any same-name entry
#                  when the caller passed a bare basename
_HOOK_JQ_HELPERS='
  def dirname: sub("/[^/]*$"; "");
  def is_named: (.command // "") as $c
    | ($c == $basename) or ($c | endswith("/" + $basename));
  def is_ours: is_named and ((.command // "") as $c
    | ($c == $script) or (($c | dirname) == $dir));
  def is_removable: is_named and (($dir == "")
    or ((.command // "") as $c | ($c == $script) or (($c | dirname) == $dir)));
'

# Collapse repeats of one command inside a single event, keeping the LAST
# registration. It is the current one — a tool that re-registers its hook under
# a new matcher finds its own entry next time and stops adding a second.
_HOOK_JQ_DEDUPE='
  def dedupe_event:
    . as $entries
    | ( reduce range(0; $entries | length) as $i ({};
          reduce (($entries[$i].hooks // [])[] | .command // "") as $command (.;
            .[$command] = $i) ) ) as $last
    | [ range(0; $entries | length) as $i
        | $entries[$i]
        | .hooks = [ (.hooks // [])[] | select($last[.command // ""] == $i) ]
        | select((.hooks | length) > 0) ];
'

_CURSOR_HOOK_JQ_DEDUPE='
  def dedupe_event:
    . as $entries
    | ( reduce range(0; $entries | length) as $i ({};
          .[$entries[$i].command // ""] = $i) ) as $last
    | [ range(0; $entries | length) as $i
        | select($last[$entries[$i].command // ""] == $i)
        | $entries[$i] ];
'

_warn_foreign_hooks() {
  local others="$1"
  local basename="$2"
  [[ -n "$others" ]] || return 0

  local other
  while IFS= read -r other; do
    [[ -n "$other" ]] || continue
    echo "  ! $other also registers $basename; left as is" >&2
  done <<< "$others"
}

# Idempotently register a hook in $SETTINGS.
#
# Ownership: an entry belongs to this installer when its command is the script
# being installed, or another script of the same name from the same directory.
# Those entries are taken out of every event first, so a hook that moved to a
# different event does not stay registered on the old one. A same-name hook
# pointing at a path the user owns is left alone with a warning — two different
# scripts may legitimately share a file name. Repeats of one command inside the
# target event, whoever wrote them, collapse to the first one.
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
    SETTINGS_BACKED_UP=1
  fi

  # The agent reads settings.json as a native process, so the command has to be
  # a path it can resolve. On Windows a shell-form hook falls back to PowerShell
  # when Git Bash is missing, where a .sh script cannot run — name the shell so
  # that failure is legible instead of silent.
  local command_path shell dir
  command_path="$(native_path "$script")"
  dir="$(dirname "$command_path")"
  shell=""
  if is_windows; then
    shell="bash"
  fi

  _warn_foreign_hooks "$(jq -r \
    --arg script "$command_path" --arg basename "$basename" --arg dir "$dir" \
    "$_HOOK_JQ_HELPERS"'
    [ (.hooks // {}) | to_entries[] | .value[]? | (.hooks // [])[]?
      | select(is_named and (is_ours | not)) | .command ]
    | unique | .[]
  ' "$SETTINGS")" "$basename"

  local tmp
  tmp="$(mktemp)"
  jq --arg script "$command_path" \
     --arg matcher "$matcher" \
     --arg event "$event" \
     --arg basename "$basename" \
     --arg dir "$dir" \
     --arg shell "$shell" \
     "$_HOOK_JQ_HELPERS$_HOOK_JQ_DEDUPE"'
    .hooks //= {}
    | .hooks[$event] //= []
    | ( [ .hooks[$event] | to_entries[]
          | select((.value.hooks // []) | any(is_ours)) | .key ] | first ) as $at
    | .hooks |= with_entries(
        .value |= ( map(.hooks |= map(select(is_ours | not)))
                    | map(select((.hooks // []) | length > 0)) )
      )
    | .hooks[$event] //= []
    | .hooks[$event] |= dedupe_event
    | ( {hooks: [ ({type: "command", command: $script}
                   + (if $shell == "" then {} else {shell: $shell} end)) ]}
        + (if $matcher == "" then {} else {matcher: $matcher} end) ) as $entry
    | .hooks[$event] |= (if $at == null then . + [$entry] else .[0:$at] + [$entry] + .[$at:] end)
  ' "$SETTINGS" > "$tmp"
  if _replace_json_if_changed "$SETTINGS" "$tmp" _backup_settings_once; then
    echo "  + hook $event${matcher:+ ($matcher)} -> $command_path"
  else
    echo "  = hook $event${matcher:+ ($matcher)} -> $command_path (registered)"
  fi
}

# Drop hook entries for <script> from <event>. Pass the installed path to keep a
# same-name hook the user owns; a bare basename matches on the name alone.
remove_hook() {
  local script="$1"
  local event="$2"

  [[ -f "$SETTINGS" ]] || return 0

  if ! command -v jq >/dev/null 2>&1; then
    echo "install-lib: jq is required to manage hooks" >&2
    exit 1
  fi

  local basename command_path dir
  basename="$(basename "$script")"
  command_path=""
  dir=""
  if [[ "$script" == */* ]]; then
    command_path="$(native_path "$script")"
    dir="$(dirname "$command_path")"
  fi

  local tmp
  tmp="$(mktemp)"
  jq --arg event "$event" --arg script "$command_path" \
     --arg basename "$basename" --arg dir "$dir" \
     "$_HOOK_JQ_HELPERS"'
    .hooks //= {}
    | if .hooks[$event] then
        .hooks[$event] |= (
          map(.hooks |= map(select(is_removable | not)))
          | map(select((.hooks // []) | length > 0))
        )
      else . end
  ' "$SETTINGS" > "$tmp"
  if _replace_json_if_changed "$SETTINGS" "$tmp" _backup_settings_once; then
    echo "  - hook $event ($basename) removed"
  fi
}

# Idempotently register a hook in ~/.cursor/hooks.json. Cursor has its own hook
# protocol — different event names, a flat entry per event, `permission` instead
# of `permissionDecision` — so it gets its own writer rather than a second
# target for install_hook. Ownership and de-duplication work as they do there.
install_cursor_hook() {
  local script="$1"
  local event="$2"
  local matcher="${3:-}"
  local basename
  basename="$(basename "$script")"

  if ! command -v jq >/dev/null 2>&1; then
    echo "install-lib: jq is required to register hooks" >&2
    exit 1
  fi

  mkdir -p "$(dirname "$CURSOR_HOOKS")"
  if [[ ! -f "$CURSOR_HOOKS" ]]; then
    echo '{"version": 1, "hooks": {}}' > "$CURSOR_HOOKS"
    CURSOR_HOOKS_BACKED_UP=1
  fi

  local command_path dir
  command_path="$(native_path "$script")"
  dir="$(dirname "$command_path")"

  _warn_foreign_hooks "$(jq -r \
    --arg script "$command_path" --arg basename "$basename" --arg dir "$dir" \
    "$_HOOK_JQ_HELPERS"'
    [ (.hooks // {}) | to_entries[] | .value[]?
      | select(is_named and (is_ours | not)) | .command ]
    | unique | .[]
  ' "$CURSOR_HOOKS")" "$basename"

  local tmp
  tmp="$(mktemp)"
  jq --arg script "$command_path" \
     --arg matcher "$matcher" \
     --arg event "$event" \
     --arg basename "$basename" \
     --arg dir "$dir" \
     "$_HOOK_JQ_HELPERS$_CURSOR_HOOK_JQ_DEDUPE"'
    .version = 1
    | .hooks //= {}
    | .hooks[$event] //= []
    | ( [ .hooks[$event] | to_entries[] | select(.value | is_ours) | .key ] | first ) as $at
    | .hooks |= with_entries(.value |= map(select(is_ours | not)))
    | .hooks[$event] //= []
    | .hooks[$event] |= dedupe_event
    | ( {command: $script}
        + (if $matcher == "" then {} else {matcher: $matcher} end) ) as $entry
    | .hooks[$event] |= (if $at == null then . + [$entry] else .[0:$at] + [$entry] + .[$at:] end)
  ' "$CURSOR_HOOKS" > "$tmp"
  if _replace_json_if_changed "$CURSOR_HOOKS" "$tmp" _backup_cursor_hooks_once; then
    echo "  + cursor hook $event${matcher:+ ($matcher)} -> $command_path"
  else
    echo "  = cursor hook $event${matcher:+ ($matcher)} -> $command_path (registered)"
  fi
}

# Drop ~/.cursor/hooks.json entries for <script> from <event>. Same argument
# rule as remove_hook: a path keeps a same-name hook the user owns.
remove_cursor_hook() {
  local script="$1"
  local event="$2"

  [[ -f "$CURSOR_HOOKS" ]] || return 0

  if ! command -v jq >/dev/null 2>&1; then
    echo "install-lib: jq is required to manage hooks" >&2
    exit 1
  fi

  local basename command_path dir
  basename="$(basename "$script")"
  command_path=""
  dir=""
  if [[ "$script" == */* ]]; then
    command_path="$(native_path "$script")"
    dir="$(dirname "$command_path")"
  fi

  local tmp
  tmp="$(mktemp)"
  jq --arg event "$event" --arg script "$command_path" \
     --arg basename "$basename" --arg dir "$dir" \
     "$_HOOK_JQ_HELPERS"'
    if .hooks[$event] then
      .hooks[$event] |= map(select(is_removable | not))
    else . end
  ' "$CURSOR_HOOKS" > "$tmp"
  if _replace_json_if_changed "$CURSOR_HOOKS" "$tmp" _backup_cursor_hooks_once; then
    echo "  - cursor hook $event ($basename) removed"
  fi
}

# Collapse duplicate hook registrations across every event of $SETTINGS.
# install_hook already does this for the event it writes; this runs at the end
# of an install because a tool that merges its own hooks afterwards (agent-sdd)
# can add a second entry for a script already registered under a wider matcher.
dedupe_hooks() {
  [[ -f "$SETTINGS" ]] || return 0
  command -v jq >/dev/null 2>&1 || return 0

  local tmp
  tmp="$(mktemp)"
  jq "$_HOOK_JQ_DEDUPE"'
    if .hooks then .hooks |= with_entries(.value |= dedupe_event) else . end
  ' "$SETTINGS" > "$tmp"
  if _replace_json_if_changed "$SETTINGS" "$tmp" _backup_settings_once; then
    echo "  - collapsed duplicate hook registrations in $SETTINGS"
  fi
}

dedupe_cursor_hooks() {
  [[ -f "$CURSOR_HOOKS" ]] || return 0
  command -v jq >/dev/null 2>&1 || return 0

  local tmp
  tmp="$(mktemp)"
  jq "$_CURSOR_HOOK_JQ_DEDUPE"'
    if .hooks then .hooks |= with_entries(.value |= dedupe_event) else . end
  ' "$CURSOR_HOOKS" > "$tmp"
  if _replace_json_if_changed "$CURSOR_HOOKS" "$tmp" _backup_cursor_hooks_once; then
    echo "  - collapsed duplicate hook registrations in $CURSOR_HOOKS"
  fi
}

# Append rules to ~/.claude/settings.json permissions.<action>, preserving
# anything the user added by hand. Idempotent: rules already present are
# left alone. Action must be one of allow|deny|ask.
install_permission_rules() {
  local action="$1"
  shift
  local rules=("$@")

  case "$action" in
    allow|deny|ask) ;;
    *)
      echo "install-lib: install_permission_rules: invalid action '$action' (allow|deny|ask)" >&2
      return 1
      ;;
  esac

  [[ ${#rules[@]} -gt 0 ]] || return 0

  if ! command -v jq >/dev/null 2>&1; then
    echo "install-lib: jq is required to manage permissions" >&2
    exit 1
  fi

  mkdir -p "$(dirname "$SETTINGS")"
  if [[ ! -f "$SETTINGS" ]]; then
    echo '{}' > "$SETTINGS"
    SETTINGS_BACKED_UP=1
  fi

  local rules_json
  rules_json="$(printf '%s\n' "${rules[@]}" | jq -R . | jq -s .)"

  local added
  added="$(jq -r \
    --arg action "$action" \
    --argjson rules "$rules_json" '
      ((.permissions[$action] // []) | unique) as $cur
      | ($rules - $cur) | length
    ' "$SETTINGS")"

  if [[ "$added" == "0" ]]; then
    echo "  = permissions.$action up to date (${#rules[@]} rule(s) already present)"
    return 0
  fi

  _backup_settings_once

  local tmp
  tmp="$(mktemp)"
  jq --arg action "$action" --argjson rules "$rules_json" '
    .permissions //= {}
    | .permissions[$action] //= []
    | .permissions[$action] = ((.permissions[$action] + $rules) | unique)
  ' "$SETTINGS" > "$tmp"
  mv "$tmp" "$SETTINGS"
  echo "  + permissions.$action +$added rule(s)"
}

# Set or clear CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS in the env block of
# ~/.claude/settings.json. Symmetric with the driver's --teams flag: 1 sets the
# key, 0 removes it. Idempotent — no backup/write when already in the desired
# state.
install_teams_env() {
  local enabled="$1"
  echo "[claude] agent-teams env"

  local key="CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"

  if ! command -v jq >/dev/null 2>&1; then
    echo "install-lib: jq is required to manage the env block" >&2
    exit 1
  fi

  mkdir -p "$(dirname "$SETTINGS")"
  if [[ ! -f "$SETTINGS" ]]; then
    echo '{}' > "$SETTINGS"
    SETTINGS_BACKED_UP=1
  fi

  local current
  current="$(jq -r --arg k "$key" '.env[$k] // ""' "$SETTINGS")"

  if [[ "$enabled" -eq 1 ]]; then
    if [[ "$current" == "1" ]]; then
      echo "  = env.$key already set"
      return 0
    fi
    _backup_settings_once
    local tmp
    tmp="$(mktemp)"
    jq --arg k "$key" '.env //= {} | .env[$k] = "1"' "$SETTINGS" > "$tmp"
    mv "$tmp" "$SETTINGS"
    echo "  + env.$key=1"
  else
    if [[ -z "$current" ]]; then
      echo "  = env.$key absent"
      return 0
    fi
    _backup_settings_once
    local tmp
    tmp="$(mktemp)"
    jq --arg k "$key" 'del(.env[$k])' "$SETTINGS" > "$tmp"
    mv "$tmp" "$SETTINGS"
    echo "  - env.$key removed"
  fi
}

# Make Codex able to delegate: the `multi_agent` feature and `agents.enabled`
# are two independent gates, and either one left off keeps `spawn_agent` away
# from the model. Asymmetric with the driver's --teams flag on purpose: 0 leaves
# the config alone, because both gates default to on and clearing them would
# silently undo a deliberate opt-out. Idempotent — nothing is written when both
# gates are already on.
install_codex_subagents() {
  local enabled="$1"
  echo "[codex] sub-agents"

  if [[ "$enabled" -eq 0 ]]; then
    echo "  = config left as-is (--teams not requested)"
    return 0
  fi

  _enable_codex_multi_agent_feature
  _enable_codex_agents_key
}

# Turn the `multi_agent` feature on through codex itself: it owns a real TOML
# writer, so the key lands correctly whatever shape the file is in.
_enable_codex_multi_agent_feature() {
  if ! command -v codex >/dev/null 2>&1; then
    echo "  ! 'codex' not on PATH; cannot verify the multi_agent feature" >&2
    return 0
  fi

  # An older codex without `features list` must degrade to "state unknown", not
  # abort a driver running under `set -euo pipefail`.
  local codex_home state
  codex_home="$(dirname "$CODEX_CONFIG_TOML")"
  state="$(CODEX_HOME="$codex_home" codex features list 2>/dev/null \
    | awk '$1 == "multi_agent" { print $NF; exit }')" || state=""

  if [[ "$state" == "true" ]]; then
    echo "  = features.multi_agent already enabled"
    return 0
  fi

  _backup_codex_config_once
  if CODEX_HOME="$codex_home" codex features enable multi_agent >/dev/null 2>&1; then
    echo "  + features.multi_agent enabled"
  else
    echo "  ! 'codex features enable multi_agent' failed" >&2
  fi
}

# Set `agents.enabled = true`, in whichever shape the key already exists.
_enable_codex_agents_key() {
  if [[ "$(_codex_agents_enabled)" == "true" ]]; then
    echo "  = agents.enabled already true"
    return 0
  fi

  # An inline `agents = { ... }` owns the whole table, so neither appending a
  # [agents] header nor rewriting a dotted key is safe. Say so and change nothing.
  if [[ -f "$CODEX_CONFIG_TOML" ]] && grep -qE '^[[:space:]]*agents[[:space:]]*=' "$CODEX_CONFIG_TOML"; then
    echo "  ! agents is an inline table; set agents.enabled = true by hand" >&2
    return 0
  fi

  mkdir -p "$(dirname "$CODEX_CONFIG_TOML")"
  if [[ ! -f "$CODEX_CONFIG_TOML" ]]; then
    : > "$CODEX_CONFIG_TOML"
    CODEX_CONFIG_BACKED_UP=1
  fi

  _backup_codex_config_once

  local tmp
  tmp="$(mktemp)"
  awk '
    BEGIN { in_agents = 0; written = 0 }
    !written && /^[[:space:]]*agents\.enabled[[:space:]]*=/ {
      print "agents.enabled = true"
      written = 1
      next
    }
    /^[[:space:]]*\[/ {
      if (!written && $0 ~ /^[[:space:]]*\[agents\][[:space:]]*(#.*)?$/) {
        print
        print "enabled = true"
        in_agents = 1
        written = 1
        next
      }
      in_agents = 0
      print
      next
    }
    in_agents && /^[[:space:]]*enabled[[:space:]]*=/ { next }
    { print }
    END {
      if (!written) {
        if (NR > 0) print ""
        print "[agents]"
        print "enabled = true"
      }
    }
  ' "$CODEX_CONFIG_TOML" > "$tmp"
  mv "$tmp" "$CODEX_CONFIG_TOML"
  echo "  + agents.enabled=true"
}

# Current value of `agents.enabled`, or empty when it is not set. Reads both the
# `[agents]` table and the dotted top-level form; role subtables
# (`[agents.<name>]`) are a different table and are ignored.
_codex_agents_enabled() {
  [[ -f "$CODEX_CONFIG_TOML" ]] || return 0

  awk '
    BEGIN { in_agents = 0 }
    /^[[:space:]]*agents\.enabled[[:space:]]*=/ { key = $0 }
    /^[[:space:]]*\[/ { in_agents = ($0 ~ /^[[:space:]]*\[agents\][[:space:]]*(#.*)?$/); next }
    in_agents && /^[[:space:]]*enabled[[:space:]]*=/ { key = $0; exit }
    END {
      if (key == "") exit
      sub(/^[^=]*=[[:space:]]*/, "", key)
      sub(/[[:space:]]*(#.*)?$/, "", key)
      print key
    }
  ' "$CODEX_CONFIG_TOML"
}

# Register or drop the codex commit-review hook. Symmetric with the driver's
# --codex-review flag: 1 installs it, 0 removes it. Opt-in because it holds up
# every commit for a codex review and hands the findings back as a refusal, so
# the agent has to act on them before committing. The hook is fail-open and
# needs `codex` on PATH; without it every commit passes untouched.
install_codex_review_hook() {
  local enabled="$1"
  echo "[claude] codex commit review"

  if [[ "$enabled" -eq 0 ]]; then
    remove_hook "$AGENT_HOME/.claude/hooks/codex-commit-review.sh" "PreToolUse"
    echo "  = hook not requested (--codex-review)"
    return 0
  fi

  install_hook "$AGENT_HOME/.claude/hooks/codex-commit-review.sh" "Bash" "PreToolUse"

  if ! command -v codex >/dev/null 2>&1; then
    echo "  ! 'codex' not on PATH — the hook stays inert until it is installed" >&2
  fi
}

# Same switch for Cursor. The hook speaks Cursor's protocol through the
# cursor-commit-review.sh wrapper and is registered on beforeShellExecution.
install_cursor_review_hook() {
  local enabled="$1"
  echo "[cursor] codex commit review"

  if [[ "$enabled" -eq 0 ]]; then
    remove_cursor_hook "$AGENT_HOME/.cursor/hooks/cursor-commit-review.sh" "beforeShellExecution"
    echo "  = hook not requested (--codex-review)"
    return 0
  fi

  install_cursor_hook "$AGENT_HOME/.cursor/hooks/cursor-commit-review.sh" "beforeShellExecution"

  if is_windows; then
    echo "  ! Cursor gives a hook no shell selector; the script needs bash on PATH" >&2
  fi
  if ! command -v codex >/dev/null 2>&1; then
    echo "  ! 'codex' not on PATH — the hook stays inert until it is installed" >&2
  fi
}

# The codex process that runs a review gets a CODEX_HOME of its own. The
# operator's own home carries MCP servers, plugins, an interactive model and the
# full rule set, and every one of those is re-sent on each turn of the review;
# this one carries the review-scoped rules alone. The login is shared through a
# symlink, so the review still signs in as the operator and follows a token
# refresh.
install_codex_review_home() {
  local enabled="$1"
  local repo_root="$2"
  local home_dir="$3"
  local codex_config_dir="$4"
  echo "[codex] review home"

  if [[ "$enabled" -eq 0 ]]; then
    # Generated in full, plus whatever state codex kept next to it. The
    # config.toml is the proof this directory is ours before anything is removed.
    if [[ -f "$home_dir/config.toml" ]]; then
      rm -rf "$home_dir"
      echo "  - removed $home_dir"
    fi
    echo "  = review home not requested (--codex-review)"
    return 0
  fi

  # A model provider is declared in the operator's own config, and a home that
  # carries the login but not the provider would sign the review in against the
  # wrong endpoint. Leave that operator on the home that already works.
  if grep -qE '^[[:space:]]*(model_provider[[:space:]]*=|\[model_providers\.)' \
       "$codex_config_dir/config.toml" 2>/dev/null; then
    [[ -f "$home_dir/config.toml" ]] && rm -rf "$home_dir"
    echo "  = $codex_config_dir/config.toml selects a model provider; the review keeps the operator's home"
    return 0
  fi

  mkdir -p "$home_dir"
  inline_imports "$repo_root/templates/review/rules.md" "$home_dir/AGENTS.md" \
    "rules=$repo_root"

  # A review is a bounded, read-only pass over a diff: it needs no browser, and
  # a sub-agent fan-out would multiply the run by its own count. Depth it does
  # need — measured on this repo, a pass at medium missed a finding the deeper
  # one made. The model is left to codex's own default: what a review costs is
  # turns, and a cheaper model that needs more of them to reach the same finding
  # is not cheaper. CODEX_REVIEW_MODEL pins one per machine where the account
  # says otherwise.
  cat > "$home_dir/config.toml" <<'TOML'
# Generated by install.sh --codex-review. Edits are lost on the next install.
model_reasoning_effort = "high"

[features]
multi_agent = false

[tools]
web_search = false
TOML

  ln -sfn "$codex_config_dir/auth.json" "$home_dir/auth.json"
  echo "  + $home_dir"
}

# Install or drop the review skills under <target_root>. Symmetric with the
# driver's --codex-review flag: 1 links them, 0 removes the links this repo owns
# and leaves same-name skills the user wrote by hand alone. They ship with the
# hook because the hook runs its review pass through the codex-cli-review script.
install_codex_review_skills() {
  local enabled="$1"
  local source_root="$2"
  local target_root="$3"
  echo "[skills] codex review"

  if [[ "$enabled" -eq 1 ]]; then
    install_skills "$source_root" "$target_root"
    return 0
  fi

  local src
  for src in "$source_root"/*/; do
    [[ -d "$src" ]] || continue
    remove_installed_tree "$target_root/$(basename "$src")"
  done
  echo "  = skills not requested (--codex-review)"
}

# Copy each repo skill from <source_root>/* into <target_root>/<name>.
install_skills() {
  local source_root="$1"
  local target_root="$2"
  [[ -d "$source_root" ]] || return 0
  local src
  for src in "$source_root"/*/; do
    [[ -d "$src" ]] || continue
    local name
    name="$(basename "$src")"
    install_tree "${src%/}" "$target_root/$name"
  done
}

# Remove same-name symlinks under ~/.codex/skills that point at any of the
# given source roots. Removes the legacy ~/.codex/skills directory if empty.
cleanup_legacy_codex_skills() {
  local legacy_root="$AGENT_HOME/.codex/skills"
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
      if is_windows && is_junction "$legacy"; then
        remove_junction "$legacy"
      elif [[ -L "$legacy" ]]; then
        rm "$legacy"
      else
        continue
      fi
      echo "  - removed legacy Codex skill $legacy"
    done
  done

  rmdir "$legacy_root" 2>/dev/null || true
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

# Generate one Cursor rule per `- @rules/<name>.md — <description>` entry of
# <index_file>, reading bodies from <rules_root>/rules/ and writing
# <out_dir>/<name>.mdc. Cursor ignores plain .md in a rules directory, so the
# body is republished with frontmatter; `alwaysApply` is what an @-import in
# CLAUDE.md amounts to for Claude Code.
build_cursor_rules() {
  local index_file="$1"
  local rules_root="$2"
  local out_dir="$3"

  mkdir -p "$out_dir"

  local entry_re='^- @rules/([A-Za-z0-9_-]+)\.md([[:space:]]+—[[:space:]]+(.*))?$'
  local line name description body
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ $entry_re ]] || continue
    name="${BASH_REMATCH[1]}"
    description="${BASH_REMATCH[3]}"
    body="$rules_root/rules/$name.md"
    if [[ ! -f "$body" ]]; then
      echo "install-lib: rule missing: rules/$name.md" >&2
      exit 1
    fi
    write_cursor_rule "$out_dir/$name.mdc" "$description" "$body"
  done < "$index_file"
}

# Write a single Cursor rule: frontmatter, then the rule body verbatim. The
# description is quoted through jq — a JSON string is valid YAML, and rule
# descriptions carry colons.
write_cursor_rule() {
  local out_file="$1"
  local description="$2"
  local body_file="$3"

  {
    printf -- '---\n'
    if [[ -n "$description" ]]; then
      printf 'description: '
      jq -n --arg value "$description" '$value'
    fi
    printf 'alwaysApply: true\n'
    printf -- '---\n\n'
    cat "$body_file"
  } > "$out_file"
}

# Print the orchestration section for <enabled> (0|1), read from
# <templates_dir>/<off|on>.md. The off fragment is empty, so without --teams the
# section vanishes from the generated CLAUDE.md and AGENTS.md entirely.
teams_section() {
  local enabled="$1"
  local templates_dir="$2"
  local fragment=off
  [[ "$enabled" -eq 1 ]] && fragment=on
  local file="$templates_dir/${fragment}.md"
  if [[ ! -f "$file" ]]; then
    echo "install-lib: unknown teams fragment: $file" >&2
    exit 1
  fi
  cat "$file"
}

# Print the output-language directive section for <lang>, read from
# <templates_dir>/<lang>.md. <lang> is default|ru|en.
language_section() {
  local lang="$1"
  local templates_dir="$2"
  local file="$templates_dir/${lang}.md"
  if [[ ! -f "$file" ]]; then
    echo "install-lib: unknown language fragment: $file" >&2
    exit 1
  fi
  cat "$file"
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
    CLAUDE_CONFIG_BACKED_UP=1
  fi

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
    if _replace_json_if_changed "$CLAUDE_CONFIG" "$tmp" _backup_claude_config_once; then
      echo "  + claude MCP $name -> $command"
    else
      echo "  = claude MCP $name -> $command (registered)"
    fi
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
  if [[ ! -f "$CODEX_CONFIG_TOML" ]]; then
    : > "$CODEX_CONFIG_TOML"
    CODEX_CONFIG_BACKED_UP=1
  fi

  local block
  block="$(mktemp)"
  {
    printf '[mcp_servers.%s]\n' "$name"
    # command line — JSON-quote produces a TOML-safe basic string.
    printf 'command = '
    jq -n --arg v "$command" '$v'
    local args_count
    args_count="$(printf '%s' "$args_json" | jq 'length')"
    if [[ "$args_count" -gt 0 ]]; then
      printf 'args = '
      printf '%s\n' "$args_json"
    fi
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
  } > "$block"

  local header_regex='^\[mcp_servers\.'"$name"'(\.env)?\][[:space:]]*$'
  local tmp
  tmp="$(mktemp)"

  if grep -Eq "$header_regex" "$CODEX_CONFIG_TOML"; then
    # Rewrite the block where it already sits: appending it at the end instead
    # would shuffle it past whatever follows on every run.
    awk -v target="$header_regex" -v block="$block" '
      BEGIN { skip = 0; inserted = 0 }
      /^\[/ {
        if (match($0, target)) {
          skip = 1
          if (!inserted) {
            while ((getline line < block) > 0) { print line }
            close(block)
            inserted = 1
          }
          next
        }
        skip = 0
      }
      !skip
    ' "$CODEX_CONFIG_TOML" > "$tmp"
  else
    # Trim trailing blank lines so exactly one separator is added.
    awk 'BEGIN { blank = 0 } /^$/ { blank++; next } { for (i=0;i<blank;i++) print ""; blank=0; print }' \
      "$CODEX_CONFIG_TOML" > "$tmp"
    {
      [[ -s "$tmp" ]] && printf '\n'
      cat "$block"
    } >> "$tmp"
  fi
  rm -f "$block"

  if _replace_if_changed "$CODEX_CONFIG_TOML" "$tmp" _backup_codex_config_once; then
    echo "  + codex MCP $name -> $command"
  else
    echo "  = codex MCP $name -> $command (registered)"
  fi
}

# Register an MCP server in ~/.cursor/mcp.json.
# Args: same shape as register_mcp_claude. Cursor infers the stdio transport
# from `command`, so no `type` key is written.
register_mcp_cursor() {
  local name="$1"
  local command="$2"
  local args_json="$3"
  local env_json="$4"
  [[ -z "$args_json" ]] && args_json='[]'
  [[ -z "$env_json"  ]] && env_json='{}'

  if ! command -v jq >/dev/null 2>&1; then
    echo "  ! jq required to register MCP $name in cursor config" >&2
    return 1
  fi

  mkdir -p "$(dirname "$CURSOR_MCP")"
  if [[ ! -f "$CURSOR_MCP" ]]; then
    echo '{}' > "$CURSOR_MCP"
    CURSOR_MCP_BACKED_UP=1
  fi

  local tmp
  tmp="$(mktemp)"
  if jq --arg name "$name" \
        --arg command "$command" \
        --argjson args "$args_json" \
        --argjson env "$env_json" '
    .mcpServers //= {}
    | .mcpServers[$name] = (
        {command: $command}
        + (if ($args | length) > 0 then {args: $args} else {} end)
        + (if ($env | length) > 0 then {env: $env} else {} end)
      )
  ' "$CURSOR_MCP" > "$tmp"; then
    if _replace_json_if_changed "$CURSOR_MCP" "$tmp" _backup_cursor_mcp_once; then
      echo "  + cursor MCP $name -> $command"
    else
      echo "  = cursor MCP $name -> $command (registered)"
    fi
  else
    rm -f "$tmp"
    echo "  ! jq update failed for cursor MCP $name (config left untouched)" >&2
    return 1
  fi
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

# ----------------------------------------------------------------------------
# Shared install steps
#
# Steps every driver repeats — the core installer and downstream extension
# installers both need them, and neither delegates to the other's install.sh.
# ----------------------------------------------------------------------------

# Install the agent-sdd npm package globally so the `sdd` bin lands on PATH.
# agent-sdd is the distribution point for the SDD methodology; the driver runs
# `sdd install <mode>` afterwards.
ensure_agent_sdd() {
  echo "[agent-sdd]"
  ensure_npm_global "agent-sdd" "sdd" >/dev/null \
    || echo "  ! sdd not on PATH after npm install -g agent-sdd" >&2
}

# Decide how a globally installed npm MCP package should be spawned by the
# agent. Args: <pkg> <bin>. Stdout: {"command": ..., "args": [...]}.
# Returns 1 when the package is not on PATH.
#
# npm on Windows installs a .cmd shim, which is not an executable and cannot be
# spawned without a shell — so the package's own JS entry point is handed to
# node instead, per the Claude Code guidance for Windows.
mcp_launch_spec() {
  local pkg="$1"
  local bin="$2"

  local bin_path
  bin_path="$(command -v "$bin" 2>/dev/null || true)"
  [[ -n "$bin_path" ]] || return 1

  if ! is_windows; then
    jq -n --arg command "$bin_path" '{command: $command, args: []}'
    return 0
  fi

  local entry
  entry="$(_npm_global_bin_entry "$pkg" "$bin" 2>/dev/null || true)"
  if [[ -n "$entry" ]]; then
    jq -n --arg entry "$entry" '{command: "node", args: [$entry]}'
    return 0
  fi

  jq -n --arg bin "$bin" '{command: "cmd", args: ["/c", $bin]}'
}

# Absolute path of the JS file behind <bin> in the globally installed <pkg>.
_npm_global_bin_entry() {
  local pkg="$1"
  local bin="$2"

  command -v npm >/dev/null 2>&1 || return 1
  command -v node >/dev/null 2>&1 || return 1

  local root
  root="$(npm root -g 2>/dev/null)" || return 1
  [[ -n "$root" ]] || return 1
  root="$(posix_path "$root")"

  local manifest="$root/$pkg/package.json"
  [[ -f "$manifest" ]] || return 1

  local relative
  relative="$(node -e '
    const fs = require("fs");
    const [manifest, bin] = process.argv.slice(1);
    const pkg = JSON.parse(fs.readFileSync(manifest, "utf8"));
    const entry = typeof pkg.bin === "string" ? pkg.bin : (pkg.bin || {})[bin];
    if (!entry) process.exit(1);
    console.log(entry);
  ' "$manifest" "$bin")" || return 1

  native_path "$root/$pkg/$relative"
}

# Register the code-skeleton MCP referenced by rules/code-navigation.md, if its
# bin made it onto PATH.
register_core_mcp_claude() {
  _register_core_mcp claude
}

register_core_mcp_codex() {
  _register_core_mcp codex
}

register_core_mcp_cursor() {
  _register_core_mcp cursor
}

_register_core_mcp() {
  local agent="$1"

  local spec
  if ! spec="$(mcp_launch_spec "code-skeleton-mcp" "code-skeleton-mcp")"; then
    echo "  ! code-skeleton-mcp not on PATH; skip $agent registration" >&2
    return 0
  fi

  local launch_command launch_args
  launch_command="$(printf '%s' "$spec" | jq -r '.command')"
  launch_args="$(printf '%s' "$spec" | jq -c '.args')"
  "register_mcp_$agent" "code-skeleton" "$launch_command" "$launch_args" "{}"
}
