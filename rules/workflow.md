# Workflow

## Development Workflow
When given a task, follow these steps in order:

1. **Understand** — read the task, explore relevant code
2. **Clarify** — on ambiguity, first resolve it yourself from the code and
   docs; ask the user as early as possible only what needs their decision
3. **Implement** — write code following the conventions above
4. **Review** — self-review changes against CLAUDE.md rules before presenting
5. **Commit** — create a commit only when user approves
6. **Push** — push only when user explicitly asks and all tests pass

Rules:
- Never skip steps — each step must complete before the next begins
- Always pause for user approval between Review → Commit
- If the task is trivial (typo, one-line fix), step 2 can be skipped
- If the project's docs warn that a command is destructive (mass reformat,
  data loss), say so before running it, even when the user asked for it
