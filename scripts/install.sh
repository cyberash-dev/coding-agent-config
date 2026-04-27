#!/usr/bin/env bash
# Install symlinks from this repo into per-user agent config locations.
#
# Usage: install.sh <claude|codex|all>
#
# Existing files at target paths are renamed to <target>.bak.<unix-timestamp>.
# Re-running is idempotent: targets already symlinked into this repo are skipped.

set -euo pipefail

usage() {
  cat >&2 <<EOF
Usage: $0 <claude|codex|all>

  claude  symlink ~/.claude/CLAUDE.md and ~/.claude/rules
  codex   build AGENTS.md and symlink ~/.codex/AGENTS.md
  all     both
EOF
  exit 2
}

[[ $# -eq 1 ]] || usage

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TS="$(date +%s)"

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

install_claude() {
  echo "[claude]"
  link "$REPO_ROOT/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
  link "$REPO_ROOT/rules"     "$HOME/.claude/rules"
}

install_codex() {
  echo "[codex]"
  "$REPO_ROOT/scripts/build.sh"
  link "$REPO_ROOT/build/AGENTS.md" "$HOME/.codex/AGENTS.md"
}

case "$1" in
  claude) install_claude ;;
  codex)  install_codex ;;
  all)    install_claude; install_codex ;;
  *)      usage ;;
esac

echo "install.sh: done."
