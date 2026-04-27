#!/usr/bin/env bash
# Build a flat AGENTS.md for Codex by inlining @rules/*.md, @vcs/*.md, and
# @yandex/*.md references from CLAUDE.md.
#
# Usage: build.sh [--vcs <name>] [--yandex]
#
# Without --vcs, no VCS section is appended (the agent uses built-in git
# knowledge). With --vcs <name>, appends `- @vcs/<name>.md`.
# --yandex appends a Yandex section listing all yandex/*.md and implies
# --vcs arc unless --vcs was given explicitly.
#
# Source of truth: <repo>/CLAUDE.md, <repo>/rules/*.md, <repo>/vcs/*.md,
# <repo>/yandex/*.md.
# Output:          <repo>/build/AGENTS.md (always overwritten).

set -euo pipefail

VCS=""
VCS_EXPLICIT=0
YANDEX=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --vcs)
      [[ $# -ge 2 ]] || { echo "build.sh: --vcs requires a value" >&2; exit 2; }
      VCS="$2"; VCS_EXPLICIT=1; shift 2
      ;;
    --yandex)
      YANDEX=1; shift
      ;;
    *) echo "build.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ "$YANDEX" -eq 1 && "$VCS_EXPLICIT" -eq 0 ]]; then
  VCS="arc"
fi

if [[ "$VCS" == "git" ]]; then
  VCS=""
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO_ROOT/CLAUDE.md"
OUT_DIR="$REPO_ROOT/build"
OUT="$OUT_DIR/AGENTS.md"

if [[ ! -f "$SRC" ]]; then
  echo "build.sh: source not found: $SRC" >&2
  exit 1
fi

if [[ -n "$VCS" && ! -f "$REPO_ROOT/vcs/$VCS.md" ]]; then
  echo "build.sh: vcs/$VCS.md not found" >&2
  exit 1
fi

if [[ "$YANDEX" -eq 1 && ! -d "$REPO_ROOT/yandex" ]]; then
  echo "build.sh: yandex/ directory not found" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

TMP="$(mktemp)"
cp "$SRC" "$TMP"
if [[ -n "$VCS" ]]; then
  printf '\n## VCS\n- @vcs/%s.md\n' "$VCS" >> "$TMP"
fi
if [[ "$YANDEX" -eq 1 ]]; then
  printf '\n## Yandex\n' >> "$TMP"
  while IFS= read -r path; do
    printf -- '- @yandex/%s\n' "$(basename "$path")" >> "$TMP"
  done < <(find "$REPO_ROOT/yandex" -maxdepth 1 -type f -name '*.md' | sort)
fi

awk -v repo="$REPO_ROOT" '
  /^- @(rules|vcs|yandex)\/[^ ]+\.md/ {
    match($0, /@(rules|vcs|yandex)\/[^ ]+\.md/)
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
' "$TMP" > "$OUT"

rm -f "$TMP"

extras=""
[[ -n "$VCS" ]] && extras+=" vcs=$VCS"
[[ "$YANDEX" -eq 1 ]] && extras+=" yandex=on"
echo "build.sh: wrote $OUT${extras}"
