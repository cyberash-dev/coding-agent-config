# Test-Driven Development

Tests come before the code that makes them pass. Loop: **Red → Green → Refactor**,
one behavior at a time. Don't pile multiple failing tests before writing code.

This file is about *when and how* to write the test relative to the code.
For test structure (AAA, what to mock, fixtures vs parametrization) see
`testing.md`.

## Red — write a failing test

- The smallest test for the **next** behavior. Not three, not five.
- The test must fail for the **right reason**: assertion failure on observable
  output. If it fails on import error, missing symbol, or typo — fix the test
  first, then re-run to confirm it now fails on the assertion.
- Test names describe observable behavior, not the TDD step
  (`test_withdraw_rejects_amount_above_balance`, not `test_step_1`).
- If you can't formulate a failing test, you don't yet understand the behavior.
  Stop and clarify — do not improvise an implementation.

## Green — make it pass with minimum code

- Minimum code that turns the red test green. Hardcode a literal if that's
  literally all the test demands.
- Resist:
  - Adding code "for the next test" — wait until that test is red.
  - Generalizing too early — wait for the second or third test to drive the
    abstraction.
  - Polishing names, extracting helpers, tidying structure — that's the
    refactor phase.
- Ugly green is fine. The next phase fixes it.

## Refactor — improve structure under green

- Tests stay green throughout. Re-run after every meaningful change.
- Refactor only **structure**: rename, extract, inline, deduplicate, move.
  No new behavior, no changed behavior.
- If you discover a missing behavior mid-refactor, finish the refactor first,
  commit, then go back to Red. Never sneak features into a refactor commit
  (see `commits.md` → Granularity).

## When to apply TDD

- **Default for**: bug fixes (regression test first), new public functions,
  business logic, code with clear inputs/outputs, anything you'd otherwise
  drive with `print` or a REPL.
- **Skip TDD for**: exploratory spikes, throwaway scripts, code where the
  answer is visual (UI tweak, layout, copy change). For UI/visual work,
  prefer tests on the **observable contract** (events emitted, ARIA,
  data flow), not pixel positions. If even those don't fit, say so explicitly
  rather than faking TDD.

## Bug fixes

A bug fix without a regression test is incomplete.

1. Reproduce the bug as a failing test (red, for the right reason).
2. Fix the code (green).
3. Refactor if the fix exposed structural issues.

The regression test must fail on the unfixed code and pass on the fixed code.
"It works locally" is not a substitute.

## Granularity — outside-in vs inside-out

Pick one strategy per task; state the choice if it's non-obvious.

- **Outside-in** — start with an acceptance / integration test, let unit
  tests fall out as collaborators emerge. Good when the integration shape is
  clearer than the unit decomposition.
- **Inside-out** — drive small units first, then wire them together. Good
  when the domain is well-understood and decomposition is obvious.

## Anti-patterns

- **Test-after** ("test-validated development"). The test must have been red
  against absent behavior. A test written after the code only confirms what
  already works — it doesn't drive design.
- **Going green by weakening assertions or deleting the test.** If a test no
  longer makes sense, replace it with one that does and explain why; never
  drop coverage silently to ship.
- **Refactoring without green.** Refactoring requires a passing safety net.
  If tests are red, finish the Red→Green cycle before touching structure.
- **Batching** — writing five tests, then implementing all at once. You lose
  the discipline that the smallest failing test gives you, and you can't tell
  which test drove which decision.
- **Implementation-coupled tests** (`assert obj._cache.size == 1`). Tests
  asserting on internals rot on every refactor. Test observable behavior
  (`testing.md`).
- **TDD theatre** — writing a trivial passing test (`assert add(1,1) == 2`)
  to claim TDD. The test must drive a design decision, not rubber-stamp one.
- **Mixing cycles in one commit.** Red, Green, and Refactor are three
  separate disciplines. Either commit each phase, or commit one full
  Red→Green pair without smuggling refactor noise into it.

