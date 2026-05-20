#!/usr/bin/env bash
# Install symlinks from this repo into per-user agent config locations and
# register hooks in ~/.claude/settings.json.
#
# Usage: install.sh <claude|codex|all> [--sdd]
#
# --sdd   Fetch the sdd-cli submodule (Spec-Driven Development tooling),
#         `npm install` + `npm run build` + `npm link` it so the `sdd` bin
#         lands on PATH, then run `sdd install <mode>`. sdd-cli installs its
#         own rules, skill, and hooks for the chosen target(s).
#
# Hooks: install.sh always installs hooks from `hooks/`. Hook registration
# in settings.json is idempotent — entries pointing at the canonical paths
# are upserted, stale entries with the same script basename are removed.
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
           ~/.claude/hooks
  codex    build AGENTS.md, symlink ${CODEX_HOME:-~/.codex}/AGENTS.md,
           and symlink skills into ~/.agents/skills
  all      both

  --sdd    fetch the sdd-cli submodule, npm install + build + link it,
           then run \`sdd install <mode>\` so sdd-cli installs its own
           SDD rules, skill, and hooks.
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

# Fetch and build the sdd-cli submodule, then link its `sdd` bin onto PATH.
ensure_sdd_cli() {
  echo "[sdd-cli]"
  git -C "$REPO_ROOT" submodule update --init --recursive sdd-cli
  ( cd "$REPO_ROOT/sdd-cli" && npm install && npm run build && npm link )
  command -v sdd >/dev/null 2>&1 \
    || echo "  ! sdd not on PATH after npm link" >&2
}

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

install_claude() {
  echo "[claude]"
  write_generated "$HOME/.claude/CLAUDE.md" "$(cat "$REPO_ROOT/CLAUDE.md")"
  link "$REPO_ROOT/rules" "$HOME/.claude/rules"
  link "$REPO_ROOT/hooks" "$HOME/.claude/hooks"
  install_skills "$REPO_ROOT/skills" "$HOME/.claude/skills"

  install_hook "$HOME/.claude/hooks/lsp-reminder.sh" "Grep|Read" "PreToolUse"

  register_core_mcp_claude
}

install_codex() {
  echo "[codex]"
  "$REPO_ROOT/scripts/build.sh"
  link "$REPO_ROOT/build/AGENTS.md" "$CODEX_CONFIG_DIR/AGENTS.md"
  install_skills "$REPO_ROOT/skills" "$HOME/.agents/skills"
  cleanup_legacy_codex_skills "$REPO_ROOT/skills"

  register_core_mcp_codex
}

case "$MODE" in
  claude|codex|all) ensure_core_mcp_packages ;;
  *)                usage ;;
esac

if [[ "$SDD" -eq 1 ]]; then
  ensure_sdd_cli
fi

case "$MODE" in
  claude) install_claude ;;
  codex)  install_codex ;;
  all)    install_claude; install_codex ;;
esac

# sdd-cli writes its own rules/skill/hooks into the target config(s); run it
# last so build.sh's regeneration of build/AGENTS.md happens before sdd-cli
# appends to the symlinked ~/.codex/AGENTS.md.
if [[ "$SDD" -eq 1 ]]; then
  if command -v sdd >/dev/null 2>&1; then
    sdd install "$MODE"
  else
    echo "install.sh: sdd not on PATH; skipping 'sdd install $MODE'" >&2
  fi
fi

echo "install.sh: done."
