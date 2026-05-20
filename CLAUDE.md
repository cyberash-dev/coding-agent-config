# Global Instructions

Rules are split by topic across files in `~/.claude/rules/`. Each file is pulled in via an `@` import — Claude Code expands these at session start.

## Code conventions
- @rules/naming.md — naming for classes, methods, variables
- @rules/architecture.md — file organization, SOLID, hexagonal backend, FSD frontend
- @rules/python.md — Python type annotations and pytest conventions

## Quality
- @rules/tdd.md — red-green-refactor, when to apply, anti-patterns
- @rules/testing.md — AAA, mocking only at boundaries, fixtures vs parametrization
- @rules/errors.md — fail-fast, boundary validation, structured logging
- @rules/review.md — self-review checklist before commit

## Process
- @rules/workflow.md — task steps, pause for approval
- @rules/commits.md — commit message format, granularity, no AI attribution
- @rules/coding-discipline.md — think-before-coding, simplicity, surgical changes, goal-driven execution

## Output
- @rules/output-style.md — concise output, no filler, no emojis or em-dashes

## Tooling
- @rules/code-navigation.md — tool priority: LSP / code-skeleton / Grep / Read
