# Errors & Logging

## Error Handling
- **Fail fast** on bugs and unexpected state — raise/throw, don't paper over
- Catch exceptions only when you can **meaningfully recover** or **add context**
  before re-raising. `except: pass` is almost always wrong
- Validate at **system boundaries** (user input, external API responses,
  deserialization). Trust internal code — no defensive checks for impossible
  states (see `coding-discipline.md` → Simplicity First)
- Distinguish:
  - **Expected** failures (invalid input, not found, conflict) → typed error,
    handled by caller
  - **Bugs** (broken invariants) → exception/assert, surfaces to top-level
- Prefer specific exception types over generic `Exception` / `Error`

## Logging
- Log at the level that matches the event:
  - `DEBUG` — diagnostic detail, off in production
  - `INFO` — notable lifecycle events
  - `WARNING` — recoverable anomaly
  - `ERROR` — failed operation that needs attention
- Use **structured context** (key-value), not prose: `log.info("payment.processed", user_id=..., amount=...)`
- Never log secrets, tokens, full PII, raw request bodies that may contain them
- Don't log-and-rethrow — pick one. Logging at every layer creates noise

## Don't
- Don't add fallbacks for scenarios that can't happen
- Don't swallow exceptions to "make tests pass"
- Don't replace error messages with generic ones — preserve the original cause
