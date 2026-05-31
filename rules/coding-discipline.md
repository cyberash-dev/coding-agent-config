# Coding Discipline

Behavioral defaults for coding tasks. Bias toward caution and minimalism over
speed. Use judgment for trivial work.

## Think Before Coding
Don't assume. Don't hide confusion. Surface tradeoffs.
- State assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them — don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.
- Don't guess APIs, versions, flags, commit SHAs, or package names.
  Verify by reading the code or docs before asserting.

## Simplicity First
Minimum code that solves the problem. Nothing speculative.
- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Hard size caps (enforced mechanically by the shared ESLint config; exceeding one
means split or refactor, never raise the limit):
- A function body stays under 80 non-blank lines.
- A function takes at most 7 parameters; past that, pass an object.
- A class or interface exposes at most 10 public methods and 10 public properties.

Sanity check: "Would a senior engineer call this overcomplicated?" If yes, simplify.

## Surgical Changes
Touch only what you must. Clean up only your own mess.
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it — don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

Test: every changed line should trace directly to the user's request.

## Self-Documenting Code
Code should explain itself through clear names and structure. Comments are a
last resort, not a default.
- No comments that describe WHAT the code does — well-named identifiers do that.
- No comments restating the obvious, marking sections, or narrating changes
  ("added for X", "used by Y", "fixes bug Z") — that belongs in commit messages.
- No docstrings or block comments on trivial functions.
- No code snippets or usage examples inside comments — those belong in tests
  or external docs.
- Use the block form `/* */`, not `//` line comments.
- Keep any surviving comment short: a few lines of prose at most (the shared
  ESLint config caps it at 4). Needing more means the code wants restructuring,
  not a longer comment.
- If a comment feels needed, first try: better name, smaller function,
  extracted variable. Comment only if those don't resolve the confusion.

Leave a comment ONLY for genuinely non-obvious WHY: a hidden constraint,
a subtle invariant, a workaround for a specific external bug, behavior that
would surprise a careful reader. When in doubt — don't.

## Goal-Driven Execution
Define success criteria. Loop until verified.

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria
("make it work") require constant clarification.
