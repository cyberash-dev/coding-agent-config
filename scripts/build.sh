#!/usr/bin/env bash
# Build a flat AGENTS.md for Codex by inlining @rules/*.md references from CLAUDE.md.
#
# Source of truth: <repo>/CLAUDE.md and <repo>/rules/*.md.
# Output:          <repo>/build/AGENTS.md (always overwritten).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO_ROOT/CLAUDE.md"
OUT_DIR="$REPO_ROOT/build"
OUT="$OUT_DIR/AGENTS.md"

if [[ ! -f "$SRC" ]]; then
  echo "build.sh: source not found: $SRC" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

awk -v repo="$REPO_ROOT" '
  /^- @rules\/[^ ]+\.md/ {
    match($0, /@rules\/[^ ]+\.md/)
    rel = substr($0, RSTART + 1, RLENGTH - 1)
    full = repo "/" rel
    print ""
    print "<!-- inlined from " rel " -->"
    while ((getline line < full) > 0) {
      print line
    }
    close(full)
    print ""
    next
  }
  { print }
' "$SRC" > "$OUT"

echo "build.sh: wrote $OUT"
