# Testing

## Structure
- **AAA**: Arrange / Act / Assert — separate the three phases visually
  (blank lines or comments) so a reader sees what's set up, what's exercised,
  and what's checked
- One behavioral aspect per test. If a test name contains "and", it probably
  should be two tests
- Test names describe **observable behavior**, not implementation:
  - GOOD: `test_withdraw_rejects_amount_above_balance`
  - BAD:  `test_withdraw_calls_validate_then_update`
- No `if` / `for` / `while` / `try` in a test body. Branching means a second
  test; iteration means parametrization. Conditional assertions hide which
  branch actually ran on failure
- A test reads top-to-bottom on its own. A reader should understand setup,
  action, and expectation without jumping into fixtures or helpers

## What to mock
- Mock only at **system boundaries**: external APIs, clock, filesystem, network,
  randomness, message brokers
- Do NOT mock internal collaborators just to isolate a unit — test the slice
  end-to-end through its public entry point. Internal mocks couple tests to
  structure and rot on every refactor
- Prefer **fakes** (in-memory implementations) over mocks when feasible

## No fixtures, no setUp/tearDown
- **Do not use fixtures, `setUp`/`tearDown`, or `conftest`-level shared
  setup.** Every test constructs its own state inline. A reader sees the
  full Arrange phase in the test body, not scattered across files
- Repetition in setup is preferable to hidden context. Three similar tests
  that each build their object explicitly beat three terse tests sharing a
  fixture you have to chase down
- If construction is genuinely noisy, extract a **plain function** with an
  explicit name (`a_user_with_balance(100)`) and call it from Arrange.
  Functions are honest — fixtures rely on framework magic and ordering
- Use **parametrization** when the same test logic runs against many
  inputs — do not loop inside a test
- Exception: if the project already uses fixtures pervasively, match the
  surrounding style (per `coding-discipline.md` → Surgical Changes); flag
  the divergence rather than mass-rewriting

## Test code quality
- Test code is production-grade. Same bar for naming, duplication, and
  dead code as in the code under test
- No copy-pasted blocks across tests — extract a small named helper or
  parametrize. Repetition that obscures intent is worse than abstraction
- No commented-out assertions. No `skip` / `xfail` without an explicit
  reason and a ticket reference
- Failure messages must point to the cause. Prefer specific assertions
  (`assertEqual(x, 3)`) over generic ones (`assertTrue(x == 3)`)

## Negative paths
- Every public behavior has tests for invalid input, boundary values, and
  error paths — not just the happy path. A green happy-path test alone
  does not cover a behavior
- Exception tests assert on the **type and a stable message/code**, not
  just "something raised". `pytest.raises(ValueError, match=...)`,
  not bare `pytest.raises(Exception)`
- Probe the obvious edges: empty / null, max / overflow, off-by-one,
  duplicate input, time around DST / leap, locale / encoding,
  concurrency where it applies

## Independence & Determinism
- Tests must be order-independent and seed-stable
- No shared mutable global state. No singletons, module-level caches, or
  class-level state mutated by tests. If production code uses a singleton,
  reset it explicitly in setup, never rely on test order
- No test depends on another test having run (or not run) first
- No real time, real network, real database without explicit opt-in
- Failing test must point to the cause — assertion messages should be specific
