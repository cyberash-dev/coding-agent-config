# Workflow

## Specification-First Development
If the project has a specification (e.g. `/spec` folder):
1. **Read spec first** — before any code changes, review the relevant spec files
2. **Update spec** — make all changes in the specification first
3. **Get approval** — confirm spec changes with the user before touching code
4. **Implement** — write code that matches the updated specification
- Code MUST stay in sync with the spec at all times
- Never change code without a corresponding spec update

## Development Workflow
When given a task, follow these steps in order:

1. **Understand** — read the task, explore relevant code
2. **Clarify** — ask questions if requirements are ambiguous
3. **Spec** — if project has a specification, update it first (see above)
4. **Implement** — write code following the conventions above
5. **Review** — self-review changes against CLAUDE.md rules before presenting
6. **Commit** — create a commit only when user approves
7. **Push** — push only when user explicitly asks

Rules:
- Never skip steps — each step must complete before the next begins
- Always pause for user approval between Spec → Implement and Review → Commit
- If the task is trivial (typo, one-line fix), steps 2-3 can be skipped
