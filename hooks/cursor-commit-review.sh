#!/usr/bin/env bash
# beforeShellExecution (Cursor). Entry point for the commit review under
# Cursor's hook protocol; the review itself lives in codex-commit-review.sh,
# which switches its input parsing and its output envelope on this variable.
exec env COMMIT_REVIEW_PROTOCOL=cursor \
  "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/codex-commit-review.sh"
