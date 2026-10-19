#!/usr/bin/env bash
# Build a flat AGENTS.md for Codex by inlining @rules/*.md references from
# CLAUDE.md.
#
# Usage: build.sh [--out=<file>] [--lang=ru|en] [--teams]
#
# --out   Where to write the flat file. Defaults to build/AGENTS.md; the
#         deepseek mode builds its own copy at build/AGENTS.deepseek.md, so the
#         Codex file that `install.sh codex` copies is never overwritten by it.
#
# --lang  Pin the reply language appended to the flat file. Defaults to the
#         operator's own language when omitted.
#
# --teams Inline rules/orchestration.md, the standing authorization Codex and
#         DSH need before they will spawn sub-agents on their own.
#
# Source of truth: <repo>/CLAUDE.md, <repo>/rules/*.md,
#                  <repo>/templates/{language,teams}/*.md.
# Output:          <repo>/build/AGENTS.md (always overwritten).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=lib/install-lib.sh
source "$REPO_ROOT/scripts/lib/install-lib.sh"

LANG_MODE=default
TEAMS=0
OUT="$REPO_ROOT/build/AGENTS.md"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --lang=*)
      LANG_MODE="${1#--lang=}"
      case "$LANG_MODE" in default|ru|en) ;; *) echo "build.sh: invalid --lang: $LANG_MODE" >&2; exit 2 ;; esac
      shift
      ;;
    --out=*)
      OUT="${1#--out=}"
      [[ -n "$OUT" ]] || { echo "build.sh: --out needs a path" >&2; exit 2; }
      shift
      ;;
    --teams) TEAMS=1; shift ;;
    *) echo "build.sh: unexpected arg: $1" >&2; exit 2 ;;
  esac
done

SRC="$REPO_ROOT/CLAUDE.md"

if [[ ! -f "$SRC" ]]; then
  echo "build.sh: source not found: $SRC" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUT")"

SOURCE="$SRC"
if [[ "$TEAMS" -eq 1 ]]; then
  SOURCE="$(mktemp)"
  { cat "$SRC"; printf '\n'; teams_section 1 "$REPO_ROOT/templates/teams"; } > "$SOURCE"
fi

inline_imports "$SOURCE" "$OUT" "rules=$REPO_ROOT"
{ printf '\n'; language_section "$LANG_MODE" "$REPO_ROOT/templates/language"; } >> "$OUT"

[[ "$SOURCE" == "$SRC" ]] || rm -f "$SOURCE"

echo "build.sh: wrote $OUT"
