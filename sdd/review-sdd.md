# Self-Review — SDD Addendum

Extends the `## Tests` block of `@rules/review.md` when the project carries
`.sdd/config.json`. Add these checks alongside the existing test bullets
before presenting changes or committing.

## Tests (SDD)
- [ ] `sdd lint` exit 0 (if project carries `.sdd/config.json`)
- [ ] `sdd ready` exit 0 (if project carries `.sdd/config.json`)
