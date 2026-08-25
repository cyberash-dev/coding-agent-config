#!/usr/bin/env bash
# Build Cursor rules from the same rule set CLAUDE.md imports: one .mdc per
# rule, since Cursor ignores plain .md files in a rules directory.
#
# Usage: build-cursor.sh [--lang=ru|en] [--teams]
#
# --lang  Pin the reply language emitted as language.mdc. Defaults to the
#         operator's own language when omitted.
#
# --teams Add rules/orchestration.md, the standing authorization for delegation.
#
# Source of truth: <repo>/CLAUDE.md, <repo>/rules/*.md,
#                  <repo>/templates/{language,teams}/*.md.
# Output:          <repo>/build/cursor/rules/*.mdc (always rebuilt).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=lib/install-lib.sh
source "$REPO_ROOT/scripts/lib/install-lib.sh"

LANG_MODE=default
TEAMS=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --lang=*)
      LANG_MODE="${1#--lang=}"
      case "$LANG_MODE" in default|ru|en) ;; *) echo "build-cursor.sh: invalid --lang: $LANG_MODE" >&2; exit 2 ;; esac
      shift
      ;;
    --teams) TEAMS=1; shift ;;
    *) echo "build-cursor.sh: unexpected arg: $1" >&2; exit 2 ;;
  esac
done

SRC="$REPO_ROOT/CLAUDE.md"
OUT_DIR="$REPO_ROOT/build/cursor/rules"

if [[ ! -f "$SRC" ]]; then
  echo "build-cursor.sh: source not found: $SRC" >&2
  exit 1
fi

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

SOURCE="$SRC"
if [[ "$TEAMS" -eq 1 ]]; then
  SOURCE="$(mktemp)"
  { cat "$SRC"; printf '\n'; teams_section 1 "$REPO_ROOT/templates/teams"; } > "$SOURCE"
fi

build_cursor_rules "$SOURCE" "$REPO_ROOT" "$OUT_DIR"

LANGUAGE_BODY="$(mktemp)"
language_section "$LANG_MODE" "$REPO_ROOT/templates/language" > "$LANGUAGE_BODY"
write_cursor_rule "$OUT_DIR/language.mdc" "the language the agent replies in" "$LANGUAGE_BODY"
rm -f "$LANGUAGE_BODY"

[[ "$SOURCE" == "$SRC" ]] || rm -f "$SOURCE"

echo "build-cursor.sh: wrote $OUT_DIR"
