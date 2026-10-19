#!/usr/bin/env bash
# DeepSeek Harness entry point for the commit review. DSH has no hook protocol
# of its own: it calls the script the agent's profile names with the event's
# JSON on stdin and reads a one-shot approval out of stdout. This wrapper
# answers an ordinary git commit with a refusal carrying the review text, and
# lets every other command through untouched.
#
# The review itself stays in codex-commit-review.sh, which switches its input
# parsing and output envelope on COMMIT_REVIEW_PROTOCOL. DSH shares Claude
# Code's envelope shape — `tool_name` / `tool_input` on stdin, a nested
# `hookSpecificOutput` with `permissionDecision` on stdout — so it runs that
# branch. A refusal is re-emitted verbatim: DSH reads permissionDecisionReason
# as the reason it hands back to the agent.

input=$(cat)

decision=$(printf '%s' "$input" \
  | COMMIT_REVIEW_PROTOCOL=claude "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/codex-commit-review.sh") || exit 0

printf '%s' "$decision" | jq -c '
  if (.hookSpecificOutput.permissionDecision // "") == "deny" then
    .hookSpecificOutput
  else empty end
' 2>/dev/null

exit 0
