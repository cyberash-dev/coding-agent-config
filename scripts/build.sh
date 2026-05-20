#!/usr/bin/env bash
# Build a flat AGENTS.md for Codex by inlining @rules/*.md references from
# CLAUDE.md.
#
# Usage: build.sh
#
# Source of truth: <repo>/CLAUDE.md, <repo>/rules/*.md.
# Output:          <repo>/build/AGENTS.md (always overwritten).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=lib/install-lib.sh
source "$REPO_ROOT/scripts/lib/install-lib.sh"

if [[ $# -gt 0 ]]; then
  echo "build.sh: unexpected arg: $1" >&2
  exit 2
fi

SRC="$REPO_ROOT/CLAUDE.md"
OUT_DIR="$REPO_ROOT/build"
OUT="$OUT_DIR/AGENTS.md"

if [[ ! -f "$SRC" ]]; then
  echo "build.sh: source not found: $SRC" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

inline_imports "$SRC" "$OUT" "rules=$REPO_ROOT"

echo "build.sh: wrote $OUT"
