#!/usr/bin/env bash
# Install symlinks from this repo into per-user agent config locations and
# register hooks in ~/.claude/settings.json.
#
# Usage: install.sh <claude|codex|all> [--vcs <name>] [--yandex]
#
# --vcs <name>   Append `@vcs/<name>.md` to the generated CLAUDE.md / AGENTS.md
#                (e.g. --vcs arc). Without the flag (or with --vcs git), no VCS
#                guidance is bundled — the agent uses its built-in git knowledge.
#
# --yandex       Bundle all `yandex/*.md` files (Arcadia-specific MCP and tool
#                rules) and register the arcadia-volumes search-blocker hook.
#                Implies `--vcs arc` unless --vcs was given explicitly.
#
# Hooks: install.sh always installs hooks from `hooks/`; --yandex additionally
# installs hooks from `yandex/hooks/`. Hook registration in settings.json is
# idempotent — entries pointing at the canonical paths are upserted, stale
# entries with the same script basename are removed.
#
# Existing files at target paths are renamed to <target>.bak.<unix-timestamp>.

set -euo pipefail

usage() {
  cat >&2 <<EOF
Usage: $0 <claude|codex|all> [--vcs <name>] [--yandex]

  claude   generate ~/.claude/CLAUDE.md, symlink ~/.claude/rules and
           ~/.claude/hooks (and ~/.claude/vcs, ~/.claude/yandex when set)
  codex    build AGENTS.md and symlink ~/.codex/AGENTS.md
  all      both

  --vcs <name>   bundle vcs/<name>.md (e.g. arc). Omit for plain git.
  --yandex       bundle yandex/*.md and yandex hooks (implies --vcs arc).
EOF
  exit 2
}

[[ $# -ge 1 ]] || usage

MODE="$1"; shift
VCS=""
VCS_EXPLICIT=0
YANDEX=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --vcs)
      [[ $# -ge 2 ]] || usage
      VCS="$2"; VCS_EXPLICIT=1; shift 2
      ;;
    --yandex)
      YANDEX=1; shift
      ;;
    *) usage ;;
  esac
done

if [[ "$YANDEX" -eq 1 && "$VCS_EXPLICIT" -eq 0 ]]; then
  VCS="arc"
fi

if [[ "$VCS" == "git" ]]; then
  VCS=""
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TS="$(date +%s)"
SETTINGS="$HOME/.claude/settings.json"
SETTINGS_BACKED_UP=0

if [[ -n "$VCS" && ! -f "$REPO_ROOT/vcs/$VCS.md" ]]; then
  echo "install.sh: vcs/$VCS.md not found in repo" >&2
  exit 1
fi

if [[ "$YANDEX" -eq 1 && ! -d "$REPO_ROOT/yandex" ]]; then
  echo "install.sh: yandex/ directory not found in repo" >&2
  exit 1
fi

link() {
  local source="$1"
  local target="$2"

  if [[ ! -e "$source" ]]; then
    echo "install.sh: source missing: $source" >&2
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

build_claude_md() {
  local body
  body="$(cat "$REPO_ROOT/CLAUDE.md")"
  if [[ -n "$VCS" ]]; then
    body+=$'\n\n## VCS\n'
    body+="- @vcs/$VCS.md"$'\n'
  fi
  if [[ "$YANDEX" -eq 1 ]]; then
    body+=$'\n## Yandex\n'
    while IFS= read -r path; do
      local rel="yandex/$(basename "$path")"
      body+="- @$rel"$'\n'
    done < <(find "$REPO_ROOT/yandex" -maxdepth 1 -type f -name '*.md' | sort)
  fi
  printf '%s' "$body"
}

# Idempotently register a hook in ~/.claude/settings.json.
# Args: <script_path> <matcher> <event_name>
# Removes any prior PreToolUse/UserPromptSubmit entries whose command ends
# with the same basename, then appends a fresh entry pointing at the canonical
# path. If a matching entry already exists with the canonical command, the
# function still rewrites (cheap and keeps things deterministic).
install_hook() {
  local script="$1"
  local matcher="$2"
  local event="$3"
  local basename
  basename="$(basename "$script")"

  if ! command -v jq >/dev/null 2>&1; then
    echo "install.sh: jq is required to register hooks" >&2
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

install_claude() {
  echo "[claude]"
  write_generated "$HOME/.claude/CLAUDE.md" "$(build_claude_md)"
  link "$REPO_ROOT/rules" "$HOME/.claude/rules"
  link "$REPO_ROOT/hooks" "$HOME/.claude/hooks"
  if [[ -n "$VCS" ]]; then
    link "$REPO_ROOT/vcs" "$HOME/.claude/vcs"
  fi
  if [[ "$YANDEX" -eq 1 ]]; then
    link "$REPO_ROOT/yandex" "$HOME/.claude/yandex"
  fi

  # Register hooks idempotently.
  install_hook "$HOME/.claude/hooks/lsp-reminder.sh" "Grep|Read" "PreToolUse"
  if [[ "$YANDEX" -eq 1 ]]; then
    install_hook "$HOME/.claude/yandex/hooks/block-arcadia-broad-search.sh" \
      "Bash|Grep|Glob" "PreToolUse"
  fi
}

install_codex() {
  echo "[codex]"
  local args=()
  [[ -n "$VCS" ]] && args+=(--vcs "$VCS")
  [[ "$YANDEX" -eq 1 ]] && args+=(--yandex)
  "$REPO_ROOT/scripts/build.sh" "${args[@]}"
  link "$REPO_ROOT/build/AGENTS.md" "$HOME/.codex/AGENTS.md"
}

case "$MODE" in
  claude) install_claude ;;
  codex)  install_codex ;;
  all)    install_claude; install_codex ;;
  *)      usage ;;
esac

echo "install.sh: done."
