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
- Every test asserts on an observable result. A test that only calls the code,
  or passes merely because nothing was thrown, checks nothing. When "does not
  raise" is the behavior, assert it explicitly
- Expected values are literals written by hand. Never compute the expectation
  with the production code or a copy of its algorithm — the test then agrees
  with any bug in it
- Assert only what the behavior defines. Don't compare a whole payload or
  snapshot when the test is about one field; unrelated details make it break
  on every harmless change
- Test the core behavior, not just the easy side effects around it (a log line,
  a call count, a row existing)
- Coverage points at untested code; it is never the goal. Don't write tests to
  hit lines

## What to mock
- Mock only at **system boundaries**: external APIs, clock, filesystem, network,
  randomness, message brokers
- Do NOT mock internal collaborators just to isolate a unit — test the slice
  end-to-end through its public entry point. Internal mocks couple tests to
  structure and rot on every refactor
- Prefer **fakes** (in-memory implementations) over mocks when feasible
- Assert observable behavior through the public entry point (the handler's
  response, the value actually forwarded downstream), never the mock's own
  output, a schema definition, or generated/contract structure (reflection
  guards). A test that would pass without exercising real behavior tests the
  framework, not the code
- A test with more mocks than real collaborators tests the mocks. Move it to a
  level where the real code runs
- Don't bend production code for a test: no reflection into private state, no
  widened visibility, no test-only methods or flags. If a behavior can't be
  observed through the public API, inject the boundary it depends on

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
- No constants or test-data modules shared between tests either. A literal
  reused across tests is hidden context: each test states its own inputs
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
- Test files live next to the code they exercise, following the project's
  test-location convention — don't park them in a separate `tests/regression/`
  tree away from the code under test
- Confirm a new test is actually collected and executed by the suite (wired
  into the build/test target). A present-but-unrun test gives false coverage
- Match test count to behavior complexity. Don't pile near-duplicate cases on
  trivial logic; cover the key cases plus the untested siblings, and drop
  redundant guard tests that assert nothing about real behavior
- Organize tests by behavior, not one test per production method. A test lives
  in the file of the unit it exercises. A test file grown to hundreds of cases
  signals a unit that does too much: flag it
- Tests are silent when green: no `print` or log output on success. Diagnostic
  detail belongs in the failure message

## Prove the test can fail
- A test written against code that already exists was never red. Break the
  code under test on purpose (invert the condition, return a constant), confirm
  the test goes red on its assertion, then restore the code. A test that stays
  green is useless: rewrite it
- When an existing test goes red, it found something. Don't change its expected
  value to whatever the code returns now unless the task changed that behavior;
  otherwise report the regression

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
- Keep tests that need real services in a separately selectable suite (marker
  or directory) so the default run stays fast and offline
- No `sleep` to wait for async work. Wait on the condition with a bounded
  timeout, or drive a fake clock/scheduler
- Write files only into a per-test temporary directory from the framework
  (`tmp_path`), never into the repo or home. Don't depend on the machine's
  locale, timezone, env vars, or absolute paths — set what the test needs
- No retry-on-failure plugins or annotations. A flaky test is a bug in the test
  or the code: reproduce and fix it
- A DB query without `ORDER BY` returns rows in nondeterministic order; a test
  asserting a fixed order is flaky — add `ORDER BY` or sort before asserting
- Failing test must point to the cause — assertion messages should be specific
