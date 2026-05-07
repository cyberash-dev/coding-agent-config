#!/usr/bin/env bash
# Install symlinks from this repo into per-user agent config locations and
# register hooks in ~/.claude/settings.json.
#
# Usage: install.sh <claude|codex|all> [--sdd]
#
# --sdd   Bundle all `sdd/*.md` files (Spec-Driven Development methodology,
#         enforcement registry, sdd-cli usage), register the sdd-lint
#         reminder hook, and install the spec-driven-development skill.
#         Without the flag, every previously installed SDD artefact owned
#         by this repo is removed (hook entry, ~/.claude/sdd symlink,
#         spec-driven-development skill symlinks).
#
# Hooks: install.sh always installs hooks from `hooks/`; --sdd additionally
# installs hooks from `sdd/hooks/`. Hook registration in settings.json is
# idempotent — entries pointing at the canonical paths are upserted, stale
# entries with the same script basename are removed.
#
# Existing files at target paths are renamed to <target>.bak.<unix-timestamp>.
#
# Downstream extension repos embed this repo as a git submodule and source
# `scripts/lib/install-lib.sh` from their own driver scripts to compose
# additional bundles on top of the core install.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=lib/install-lib.sh
source "$REPO_ROOT/scripts/lib/install-lib.sh"

usage() {
  cat >&2 <<EOF
Usage: $0 <claude|codex|all> [--sdd]

  claude   generate ~/.claude/CLAUDE.md, symlink ~/.claude/rules and
           ~/.claude/hooks (and ~/.claude/sdd when set)
  codex    build AGENTS.md, symlink ${CODEX_HOME:-~/.codex}/AGENTS.md,
           and symlink skills into ~/.agents/skills
  all      both

  --sdd    bundle sdd/*.md, the sdd-lint hook, and the
           spec-driven-development skill. Without the flag any
           previously installed SDD artefact is removed.
EOF
  exit 2
}

[[ $# -ge 1 ]] || usage

MODE="$1"; shift
SDD=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sdd)
      SDD=1; shift
      ;;
    *) usage ;;
  esac
done

CODEX_CONFIG_DIR="${CODEX_HOME:-$HOME/.codex}"

if [[ "$SDD" -eq 1 && ! -d "$REPO_ROOT/sdd" ]]; then
  echo "install.sh: sdd/ directory not found in repo" >&2
  exit 1
fi

# MCP servers referenced by core rules (rules/code-navigation.md → code-skeleton).
# Each entry is registered in ~/.claude.json or ~/.codex/config.toml depending
# on the install mode, after a single global npm install.
ensure_core_mcp_packages() {
  echo "[mcp/core]"
  ensure_npm_global "code-skeleton-mcp" "code-skeleton-mcp" >/dev/null || true
}

register_core_mcp_claude() {
  local cs_bin
  cs_bin="$(command -v code-skeleton-mcp 2>/dev/null || true)"
  if [[ -z "$cs_bin" ]]; then
    echo "  ! code-skeleton-mcp not on PATH; skip claude registration" >&2
    return 0
  fi
  register_mcp_claude "code-skeleton" "$cs_bin" "[]" "{}"
}

register_core_mcp_codex() {
  local cs_bin
  cs_bin="$(command -v code-skeleton-mcp 2>/dev/null || true)"
  if [[ -z "$cs_bin" ]]; then
    echo "  ! code-skeleton-mcp not on PATH; skip codex registration" >&2
    return 0
  fi
  register_mcp_codex "code-skeleton" "$cs_bin" "[]" "{}"
}

build_claude_md() {
  local body
  body="$(cat "$REPO_ROOT/CLAUDE.md")"
  if [[ "$SDD" -eq 1 ]]; then
    body+=$'\n\n## SDD\n'
    while IFS= read -r path; do
      local rel="sdd/$(basename "$path")"
      body+="- @$rel"$'\n'
    done < <(find "$REPO_ROOT/sdd" -maxdepth 1 -type f -name '*.md' | sort)
  fi
  printf '%s' "$body"
}

install_claude() {
  echo "[claude]"
  write_generated "$HOME/.claude/CLAUDE.md" "$(build_claude_md)"
  link "$REPO_ROOT/rules" "$HOME/.claude/rules"
  link "$REPO_ROOT/hooks" "$HOME/.claude/hooks"
  if [[ "$SDD" -eq 1 ]]; then
    link "$REPO_ROOT/sdd" "$HOME/.claude/sdd"
  fi
  install_skills "$REPO_ROOT/skills" "$HOME/.claude/skills"
  if [[ "$SDD" -eq 1 ]]; then
    install_skills "$REPO_ROOT/sdd/skills" "$HOME/.claude/skills"
  else
    unlink_if_repo_owned "$HOME/.claude/sdd" "$REPO_ROOT/sdd"
    unlink_if_repo_owned "$HOME/.claude/skills/spec-driven-development" \
      "$REPO_ROOT/sdd/skills/spec-driven-development"
  fi

  install_hook "$HOME/.claude/hooks/lsp-reminder.sh" "Grep|Read" "PreToolUse"
  if [[ "$SDD" -eq 1 ]]; then
    install_hook "$HOME/.claude/sdd/hooks/sdd-lint-reminder.sh" \
      "Edit|Write|MultiEdit" "PreToolUse"
  else
    remove_hook "sdd-lint-reminder.sh" "PreToolUse"
  fi

  register_core_mcp_claude
}

install_codex() {
  echo "[codex]"
  local args=()
  [[ "$SDD" -eq 1 ]] && args+=(--sdd)
  "$REPO_ROOT/scripts/build.sh" ${args[@]+"${args[@]}"}
  link "$REPO_ROOT/build/AGENTS.md" "$CODEX_CONFIG_DIR/AGENTS.md"
  install_skills "$REPO_ROOT/skills" "$HOME/.agents/skills"
  if [[ "$SDD" -eq 1 ]]; then
    install_skills "$REPO_ROOT/sdd/skills" "$HOME/.agents/skills"
  else
    unlink_if_repo_owned "$HOME/.agents/skills/spec-driven-development" \
      "$REPO_ROOT/sdd/skills/spec-driven-development"
  fi
  cleanup_legacy_codex_skills "$REPO_ROOT/skills" "$REPO_ROOT/sdd/skills"

  register_core_mcp_codex
}

case "$MODE" in
  claude) ensure_core_mcp_packages; install_claude ;;
  codex)  ensure_core_mcp_packages; install_codex ;;
  all)    ensure_core_mcp_packages; install_claude; install_codex ;;
  *)      usage ;;
esac

echo "install.sh: done."
