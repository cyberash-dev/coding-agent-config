#!/usr/bin/env bash
# Install symlinks from this repo into per-user agent config locations and
# register hooks in ~/.claude/settings.json.
#
# Usage: install.sh <claude|codex|all> [--sdd] [--teams] [--codex-review]
#                   [--update-mcps] [--lang=ru|en]
#
# --lang  Pin the agent's reply language. Without it, the agent replies in
#         whatever language the operator used. With `--lang=ru` or
#         `--lang=en`, it always replies in that language. The directive is
#         appended to the generated ~/.claude/CLAUDE.md and build/AGENTS.md.
#
# --sdd   Install the `agent-sdd` npm package (Spec-Driven Development
#         tooling) globally so the `sdd` bin lands on PATH, then run
#         `sdd install <mode>`. agent-sdd installs its own rules, skill,
#         and hooks for the chosen target(s).
#
# --teams Set CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 in the env block of
#         ~/.claude/settings.json (claude/all only). Without the flag, the
#         key is removed.
#
# --codex-review
#         Register the codex-commit-review PreToolUse hook, which runs every
#         `git commit` / `arc commit` through codex twice: a review pass and a
#         workspace-write pass that edits the files. It speaks the Claude Code
#         hook protocol, so the flag applies to claude/all and is inert for the
#         codex mode. Without the flag, the hook is removed.
#
# --update-mcps
#         Update already installed npm-backed MCP packages to npm latest
#         without prompting instead of asking per package.
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
Usage: $0 <claude|codex|all> [--sdd] [--teams] [--codex-review] [--update-mcps] [--lang=ru|en]

  claude   generate ~/.claude/CLAUDE.md, symlink ~/.claude/rules and
           ~/.claude/hooks
  codex    build AGENTS.md, symlink ${CODEX_HOME:-~/.codex}/AGENTS.md,
           and symlink skills into ~/.agents/skills
  all      both

  --lang   pin the reply language to ru or en. Omit to keep replying in
           the operator's own language.
  --sdd    install the \`agent-sdd\` npm package globally, then run
           \`sdd install <mode>\` so agent-sdd installs its own
           SDD rules, skill, and hooks.
  --teams  set CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 in the env block of
           ~/.claude/settings.json (claude/all only)
  --codex-review
           register the codex-commit-review PreToolUse hook: every commit is
           reviewed by codex, which then edits the files (claude/all only)
  --update-mcps
           update npm-backed MCP packages without prompting per package
EOF
  exit 2
}

[[ $# -ge 1 ]] || usage

MODE="$1"; shift
SDD=0
TEAMS=0
CODEX_REVIEW=0
UPDATE_MCPS=0
LANG_MODE=default

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sdd)
      SDD=1; shift
      ;;
    --teams) TEAMS=1; shift ;;
    --codex-review) CODEX_REVIEW=1; shift ;;
    --update-mcps) UPDATE_MCPS=1; shift ;;
    --lang=*)
      LANG_MODE="${1#--lang=}"
      case "$LANG_MODE" in ru|en) ;; *) usage ;; esac
      shift
      ;;
    *) usage ;;
  esac
done

# The review hook speaks the Claude Code hook protocol and is registered in
# ~/.claude/settings.json, so the codex mode has nowhere to put it. Say so
# instead of accepting the flag and doing nothing.
if [[ "$CODEX_REVIEW" -eq 1 && "$MODE" == "codex" ]]; then
  echo "install.sh: --codex-review applies to claude/all; ignored for the codex mode" >&2
fi

CODEX_CONFIG_DIR="${CODEX_HOME:-$AGENT_HOME/.codex}"

# Every writer below needs jq and awk. Bail before the first mutation instead of
# aborting halfway through, with links already created and hooks not registered.
require_deps() {
  local missing=()
  local tool
  for tool in jq awk; do
    command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
  done
  [[ ${#missing[@]} -gt 0 ]] || return 0

  echo "install.sh: missing required tool(s): ${missing[*]}" >&2
  case "$(os_kind)" in
    macos)   echo "  install with: brew install ${missing[*]}" >&2 ;;
    linux)   echo "  install with: sudo apt install ${missing[*]}  (or your distro's package manager)" >&2 ;;
    windows) echo "  install with: winget install jqlang.jq  (awk ships with Git for Windows)" >&2 ;;
  esac
  exit 1
}

# MCP servers referenced by core rules (rules/code-navigation.md → code-skeleton).
# Each entry is registered in ~/.claude.json or ~/.codex/config.toml depending
# on the install mode, after a single global npm install.
ensure_core_mcp_packages() {
  echo "[mcp/core]"
  ensure_mcp_npm_global "code-skeleton-mcp" "code-skeleton-mcp" >/dev/null || true
}

install_claude() {
  echo "[claude]"
  write_generated "$AGENT_HOME/.claude/CLAUDE.md" \
    "$(cat "$REPO_ROOT/CLAUDE.md"; printf '\n'; language_section "$LANG_MODE" "$REPO_ROOT/templates/language")"
  link "$REPO_ROOT/rules" "$AGENT_HOME/.claude/rules"
  link "$REPO_ROOT/hooks" "$AGENT_HOME/.claude/hooks"
  install_skills "$REPO_ROOT/skills" "$AGENT_HOME/.claude/skills"

  remove_hook "lsp-reminder.sh" "PreToolUse"
  install_hook "$AGENT_HOME/.claude/hooks/code-navigation-reminder.sh" "Grep|Read" "PreToolUse"
  install_codex_review_hook "$CODEX_REVIEW"

  register_core_mcp_claude
  install_teams_env "$TEAMS"
}

install_codex() {
  echo "[codex]"
  "$REPO_ROOT/scripts/build.sh" --lang="$LANG_MODE"
  link "$REPO_ROOT/build/AGENTS.md" "$CODEX_CONFIG_DIR/AGENTS.md"
  install_skills "$REPO_ROOT/skills" "$AGENT_HOME/.agents/skills"
  cleanup_legacy_codex_skills "$REPO_ROOT/skills"

  register_core_mcp_codex
}

case "$MODE" in
  claude|codex|all) ;;
  *)                usage ;;
esac

require_deps
ensure_core_mcp_packages

if [[ "$SDD" -eq 1 ]]; then
  ensure_agent_sdd
fi

case "$MODE" in
  claude) install_claude ;;
  codex)  install_codex ;;
  all)    install_claude; install_codex ;;
esac

# agent-sdd writes its own rules/skill/hooks into the target config(s); run it
# last so build.sh's regeneration of build/AGENTS.md happens before agent-sdd
# appends to the symlinked ~/.codex/AGENTS.md.
if [[ "$SDD" -eq 1 ]]; then
  if command -v sdd >/dev/null 2>&1; then
    sdd install "$MODE"
  else
    echo "install.sh: sdd not on PATH; skipping 'sdd install $MODE'" >&2
  fi
fi

echo "install.sh: done."
