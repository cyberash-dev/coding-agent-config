# Python

## Type Annotations
- All function/method arguments MUST have type annotations
- Return types MUST be annotated when the function returns a value
- Avoid overly generic types (`str`, `object`, `Any`, `dict`, `list`) — choose the
  most specific type based on context and existing code patterns:
  - `HttpUrl` instead of `str` for URLs
  - `Mapping[str, int]` instead of `dict` when you only read
  - `Sequence[X]` / `Iterable[X]` instead of `list` when you only iterate
  - `Literal[...]` / `Enum` instead of `str` for closed sets of values
  - Domain types (e.g. `UserId`, `Money`) instead of primitives

## Pytest
- If a fixture is passed to a test but **not used** in the test body, use
  `@pytest.mark.usefixtures("fixture_name")` instead of adding it as a parameter
- Prefer parametrization (`@pytest.mark.parametrize`) over loops inside tests
- One behavioral aspect per test — split rather than assert many things at once
