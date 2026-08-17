#!/bin/bash
# PreToolUse (Bash). Before a `git commit` / `arc commit`, run the uncommitted
# changes through codex in two passes: (1) review, (2) apply fixes straight into
# the files. No human confirmation is asked for: the hook always returns
# permissionDecision:"allow" and puts the review plus the fix report into
# additionalContext. Fail-open: when codex fails the commit goes through as is,
# with a warning.
#   git review: codex exec -s read-only -C <root> review --uncommitted
#   arc review: arc diff | codex exec --skip-git-repo-check -s read-only -C <root> "<prompt>"
#   fixes:      <review> | codex exec -s workspace-write -C <root> "<fix-prompt>"
#
# Kill switches (any one of them makes the hook exit quietly, and the commit
# takes its normal path):
#   CODEX_COMMIT_REVIEW_DISABLED=1  — env of the Claude Code process (needs a
#     session restart);
#   the file ~/.claude/codex-commit-review.disabled — created/removed on the
#     fly, path overridable through CODEX_COMMIT_REVIEW_FLAG;
#   codex not installed.
CODEX_COMMIT_REVIEW_FLAG="${CODEX_COMMIT_REVIEW_FLAG:-$HOME/.claude/codex-commit-review.disabled}"
[[ "$CODEX_COMMIT_REVIEW_DISABLED" == "1" ]] && exit 0
[[ -e "$CODEX_COMMIT_REVIEW_FLAG" ]] && exit 0

input=$(cat)
tool=$(printf '%s' "$input" | jq -r '.tool_name // empty')
command=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')

[[ "$tool" != "Bash" ]] && exit 0

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

file_hash() {
  local f="$1"
  [[ -f "$f" ]] || { printf 'absent'; return; }
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 1 -- "$f" | cut -d' ' -f1
  elif command -v sha1sum >/dev/null 2>&1; then
    sha1sum -- "$f" | cut -d' ' -f1
  else
    cksum -- "$f" | cut -d' ' -f1
  fi
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
  "$vcs commit: could not resolve an existing commit directory from the command. No review and no auto-fixes ran, the commit goes through as is."

# No codex — none of the hook's business: exit quietly, the commit takes its
# normal path (no allow, no context for the agent).
CODEX_BIN="${CODEX_BIN:-$(command -v codex 2>/dev/null)}"
[[ -x "$CODEX_BIN" ]] || exit 0

# The temp-file registry lives in a file rather than an array: mktmp is called
# through $(...), and an assignment to a parent variable from a subshell never
# arrives.
TMPLIST=$(mktemp)
mktmp() { local f; f=$(mktemp); printf '%s\n' "$f" >>"$TMPLIST"; printf '%s' "$f"; }
cleanup() { [[ -s "$TMPLIST" ]] && xargs rm -f <"$TMPLIST" 2>/dev/null; rm -f "$TMPLIST"; }
trap cleanup EXIT

CODEX_REVIEW_TIMEOUT="${CODEX_REVIEW_TIMEOUT:-600}"
run_codex() {
  local stdin_file="$1" out_file="$2" err_file="$3"
  shift 3
  "$@" <"${stdin_file:-/dev/null}" >"$out_file" 2>"$err_file" &
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
rc=0

if [[ "$vcs" == "git" ]]; then
  repo_root=$(git -C "$target_dir" rev-parse --show-toplevel 2>/dev/null) || true
  [[ -z "$repo_root" ]] && allow "git commit: repository not found; review skipped." \
    "git commit, but no git repository was found from $target_dir. No review and no auto-fixes ran, the commit goes through as is."
  [[ -z "$(git -C "$repo_root" status --short 2>/dev/null)" ]] && exit 0
  vcs_root="$repo_root"

  run_codex "" "$out" "$err" \
    "$CODEX_BIN" exec -s read-only -C "$repo_root" review --uncommitted
  rc=$?
else
  arc_root=$( (cd "$target_dir" 2>/dev/null && arc rev-parse --show-toplevel 2>/dev/null) )
  [[ -z "$arc_root" ]] && arc_root=$( (cd "$target_dir" 2>/dev/null && arc root 2>/dev/null) )
  [[ -z "$arc_root" ]] && allow "arc commit: working copy not found; review skipped." \
    "arc commit, but no arc working copy was found from $target_dir. No review and no auto-fixes ran, the commit goes through as is."
  [[ -z "$( (cd "$arc_root" && arc status --short 2>/dev/null) )" ]] && exit 0
  vcs_root="$arc_root"

  diff_file=$(mktmp)
  # Review what actually goes into the commit: the staged diff (`arc commit`
  # commits the index). The unstaged fallback covers the `arc commit -a`
  # workflow without a preceding `arc add`. Otherwise the unstaged diff is
  # empty after `arc add` and codex has nothing to review.
  (cd "$arc_root" && { arc diff --cached 2>/dev/null; arc diff 2>/dev/null; }) >"$diff_file"
  run_codex "$diff_file" "$out" "$err" \
    "$CODEX_BIN" exec --skip-git-repo-check -s read-only -C "$arc_root" \
    "You are a strict code reviewer. The <stdin> block holds the diff of uncommitted changes in an arc working copy. Do a code review: first the findings ordered by severity (critical -> minor), each with file:line, then a short summary. If there is nothing to report, say so explicitly. Note that untracked files may be missing from the diff."
  rc=$?
fi

review=$(cat "$out")

if [[ "$rc" -ne 0 || -z "$review" ]]; then
  err_tail=$(tail -n 5 "$err" 2>/dev/null)
  allow "codex review failed (rc=$rc); the commit goes through unreviewed." \
    "The codex review before $vcs commit failed (rc=$rc). No auto-fixes were applied, the changes go into the commit as is. Details: ${err_tail:-no stderr}"
fi

# Index snapshot taken BEFORE the auto-fixes: only files that were already in
# the index and that codex actually changed get re-staged. Files the author
# left outside the index are not pulled into the commit; if the command itself
# contains an `add`, it picks the fixes up on its own (the hook runs before the
# command executes).
staged_list=()
staged_hash=()
while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  staged_list+=("$f")
  staged_hash+=("$( (cd "$vcs_root" && file_hash "$f") )")
done < <( (cd "$vcs_root" && "$vcs" diff --cached --name-only 2>/dev/null) )

fix_out=$(mktmp)
fix_err=$(mktmp)
fix_args=("$CODEX_BIN" exec)
[[ "$vcs" == "arc" ]] && fix_args+=(--skip-git-repo-check)
fix_args+=(-s workspace-write -C "$vcs_root")
run_codex "$out" "$fix_out" "$fix_err" "${fix_args[@]}" \
  "You are a senior engineer. The <stdin> block holds a code review of the uncommitted changes in this working copy. Apply the fixes straight into the files: only objective, local findings (bugs, logic errors, crashes, leaks, contract violations, typos in identifiers). Do NOT apply stylistic or taste findings, do not refactor beyond the touched changes, do not bend tests to the implementation, do not revert the author's changes, do not create new files. If there is nothing to apply, change nothing. Finish with a report: a line 'APPLIED:' listing (file:line - what was done) and a line 'SKIPPED:' listing the rest with a reason."
fix_rc=$?

fix_report=$(cat "$fix_out")
if [[ "$fix_rc" -ne 0 ]]; then
  fix_err_tail=$(tail -n 5 "$fix_err" 2>/dev/null)
  fix_report="THE AUTO-FIX PASS FAILED (rc=$fix_rc). Details: ${fix_err_tail:-no stderr}
${fix_report}"
fi

restaged=()
for ((i = 0; i < ${#staged_list[@]}; i++)); do
  f="${staged_list[i]}"
  [[ "$( (cd "$vcs_root" && file_hash "$f") )" == "${staged_hash[i]}" ]] && continue
  (cd "$vcs_root" && "$vcs" add -- "$f" >/dev/null 2>&1) && restaged+=("$f")
done

restaged_text="(nothing)"
[[ "${#restaged[@]}" -gt 0 ]] && restaged_text=$(printf '%s\n' "${restaged[@]}")

allow "Codex: review done, fixes applied automatically (files re-staged: ${#restaged[@]})." \
  "Codex review and auto-fixes before the commit ($vcs, $vcs_root):

=== REVIEW ===
$review

=== AUTO-FIX REPORT ===
$fix_report

=== RE-STAGED ===
$restaged_text

=== $vcs status --short AFTER THE FIXES ===
$( (cd "$vcs_root" && "$vcs" status --short 2>/dev/null) )

Files on disk may have changed: re-read the affected files before editing them further."
