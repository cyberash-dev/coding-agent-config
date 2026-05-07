#!/usr/bin/env bash
# Build a flat AGENTS.md for Codex by inlining @rules/*.md and (optionally)
# @sdd/*.md references from CLAUDE.md.
#
# Usage: build.sh [--sdd]
#
# --sdd appends an SDD section listing all sdd/*.md.
#
# Source of truth: <repo>/CLAUDE.md, <repo>/rules/*.md, <repo>/sdd/*.md.
# Output:          <repo>/build/AGENTS.md (always overwritten).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=lib/install-lib.sh
source "$REPO_ROOT/scripts/lib/install-lib.sh"

SDD=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --sdd)
      SDD=1; shift
      ;;
    *) echo "build.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

SRC="$REPO_ROOT/CLAUDE.md"
OUT_DIR="$REPO_ROOT/build"
OUT="$OUT_DIR/AGENTS.md"

if [[ ! -f "$SRC" ]]; then
  echo "build.sh: source not found: $SRC" >&2
  exit 1
fi

if [[ "$SDD" -eq 1 && ! -d "$REPO_ROOT/sdd" ]]; then
  echo "build.sh: sdd/ directory not found" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

TMP="$(mktemp)"
cp "$SRC" "$TMP"
if [[ "$SDD" -eq 1 ]]; then
  printf '\n## SDD\n' >> "$TMP"
  while IFS= read -r path; do
    printf -- '- @sdd/%s\n' "$(basename "$path")" >> "$TMP"
  done < <(find "$REPO_ROOT/sdd" -maxdepth 1 -type f -name '*.md' | sort)
fi

inline_imports "$TMP" "$OUT" \
  "rules=$REPO_ROOT" \
  "sdd=$REPO_ROOT"

rm -f "$TMP"

extras=""
[[ "$SDD" -eq 1 ]] && extras+=" sdd=on"
echo "build.sh: wrote $OUT${extras}"
