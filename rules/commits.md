# Commits

## Message Format
- Short imperative subject (≤72 chars): `add user lookup endpoint`,
  not `added` or `adds` or `feat: added`
- Body (when needed) explains **why**, not what — the diff already shows what
- Wrap body at ~72 chars; blank line between subject and body

## Granularity
- One logical change per commit. If the body needs "and", split the commit
- Refactors and behavior changes go in separate commits
- Don't bundle unrelated cleanups with the main change

## Authorship
- **Never** add `Co-Authored-By` or any AI co-authorship trailer
- **Never** add tool/agent attribution (`🤖 Generated with...`, etc.)

## Safety
- Don't amend published commits (already pushed/shared)
- Don't `push --force` to shared branches without explicit user request
- Don't skip hooks (`--no-verify`) unless the user explicitly asks; fix the
  underlying issue instead
