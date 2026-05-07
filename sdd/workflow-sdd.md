# Workflow — SDD Addendum

Extends `@rules/workflow.md` for projects that use Spec-Driven Development.
When the project carries `.sdd/config.json`, the steps below are mandatory
and override the trivial-task exception in `@rules/workflow.md`.

## Specification-First Development
If the project has a specification (e.g. `/spec` folder):
1. **Read spec first** — before any code changes, review the relevant spec files
2. **Update spec** — make all changes in the specification first
3. **Lint spec** — `sdd lint` MUST exit 0 before proceeding (see `sdd-cli-usage.md`)
4. **Get approval** — confirm spec changes with the user before touching code; for `proposed → approved` use `sdd approve` (attestation) + `sdd finalize` (atomic flip)
5. **Implement** — write code that matches the updated specification
6. **Ready check** — `sdd ready` MUST exit 0 before proposing commit
- Code MUST stay in sync with the spec at all times
- Never change code without a corresponding spec update
- Never bypass `sdd ready` exit 1 to land a commit

### Preflight before any Edit/Write to code
Before the first `Edit`/`Write`/`MultiEdit` on a non-spec file in a session,
explicitly verify:
1. Does this project have a specification directory (`/spec` or equivalent)?
2. If yes — name the exact spec file(s) that govern the change and confirm
   they are already updated and approved for this task. If they are not,
   STOP and go back to step Spec.
3. State both answers in chat before the tool call. Silent skipping is the
   failure mode this rule exists to prevent.

This preflight applies even in Auto mode and even on tasks that look trivial.
Spec-presence overrides the "trivial task" exception in `@rules/workflow.md`.

## SDD-augmented Development Workflow
The numbered steps from `@rules/workflow.md` are extended as follows when
the project has a specification:

1. **Understand** — read the task, explore relevant code
2. **Clarify** — ask questions if requirements are ambiguous
3. **Spec** — update the specification first (see above)
3a. **Spec-lint** — run `sdd lint`; do not proceed until exit 0 (only when project carries `.sdd/config.json`)
4. **Implement** — write code following the conventions above
5. **Review** — self-review changes against CLAUDE.md rules before presenting
5a. **Ready** — run `sdd ready`; do not commit until exit 0 (only when project carries `.sdd/config.json`)
6. **Commit** — create a commit only when user approves
7. **Push** — push only when user explicitly asks

Pause-for-approval rule is widened: pause between **Spec → Implement** and
between **Review → Commit** (instead of just the second).

## sdd-cli integration

The `sdd` CLI is part of the SDD workflow when the project carries
`.sdd/config.json` and a `BrownfieldBaseline` block. Operational rules,
phase-to-command mapping, and troubleshooting are in
`@sdd/sdd-cli-usage.md`. The lint reminder is wired via
`sdd/hooks/sdd-lint-reminder.sh` (PreToolUse on Edit/Write/MultiEdit for
spec files).
