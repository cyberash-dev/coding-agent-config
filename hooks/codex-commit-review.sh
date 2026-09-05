#!/usr/bin/env bash
# Before a `git commit` / `arc commit`, run the uncommitted changes through a
# read-only codex review and hand the findings to the agent. Nothing on disk is
# touched. Fail-open: when codex fails the commit goes through as is, with a
# warning.
#   review: python3 <codex-cli-review skill>/scripts/codex_review.py
#             --cwd <root> --scope-file <status + diff>
#
# Both harnesses refuse the commit and hand the review over as the reason: the
# findings have to reach the agent before the commit exists, and under Cursor a
# hook message reaches the agent only on a refusal anyway. The agent acts on the
# findings and re-runs the commit; the scope hash of the reviewed change is
# remembered, so a retry on an unchanged scope is let through instead of
# starting another review.
#
# What a review costs is (turns × context), and the child re-sends its context on
# every turn, so the change has to be worth a pass at all: a diff of nothing but
# prose or lock files (CODEX_REVIEW_SKIP_PATHS) or under CODEX_REVIEW_MIN_LINES
# lines is let through unreviewed, and one over CODEX_REVIEW_MAX_SCOPE_BYTES is
# truncated with the cut declared in the scope. The child's own CODEX_HOME —
# review-scoped rules, small model, no MCP servers, no plugins — is the review
# skill's business, not the hook's.
#
# Two envelopes for that refusal, selected by COMMIT_REVIEW_PROTOCOL:
#   claude (default) — PreToolUse (Bash), permissionDecision:"deny" with the
#     review in permissionDecisionReason.
#   cursor — beforeShellExecution, entered through cursor-commit-review.sh,
#     permission:"deny" with the review in agent_message.
#
# The review owns no policy of its own: the skill script starts a read-only
# codex on the supplied scope under $code-review and returns the review as JSON.
# Both are installed together by `install.sh --codex-review`.
#
# Kill switches (any one of them makes the hook exit quietly, and the commit
# takes its normal path):
#   CODEX_COMMIT_REVIEW_DISABLED=1  — env of the agent process (needs a
#     session restart);
#   the file ~/.claude/codex-commit-review.disabled — created/removed on the
#     fly, path overridable through CODEX_COMMIT_REVIEW_FLAG;
#   codex not installed;
#   jq or python3 not installed.
# The install anchors .claude at %USERPROFILE% on Windows, because Git Bash
# derives $HOME from HOMEDRIVE/HOMEPATH. Follow it, or the kill switch lands in
# a directory the agent never reads. Same rule as scripts/lib/platform.sh; this
# hook runs standalone and cannot source it.
agent_home() {
  if [[ -n "${USERPROFILE:-}" ]] && command -v cygpath >/dev/null 2>&1; then
    cygpath -u "$USERPROFILE"
    return
  fi
  printf '%s' "$HOME"
}
CODEX_COMMIT_REVIEW_FLAG="${CODEX_COMMIT_REVIEW_FLAG:-$(agent_home)/.claude/codex-commit-review.disabled}"
[[ "$CODEX_COMMIT_REVIEW_DISABLED" == "1" ]] && exit 0
[[ -e "$CODEX_COMMIT_REVIEW_FLAG" ]] && exit 0
command -v jq >/dev/null 2>&1 || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

PROTOCOL="${COMMIT_REVIEW_PROTOCOL:-claude}"

input=$(cat)
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')
if [[ "$PROTOCOL" == "cursor" ]]; then
  command=$(printf '%s' "$input" | jq -r '.command // empty')
else
  tool=$(printf '%s' "$input" | jq -r '.tool_name // empty')
  command=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
  [[ "$tool" != "Bash" ]] && exit 0
fi

is_commit() {
  local vcs="$1"
  # `\n` belongs in both char classes: a newline is a command separator (so a
  # `git commit` on its own line, after `git add` etc., is detected), AND the
  # inter-token gap must not cross a newline (so a `commit` word in a LATER
  # line — e.g. inside a following `echo "...commit..."` — is not falsely
  # matched, which used to fire the review on a no-op post-commit command).
  local re='(^|[;&|'$'\n''][[:space:]]*)'"$vcs"'([[:space:]]+[^;&|'$'\n'']*)?[[:space:]]commit([[:space:]]|$)'
  [[ "$command" =~ $re ]]
}

vcs=""
if is_commit git; then
  vcs=git
elif is_commit arc; then
  vcs=arc
else
  exit 0
fi

# $1 — short reason for the UI, $2 — full context for the agent (defaults to $1).
allow() {
  if [[ "$PROTOCOL" == "cursor" ]]; then
    jq -n --arg r "$1" '{permission: "allow", user_message: $r}'
    exit 0
  fi
  jq -n --arg r "$1" --arg c "${2:-$1}" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "allow",
      permissionDecisionReason: $r,
      additionalContext: $c
    }
  }'
  exit 0
}

# $1 — short reason for the UI, $2 — the review itself, for the agent.
deny() {
  if [[ "$PROTOCOL" == "cursor" ]]; then
    jq -n --arg r "$1" --arg c "$2" '{permission: "deny", user_message: $r, agent_message: $c}'
    exit 0
  fi
  jq -n --arg c "$2" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $c
    }
  }'
  exit 0
}

text_hash() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 1 | cut -d' ' -f1
  elif command -v sha1sum >/dev/null 2>&1; then
    sha1sum | cut -d' ' -f1
  else
    cksum | cut -d' ' -f1
  fi
}

# Where the hash of an already reported review is kept, per working copy.
state_path() {
  printf '%s/.cache/coding-agent-config/commit-review/%s' \
    "$(agent_home)" "$(printf '%s' "$1" | text_hash)"
}

# Effective commit directory: the session cwd plus any `cd …` applied in the
# && / || / ; chain before the commit, then `git -C …`. Best-effort: subshells
# `( … )` and variables are not expanded — in that case resolution falls through
# to a fail-open allow.
resolve_commit_dir() {
  local cmd="$1" eff="$2" vcs="$3" stmt path cflag
  while IFS= read -r stmt || [[ -n "$stmt" ]]; do
    if [[ "$stmt" =~ ^[[:space:]]*cd[[:space:]]+([^[:space:]].*)$ ]]; then
      path="${BASH_REMATCH[1]}"
      # Take the path only: quoted — up to the closing quote; unquoted — the
      # first token. Otherwise a tail like ` 2>/dev/null` / ` >log` ends up in
      # the path, `cd` cannot find the directory, and resolution falls through
      # to the fail-open allow.
      if [[ "$path" == [\"\']* ]]; then
        q="${path:0:1}"; body="${path:1}"; path="${body%%"$q"*}"
      else
        read -r path _ <<< "$path"
      fi
      path="${path/#\~/$HOME}"
      [[ -n "$path" ]] || continue
      [[ "$path" == /* ]] && eff="$path" || eff="$eff/$path"
    fi
    if [[ "$stmt" =~ (^|[[:space:]])"$vcs"[[:space:]] && "$stmt" =~ [[:space:]]commit([[:space:]]|$) ]]; then
      if [[ "$vcs" == git && "$stmt" == *" -C "* ]]; then
        local -a toks; local i
        read -ra toks <<< "$stmt"
        for ((i = 0; i < ${#toks[@]} - 1; i++)); do
          [[ "${toks[i]}" == "-C" ]] || continue
          cflag="${toks[i + 1]}"
          cflag="${cflag%[\"\']}"; cflag="${cflag#[\"\']}"; cflag="${cflag/#\~/$HOME}"
          [[ "$cflag" == /* ]] && eff="$cflag" || eff="$eff/$cflag"
          break
        done
      fi
      break
    fi
  done < <(printf '%s' "$cmd" | sed -E 's/&&|\|\||;/\n/g')
  ( cd "$eff" 2>/dev/null && pwd )
}

target_dir=$(resolve_commit_dir "$command" "${cwd:-$PWD}" "$vcs")
[[ -z "$target_dir" ]] && allow "$vcs commit: could not resolve the commit directory; review skipped." \
  "$vcs commit: could not resolve an existing commit directory from the command. No review ran, the commit goes through as is."

# No codex — none of the hook's business: exit quietly, the commit takes its
# normal path (no verdict, no context for the agent).
command -v codex >/dev/null 2>&1 || exit 0

# The temp-file registry lives in a file rather than an array: mktmp is called
# through $(...), and an assignment to a parent variable from a subshell never
# arrives.
TMPLIST=$(mktemp)
mktmp() { local f; f=$(mktemp); printf '%s\n' "$f" >>"$TMPLIST"; printf '%s' "$f"; }
cleanup() { [[ -s "$TMPLIST" ]] && xargs rm -f <"$TMPLIST" 2>/dev/null; rm -f "$TMPLIST"; }
trap cleanup EXIT

CODEX_REVIEW_TIMEOUT="${CODEX_REVIEW_TIMEOUT:-600}"
# A review costs a full model pass over the change, so the change has to be
# worth one. Set either gate to nothing (empty list, floor of 0) to switch it off.
CODEX_REVIEW_SKIP_PATHS="${CODEX_REVIEW_SKIP_PATHS-*.md *.rst *.adoc *.lock package-lock.json pnpm-lock.yaml go.sum LICENSE NOTICE}"
CODEX_REVIEW_MIN_LINES="${CODEX_REVIEW_MIN_LINES:-10}"
CODEX_REVIEW_MAX_SCOPE_BYTES="${CODEX_REVIEW_MAX_SCOPE_BYTES:-200000}"
run_with_timeout() {
  local out_file="$1" err_file="$2"
  shift 2
  "$@" </dev/null >"$out_file" 2>"$err_file" &
  local cmd_pid=$! elapsed=0
  while kill -0 "$cmd_pid" 2>/dev/null; do
    if [[ "$elapsed" -ge "$CODEX_REVIEW_TIMEOUT" ]]; then
      kill -TERM "$cmd_pid" 2>/dev/null
      sleep 1
      kill -KILL "$cmd_pid" 2>/dev/null
      break
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  wait "$cmd_pid" 2>/dev/null
  return $?
}

out=$(mktmp)
err=$(mktmp)

if [[ "$vcs" == "git" ]]; then
  vcs_root=$(git -C "$target_dir" rev-parse --show-toplevel 2>/dev/null) || true
  [[ -z "$vcs_root" ]] && allow "git commit: repository not found; review skipped." \
    "git commit, but no git repository was found from $target_dir. No review ran, the commit goes through as is."
else
  vcs_root=$( (cd "$target_dir" 2>/dev/null && arc rev-parse --show-toplevel 2>/dev/null) )
  [[ -z "$vcs_root" ]] && vcs_root=$( (cd "$target_dir" 2>/dev/null && arc root 2>/dev/null) )
  [[ -z "$vcs_root" ]] && allow "arc commit: working copy not found; review skipped." \
    "arc commit, but no arc working copy was found from $target_dir. No review ran, the commit goes through as is."
fi

# Nothing uncommitted — no review to run, and no commit to hold up.
# With `color.ui = always` a status code arrives behind an escape sequence and
# no gate recognises it.
uncoloured() {
  sed $'s/\033\[[0-9;]*[a-zA-Z]//g'
}

status_text=$( (cd "$vcs_root" && "$vcs" status --short 2>/dev/null) | uncoloured )
[[ -n "$status_text" ]] || exit 0

# A status line is two status characters, a space, then the path, which status
# quotes when it carries a space. A rename prints `old -> new` and both sides
# count: moving a module to a documentation name is not a documentation change.
changed_paths() {
  status_paths
  untracked_files
}

# Tracked entries only: status collapses a new directory into one `dir/` entry,
# which no basename gate can match, so untracked paths come from the walk below.
status_paths() {
  printf '%s\n' "$status_text" | awk '
    NF && $0 !~ /^\?\?/ {
      path = substr($0, 4)
      arrow = index(path, " -> ")
      if (arrow) {
        print unquoted(substr(path, 1, arrow - 1))
        print unquoted(substr(path, arrow + 4))
      } else {
        print unquoted(path)
      }
    }
    function unquoted(value) {
      gsub(/^"|"$/, "", value)
      return value
    }'
}

is_skipped_path() {
  local name="${1##*/}" pattern
  local -a patterns
  # Split the list on whitespace WITHOUT expanding it: unquoted, `*.md` would
  # first become the names of the .md files next to the hook's own cwd, and
  # every other path would then be reviewed.
  set -f
  patterns=( $CODEX_REVIEW_SKIP_PATHS )
  set +f
  for pattern in ${patterns[@]+"${patterns[@]}"}; do
    # shellcheck disable=SC2053  # $pattern is a glob on purpose
    [[ "$name" == $pattern ]] && return 0
  done
  return 1
}

# One path per line, relative to the root: the files the commit would add, with
# a collapsed directory opened and ignored descendants left out. Short status
# quotes a path that carries a space, so the listing is asked for directly and
# the parse is a fallback for a VCS that cannot list.
untracked_files() {
  local listed path
  listed=$( (cd "$vcs_root" && "$vcs" ls-files --others --exclude-standard -z 2>/dev/null) \
    | tr '\0' '\n' )
  if [[ -n "$listed" ]]; then
    printf '%s\n' "$listed"
    return
  fi
  ( cd "$vcs_root" || return
    while IFS= read -r path; do
      [[ -e "$path" ]] || continue
      find "$path" -type f 2>/dev/null
    done < <(printf '%s\n' "$status_text" | sed -nE 's/^\?\?[[:space:]]//p') )
}

# Untracked files carry no diff at all, so a new file would read as a zero-line
# change and duck the floor its content deserves. Status collapses a new
# directory into a single `dir/` entry, so the walk has to open it.
untracked_lines() {
  local path total=0
  while IFS= read -r path; do
    [[ -f "$vcs_root/$path" ]] || continue
    total=$((total + $(awk 'END { print NR + 0 }' "$vcs_root/$path")))
  done < <(untracked_files)
  printf '%s' "$total"
}

reviewable_paths=0
while IFS= read -r changed_path; do
  is_skipped_path "$changed_path" || { reviewable_paths=1; break; }
done < <(changed_paths)

[[ "$reviewable_paths" -eq 1 ]] || allow \
  "$vcs commit: prose and lock files only; review skipped." \
  "The $vcs commit changes only paths the review gate skips ($CODEX_REVIEW_SKIP_PATHS). No review ran, the commit goes through as is."

diff_file=$(mktmp)
# Review what actually goes into the commit: the staged diff (`commit` commits
# the index). The unstaged half covers the `commit -a` workflow without a
# preceding `add`. Otherwise the unstaged diff is empty after `add` and codex
# has nothing to review.
(cd "$vcs_root" && { "$vcs" diff --cached 2>/dev/null; "$vcs" diff 2>/dev/null; }) >"$diff_file"

# What the gates parse. The file itself stays verbatim: it is what the reviewer
# reads and what the retry is fingerprinted by, and a diff can carry an escape
# sequence of its own that belongs to the change.
diff_text() {
  uncoloured < "$diff_file"
}

# Every added or removed line inside a hunk. Header lines live outside one, so
# content that starts with a sign of its own — a `+- item` YAML entry, a
# removed `-- comment` — is counted rather than mistaken for a header.
diff_lines() {
  diff_text | awk '
    /^@@/ { in_hunk = 1; next }
    /^diff / { in_hunk = 0; next }
    in_hunk && /^[+-]/ { changed++ }
    END { print changed + 0 }'
}

# Changes a diff cannot count in lines, none of them small: a file that moved
# or vanished for everything that consumed it, a script that gained or lost its
# executable bit, a binary replaced wholesale.
has_structural_change() {
  printf '%s\n' "$status_text" | grep -qE '^[RD]|^.[RD]' && return 0
  diff_text | grep -qE '^(old mode |new mode |Binary files |GIT binary patch)'
}

changed_lines=$(( $(diff_lines) + $(untracked_lines) ))
[[ "$changed_lines" -ge "$CODEX_REVIEW_MIN_LINES" ]] || has_structural_change || allow \
  "$vcs commit: $changed_lines changed line(s); review skipped." \
  "The $vcs commit changes $changed_lines line(s), under the review floor of $CODEX_REVIEW_MIN_LINES. No review ran, the commit goes through as is."

# The skill lands in a different root per harness, and the hook may be running
# under a harness that is not the one that installed it.
review_script() {
  local root candidate
  for root in "$(agent_home)/.claude/skills" "$(agent_home)/.agents/skills" "$(agent_home)/.cursor/skills"; do
    candidate="$root/codex-cli-review/scripts/codex_review.py"
    [[ -f "$candidate" ]] && { printf '%s' "$candidate"; return 0; }
  done
  return 1
}

REVIEW_SCRIPT="$(review_script)" || allow "codex-cli-review skill is not installed; review skipped." \
  "The codex-cli-review skill was not found under ~/.claude/skills, ~/.agents/skills or ~/.cursor/skills, so no review ran before the $vcs commit. Re-run install.sh with --codex-review. The commit goes through as is."

# Scope handed to the reviewer; its hash is what a retry is recognised by.
scope_file=$(mktmp)
diff_bytes=$(wc -c < "$diff_file")
{
  printf 'Review the current uncommitted %s working-copy changes.\nRepository root: %s\n\n' "$vcs" "$vcs_root"
  printf '<%s_status>\n%s\n</%s_status>\n\n' "$vcs" "$status_text" "$vcs"
  printf '<%s_diff>\n' "$vcs"
  # A diff past the cap is a generated or vendored bulk change: the reviewer
  # would re-send every byte of it on every turn, so it is cut and said to be cut.
  if [[ "$diff_bytes" -gt "$CODEX_REVIEW_MAX_SCOPE_BYTES" ]]; then
    # Dropping the cut line keeps the scope valid UTF-8: a byte cap lands
    # inside a multibyte character sooner or later, and the reviewer reads the
    # file as UTF-8 or not at all.
    head -c "$CODEX_REVIEW_MAX_SCOPE_BYTES" "$diff_file" | sed '$d'
    printf '\n[diff truncated to %s of %s bytes; the rest of the change was not reviewed]\n' \
      "$CODEX_REVIEW_MAX_SCOPE_BYTES" "$diff_bytes"
  else
    cat "$diff_file"
  fi
  printf '</%s_diff>\n\n' "$vcs"
  printf 'Inspect the exact untracked files listed by status. Read unchanged files only when needed to verify a finding. Do not scan unrelated directories.\n'
} >"$scope_file"

STATE_FILE="$(state_path "$vcs_root")"
# Fingerprint the change itself, not the scope the reviewer was handed: a
# truncated scope hashes the same after an edit past the cut, and the retry
# would be waved through as already reviewed.
change_hash="$( { printf '%s' "$status_text"; cat "$diff_file"; } | text_hash )"
if [[ -f "$STATE_FILE" ]] \
   && [[ "$(cat "$STATE_FILE")" == "$change_hash" ]]; then
  rm -f "$STATE_FILE"
  allow "Codex: this change was already reviewed; the commit goes through."
fi

run_with_timeout "$out" "$err" \
  python3 "$REVIEW_SCRIPT" --cwd "$vcs_root" --scope-file "$scope_file"
rc=$?

review=$(cat "$out")

if [[ "$rc" -ne 0 || -z "$review" ]]; then
  err_tail=$(tail -n 5 "$err" 2>/dev/null)
  allow "codex review failed (rc=$rc); the commit goes through unreviewed." \
    "The codex review before $vcs commit failed (rc=$rc). The changes go into the commit unreviewed. Details: ${err_tail:-no stderr}"
fi

context="Codex review before the commit ($vcs, $vcs_root):

=== REVIEW (JSON) ===
$review

Nothing was changed on disk: the findings are yours to weigh."

# Fail-open when the retry marker cannot be stored. A refusal the retry cannot
# clear is a refusal for good: every attempt would review the same scope again
# and stop the commit again.
if ! mkdir -p "$(dirname "$STATE_FILE")" 2>/dev/null \
   || ! printf '%s' "$change_hash" >"$STATE_FILE" 2>/dev/null; then
  allow "Codex: review done, the retry marker could not be stored; the commit goes through." \
    "$context

The retry marker under $(dirname "$STATE_FILE") could not be written, so the commit was let through instead of refused."
fi

deny "Codex: the commit was stopped so the review reaches you." \
  "$context

Apply what you agree with and re-run the same commit command: an unchanged scope goes straight through, an edited one is reviewed again."
