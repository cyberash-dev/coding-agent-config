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

## What to mock
- Mock only at **system boundaries**: external APIs, clock, filesystem, network,
  randomness, message brokers
- Do NOT mock internal collaborators just to isolate a unit — test the slice
  end-to-end through its public entry point. Internal mocks couple tests to
  structure and rot on every refactor
- Prefer **fakes** (in-memory implementations) over mocks when feasible

## Fixtures vs Parametrization
- Use **fixtures** for setup that's reused and conceptually shared
- Use **parametrization** when the same logic runs against many inputs —
  do not loop inside a test
- Keep fixtures small and composable; avoid "god fixtures" that build half
  the world

## Determinism
- Tests must be order-independent and seed-stable
- No real time, real network, real database without explicit opt-in
- Failing test must point to the cause — assertion messages should be specific
