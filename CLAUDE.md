# Global Instructions

Rules are split by topic across files in `~/.claude/rules/`. Each file is pulled in via an `@` import — Claude Code expands these at session start.

## Code conventions
- @rules/naming.md — naming for classes, methods, variables
- @rules/architecture.md — file organization, SOLID, hexagonal backend, FSD frontend

## Process
- @rules/workflow.md — spec-first development, task steps
- @rules/coding-discipline.md — think-before-coding, simplicity, surgical changes, goal-driven execution

## Tooling
- @rules/code-navigation.md — tool priority: LSP / code-skeleton / Grep / Read
- @rules/skills.md — user skill triggers (`/graphify`, ...)
