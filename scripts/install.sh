#!/usr/bin/env bash
# Copy this repo's rules, hooks and skills into per-user agent config locations
# and register hooks in ~/.claude/settings.json.
#
# Usage: install.sh <claude|codex|cursor|all> [--sdd] [--teams] [--codex-review]
#                   [--update-mcps] [--lang=ru|en]
#
# --lang  Pin the agent's reply language. Without it, the agent replies in
#         whatever language the operator used. With `--lang=ru` or
#         `--lang=en`, it always replies in that language. The directive is
#         appended to the generated ~/.claude/CLAUDE.md and build/AGENTS.md, and
#         published as language.mdc among the Cursor rules.
#
# --sdd   Install the `agent-sdd` npm package (Spec-Driven Development
#         tooling) globally so the `sdd` bin lands on PATH, then run
#         `sdd install <mode>`. agent-sdd installs its own rules, skill,
#         and hooks for the chosen target(s).
#
# --teams Turn delegation on in both harnesses. Sets
#         CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 in the env block of
#         ~/.claude/settings.json (without the flag, the key is removed) and
#         both Codex gates — features.multi_agent and agents.enabled — in
#         ~/.codex/config.toml (without the flag, the config is left as-is).
#         It also adds rules/orchestration.md to the generated CLAUDE.md /
#         AGENTS.md — the standing authorization both agents need before they
#         delegate on their own.
#
# --codex-review
#         Install the review bundle from `codex-review/`: the code-review and
#         codex-cli-review skills, plus the codex-commit-review PreToolUse hook,
#         which runs every `git commit` / `arc commit` through a read-only codex
#         review driven by the codex-cli-review skill and refuses the commit so
#         the findings reach the agent. The skills land on every surface; the hook
#         is registered for claude (PreToolUse) and cursor (beforeShellExecution),
#         Codex has no hook configuration to put it in. It also writes the review
#         its own CODEX_HOME under ~/.cache/coding-agent-config/codex-review-home:
#         the review-scoped rules, medium reasoning, no MCP servers and no
#         plugins, with the login shared from the operator's codex home. Without
#         the flag, all three are removed.
#
# --update-mcps
#         Update already installed npm-backed MCP packages to npm latest
#         without prompting instead of asking per package.
#
# Hooks: install.sh always installs the scripts from `hooks/`. Registration in
# ~/.claude/settings.json and ~/.cursor/hooks.json is idempotent — the entry
# this repo owns is replaced where it already sits, a same-name hook of the
# user's own is left alone, and repeats of one command in an event collapse.
#
# Rules, hooks and skills are copied, not symlinked: editing this repo takes
# effect on the next install.sh run. What the installer wrote is recorded in a
# .coding-agent-config manifest next to the copies, so a later run can take its
# own files back out without touching anything the user keeps there. Files at
# target paths that this repo does not own are renamed to
# <target>.bak.<unix-timestamp>.
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
Usage: $0 <claude|codex|cursor|all> [--sdd] [--teams] [--codex-review] [--update-mcps] [--lang=ru|en]

  claude   generate ~/.claude/CLAUDE.md, copy ~/.claude/rules and
           ~/.claude/hooks
  codex    build AGENTS.md, copy it to ${CODEX_HOME:-~/.codex}/AGENTS.md,
           and copy skills into ~/.agents/skills
  cursor   build the .mdc rule set into ~/.cursor/rules, copy hooks into
           ~/.cursor/hooks and skills into ~/.agents/skills
  all      all three

  --lang   pin the reply language to ru or en. Omit to keep replying in
           the operator's own language.
  --sdd    install the \`agent-sdd\` npm package globally, then run
           \`sdd install <mode>\` so agent-sdd installs its own
           SDD rules, skill, and hooks.
  --teams  install rules/orchestration.md into the generated instructions and
           turn delegation on: CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 in
           ~/.claude/settings.json, features.multi_agent + agents.enabled in
           ~/.codex/config.toml
  --codex-review
           install the code-review and codex-cli-review skills, the trimmed
           CODEX_HOME the review runs in, and the commit-review hook for claude
           and cursor: every commit is refused once so the codex review reaches
           the agent, nothing is edited, and the retry goes through
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

# Codex has no hook configuration of its own, so the codex mode has nowhere to
# put the review hook. Say what the flag does there instead of leaving the
# missing hook unexplained.
if [[ "$CODEX_REVIEW" -eq 1 && "$MODE" == "codex" ]]; then
  echo "install.sh: --codex-review installs the review skills; the commit hook is claude/cursor only" >&2
fi

CODEX_CONFIG_DIR="${CODEX_HOME:-$AGENT_HOME/.codex}"
REVIEW_SKILLS="$REPO_ROOT/codex-review/skills"

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
    "$(cat "$REPO_ROOT/CLAUDE.md"; printf '\n'; \
       teams_section "$TEAMS" "$REPO_ROOT/templates/teams"; \
       language_section "$LANG_MODE" "$REPO_ROOT/templates/language")"
  install_tree "$REPO_ROOT/rules" "$AGENT_HOME/.claude/rules"
  install_tree "$REPO_ROOT/hooks" "$AGENT_HOME/.claude/hooks"
  install_skills "$REPO_ROOT/skills" "$AGENT_HOME/.claude/skills"
  install_codex_review_skills "$CODEX_REVIEW" "$REVIEW_SKILLS" "$AGENT_HOME/.claude/skills"

  remove_hook "$AGENT_HOME/.claude/hooks/lsp-reminder.sh" "PreToolUse"
  install_hook "$AGENT_HOME/.claude/hooks/code-navigation-reminder.sh" "Grep|Read" "PreToolUse"
  install_codex_review_hook "$CODEX_REVIEW"

  register_core_mcp_claude
  install_teams_env "$TEAMS"
}

install_codex() {
  echo "[codex]"
  # Codex reads AGENTS.override.md instead of AGENTS.md when it exists, so the
  # install would look successful while the instructions never load.
  if [[ -e "$CODEX_CONFIG_DIR/AGENTS.override.md" ]]; then
    echo "  ! $CODEX_CONFIG_DIR/AGENTS.override.md shadows AGENTS.md; Codex will not read this install" >&2
  fi
  local build_args=(--lang="$LANG_MODE")
  [[ "$TEAMS" -eq 1 ]] && build_args+=(--teams)
  "$REPO_ROOT/scripts/build.sh" "${build_args[@]}"
  install_file "$REPO_ROOT/build/AGENTS.md" "$CODEX_CONFIG_DIR/AGENTS.md"
  install_skills "$REPO_ROOT/skills" "$AGENT_HOME/.agents/skills"
  install_codex_review_skills "$CODEX_REVIEW" "$REVIEW_SKILLS" "$AGENT_HOME/.agents/skills"
  cleanup_legacy_codex_skills "$REPO_ROOT/skills" "$REVIEW_SKILLS"

  register_core_mcp_codex
  install_codex_subagents "$TEAMS"
}

install_cursor() {
  echo "[cursor]"
  local build_args=(--lang="$LANG_MODE")
  [[ "$TEAMS" -eq 1 ]] && build_args+=(--teams)
  "$REPO_ROOT/scripts/build-cursor.sh" "${build_args[@]}"
  install_tree "$REPO_ROOT/build/cursor/rules" "$AGENT_HOME/.cursor/rules"
  install_tree "$REPO_ROOT/hooks" "$AGENT_HOME/.cursor/hooks"
  # ~/.agents/skills is read by Codex and Cursor alike, so both modes share one
  # copy instead of installing the same skill twice.
  install_skills "$REPO_ROOT/skills" "$AGENT_HOME/.agents/skills"
  install_codex_review_skills "$CODEX_REVIEW" "$REVIEW_SKILLS" "$AGENT_HOME/.agents/skills"

  install_cursor_review_hook "$CODEX_REVIEW"

  register_core_mcp_cursor
}

case "$MODE" in
  claude|codex|cursor|all) ;;
  *)                       usage ;;
esac

require_deps
ensure_core_mcp_packages

if [[ "$SDD" -eq 1 ]]; then
  ensure_agent_sdd
fi

case "$MODE" in
  claude) install_claude ;;
  codex)  install_codex ;;
  cursor) install_cursor ;;
  all)    install_claude; install_codex; install_cursor ;;
esac

# One review home per user: every surface runs its review through the same
# codex-cli-review script, and the script reads it from a fixed path.
install_codex_review_home "$CODEX_REVIEW" "$REPO_ROOT" \
  "$AGENT_HOME/.cache/coding-agent-config/codex-review-home" "$CODEX_CONFIG_DIR"

# agent-sdd writes its own rules/skill/hooks into the target config(s); run it
# last so the build steps finish before agent-sdd appends to the installed
# ~/.codex/AGENTS.md. It targets claude and codex; there is no cursor mode.
if [[ "$SDD" -eq 1 ]]; then
  if [[ "$MODE" == "cursor" ]]; then
    echo "install.sh: agent-sdd has no cursor target; skipping 'sdd install'" >&2
  elif command -v sdd >/dev/null 2>&1; then
    sdd install "$MODE"
  else
    echo "install.sh: sdd not on PATH; skipping 'sdd install $MODE'" >&2
  fi
fi

# Last word on the hook files: a tool that merged its own hooks after us (see
# --sdd) can leave a second entry for a script that is already registered.
case "$MODE" in
  claude|all) dedupe_hooks ;;
esac
case "$MODE" in
  cursor|all) dedupe_cursor_hooks ;;
esac

echo "install.sh: done."
