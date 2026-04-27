# Self-Review Checklist

Run through this list before presenting changes or committing.

## Scope
- [ ] Every changed line traces directly to the user's request
- [ ] No "while I was here" refactors, formatting tweaks, or comment polish
- [ ] No new abstractions that aren't used at least twice
- [ ] No speculative configurability, flags, or hooks

## Cleanup
- [ ] No orphan imports/variables/functions left by my own changes
- [ ] No dead code I added (commented-out blocks, unused helpers)
- [ ] No debug prints, `console.log`, `breakpoint()`, `TODO(me)` left behind

## Conventions
- [ ] Names follow `naming.md` (nouns for queries, verbs for commands,
      `is*/has*/can*` for booleans)
- [ ] Architecture matches `architecture.md` (slice boundaries, dependency
      direction, no leakage from `domain/`)
- [ ] Style matches the surrounding file — even if I'd write it differently
- [ ] Python: type annotations on every argument (see `python.md`)

## Tests
- [ ] New behavior has a test; bug fix has a regression test
- [ ] Tests follow `testing.md` (AAA, no internal mocks, descriptive names)
- [ ] All tests pass locally

## Errors
- [ ] No swallowed exceptions, no fallbacks for impossible states
- [ ] Validation only at boundaries (see `errors.md`)

## Communication
- [ ] If I made a non-obvious choice, I can explain why in one sentence
- [ ] If I deviated from the user's stated approach, I flagged it
