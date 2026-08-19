---
name: code-review
description: Review a supplied code change or explicit file set using all applicable contextual, repository, language, and quality rules. Use whenever Codex is asked to review, audit, or inspect code in the app, CLI, IDE, automation, or another review adapter. Do not implement fixes unless the user explicitly changes the task.
---

# Code Review

## Objective

Produce a focused, evidence-backed review of the supplied scope. Treat this skill as the canonical review policy. Keep CLI invocation and VCS-specific scope collection in separate adapters.

## Inputs

Identify before reviewing:

- the exact change set, diff, commit, or files in scope;
- the target root used to resolve files and repository instructions;
- explicit review criteria supplied by the user or calling adapter;
- additional rules supplied by a parent agent or harness.

Use the scope provided by the user, review surface, or adapter. If no scope is available and selecting one would require a VCS assumption, ask for the scope instead of guessing.

## Applicable Rules

1. Collect relevant instructions already present in the current context.
2. Load applicable target-tree instructions such as `AGENTS.md`, `CLAUDE.md`, or their documented equivalent.
3. Apply explicit user criteria plus relevant language, architecture, testing, security, naming, error-handling, and project best-practice rules.
4. Resolve conflicts according to instruction priority. Among compatible rules at the same priority, apply the most specific rule covering the changed file.
5. Keep the rule set scoped to the reviewed code. Do not invent, weaken, or silently omit requirements.

Treat applicable rules as review criteria. Report only violations supported by the review target. Treat process requirements that cannot be verified from available evidence as residual risk, not findings.

## Workflow

1. Understand the intended behavior from the task, change description, tests, and surrounding contracts.
2. Inspect every changed file in scope plus only the unchanged callers, consumers, schemas, migrations, or tests needed to verify behavior.
3. Check applicable concerns:
   - correctness and regressions;
   - security, privacy, authorization, and data loss;
   - concurrency, transactions, ordering, and idempotency;
   - external contracts, compatibility, migrations, queries, and indexes;
   - architecture, types, errors, logging, naming, and maintainability required by applicable rules;
   - missing tests for changed behavior, invalid inputs, boundaries, and error paths.
4. Verify every candidate finding against the source and scope.
5. Remove duplicates, preference-only advice, pre-existing issues unrelated to the change, and claims without a concrete failure scenario.

## Finding Contract

Report a finding only when all of these are available:

- a precise file and line when the source has a stable location;
- the triggering input, state, or execution path;
- the observable impact;
- evidence that the reviewed change introduced or materially exposed the issue;
- the applicable rule when the finding depends on a contextual requirement;
- a concrete remediation.

Use priorities consistently:

- `P0`: immediate, widespread security, data-loss, or availability failure;
- `P1`: high-impact defect likely to block release or normal operation;
- `P2`: actionable defect affecting a realistic path;
- `P3`: low-impact but real defect, not optional polish.

## Output

Lead with findings ordered by priority. Keep summaries secondary.

When a caller supplies an output schema, conform to it exactly. Otherwise report each finding with priority, title, location, evidence, impact, applicable rule, and remediation.

If no finding survives verification, say so clearly. List residual risks and tests not run. Do not edit files, commit, push, or apply patches during review.
