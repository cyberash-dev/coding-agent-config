# Review Rules

The rules a change is reviewed against. Every one of them is checkable from a
diff and the files it touches.

Process, navigation, orchestration and output-style rules are deliberately
absent: a read-only reviewer drives no workflow, writes no commit, and talks to
no operator, so carrying those rules would only re-send tokens on every turn.

## Code conventions
- @rules/naming.md
- @rules/architecture.md
- @rules/python.md
- @rules/typescript.md

## Quality
- @rules/tdd.md
- @rules/testing.md
- @rules/errors.md
- @rules/review.md

## Discipline
- @rules/coding-discipline.md

The rules above are already loaded. Do not go looking for them again in the
tree under review.
