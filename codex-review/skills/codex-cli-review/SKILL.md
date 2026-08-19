---
name: codex-cli-review
description: Run an independent, VCS-neutral code review through `codex exec` from a supplied scope file and optional rules file. Use when a hook, script, CI job, another harness, or a Codex agent needs a structured CLI review. Do not use this skill to discover Git or Arc changes.
---

# Codex CLI Review

## Objective

Invoke `$code-review` in a fresh, read-only Codex CLI process and return a structured review. Require the caller or a VCS adapter to materialize the review scope first.

## Input Contract

Require:

- a target directory used as the child Codex working root;
- a UTF-8 scope file containing the exact diff, files, or change-set instructions to review.

Accept an optional UTF-8 rules file containing relevant instructions from the parent context. When an agent calls this adapter, collect applicable review and code-quality rules already available to that agent and write a concise, faithful rules file.

Do not run Git, Arc, or another VCS to invent a scope. Ask the caller for the scope instead.

## Invocation

Resolve the script relative to this skill as `scripts/codex_review.py`, then run:

```bash
python3 <skill-directory>/scripts/codex_review.py \
  --cwd <target-directory> \
  --scope-file <scope-file> \
  --rules-file <rules-file>
```

Omit `--rules-file` only when the caller has no additional contextual rules. The child still loads applicable target-tree instructions.

The script:

- explicitly invokes `$code-review` instead of relying on implicit skill selection;
- uses a read-only sandbox and allows non-Git roots;
- disables hooks in the child and sets a recursion guard;
- uses an ephemeral session;
- validates the final response against `review-output.schema.json`;
- prints the structured review JSON to stdout;
- sends actionable execution errors to stderr.

Exit code `0` means the review completed, even when findings exist. Treat nonzero status as execution failure. Keep policy decisions such as blocking a merge outside this adapter.

## Hook and Harness Use

Call the script from any harness after that harness materializes scope and rules files. Redirect stdout to the desired artifact or parse the JSON directly. Do not assume hook configuration is portable between harnesses.

When running interactively, read the JSON, verify referenced source lines, discard unsupported findings, and present findings before the summary. In unattended automation, keep the result advisory unless a separate, explicit gate defines blocking policy.

## Failure Handling

- Report missing files, unavailable CLI, authentication failures, nonzero child status, and invalid JSON distinctly.
- Do not silently replace a requested CLI review with a different reviewer.
- Do not edit source files during review.
