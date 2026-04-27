# Global Instructions

Rules are split by topic across files in `~/.claude/rules/`. Each file is pulled in via an `@` import — Claude Code expands these at session start.

## Code conventions
- @rules/naming.md — naming for classes, methods, variables
- @rules/architecture.md — file organization, SOLID, hexagonal backend, FSD frontend
- @rules/python.md — Python type annotations and pytest conventions

## Quality
- @rules/testing.md — AAA, mocking only at boundaries, fixtures vs parametrization
- @rules/errors.md — fail-fast, boundary validation, structured logging
- @rules/review.md — self-review checklist before commit

## Process
- @rules/workflow.md — spec-first development, task steps
- @rules/commits.md — commit message format, granularity, no AI attribution
- @rules/coding-discipline.md — think-before-coding, simplicity, surgical changes, goal-driven execution

## Tooling
- @rules/code-navigation.md — tool priority: LSP / code-skeleton / Grep / Read
- @rules/skills.md — user skill triggers (`/graphify`, ...)
