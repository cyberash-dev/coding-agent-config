# TDD — SDD Addendum

Extends `@rules/tdd.md` for projects that carry `.sdd/config.json`.
The Red→Green→Refactor cycle still holds, but the **source of the Red test**
and the **definition of done** are anchored to the spec.

## Where Red comes from

Red tests are not invented from intuition. Each Red test closes a
`Test obligation` declared on a normative ID (`Behavior` / `Invariant` /
`Contract` / `Migration` / `Delta`). One ID may declare several obligations
(happy path, boundary, negative) — each is its own Red test, written one at
a time.

If you can't trace a test to a `Test obligation`, the test doesn't belong.
Either raise an `Open-Q` to extend the spec, or skip the test. Tests that
don't trace to a normative ID become candidates for new
`Constraint` / `Policy` / `ASSUMPTION` — raise them, don't smuggle them in
as silent green-keepers.

## The full SDD-TDD chain

For every change:

1. **Spec** — author / amend the relevant ID(s) and their `Test obligation`s.
2. **Spec-lint** — `sdd lint` exit 0 (gate `spec-valid`).
3. **Red** — for each open `Test obligation`, write one failing test
   carrying `@covers <partition>:<id>`. Test fails on assertion, not on a
   missing import. One Red at a time.
4. **Green** — minimum code to turn the current Red green. Only what the
   spec authorizes — no behavior outside an approved ID.
5. **Refactor** — structure only, tests stay green, observable behavior
   on `approved` IDs unchanged.
6. **Implementation-valid** — `sdd ready` exit 0
   (gate `implementation-valid`). Coverage holes surface here.

Skipping any step (writing code before Red, committing on `sdd ready`
exit 1, etc.) violates the SDD invariant "spec is the source of truth".
See `@sdd/sdd-cli-usage.md` for command-by-command gate mapping.

## `@covers` markers

Every Red test that closes a `Test obligation` must carry
`@covers <partition>:<id>` (in a comment, or the language-equivalent
location `sdd ready` reads in this project). Missing markers surface as
`[uncovered]` even if the test exists and passes.

If a `Test obligation` is `not_applicable`, the spec must carry an explicit
`not_applicable + reason`. No `@covers` and no Red test in that case — do
not fabricate a trivial test to silence the gate
(see `@rules/tdd.md` → Anti-patterns: TDD theatre).

## Migration runtime-state

`Migration` carries two orthogonal axes — spec-lifecycle (`draft..removed`)
governs `sdd lint`; `runtime_state ∈ {pre_cutover, in_progress,
cutover_done, rolled_back}` governs which tests are applicable.

Tests for `Invariant` / `Contract` with `data_scope = post_migration:<MIG-ID>`
must be wired to the `enforcement_stage` marker (feature flag, completion
sentinel, `cutover_marker`) so CI can deterministically toggle pre / during
/ post. Live deployment signals as the marker are forbidden
(see `@sdd/spec-driven-development.md` → Brownfield rules).

`sdd ready` only checks tests applicable to the current `runtime_state`.
A pre-cutover test that's red after `runtime_state=cutover_done` is not a
gate failure — it's an obsolete test. Re-scope via spec or delete as part
of cutover.

## Removed IDs — replace, don't drop

When an ID transitions to `removed`, do not silently delete its tests.
Replace each test with one that verifies the declared `compatibility_action`:

- `reject` → old input now produces the typed error.
- `ignore` → old input is accepted but produces no effect.
- `migrate` → old input is transformed per spec.
- `no_longer_guaranteed` → test removed; document the gap in PR
  (ENF-007B).

Removing a test without replacing it is a coverage drop and `sdd ready`
will flag it.

## Major-bump Surface

For a Surface with a major bump (predicate change on `Policy` or
`Invariant(stability=contractual)`) the Red test alone is signal, not
proof. `implementation-valid` passes mechanically, but ENF-004B requires
human review of:

- input classes the test covers,
- negative oracle (what must NOT pass),
- assertion summary.

When the agent writes a major-bump Red, name these three explicitly in the
test docstring or PR description. The reviewer needs them to validate
oracle quality.

## Halt mid-Red

While writing a Red test, halt and raise `Open-Q` if you hit:

- a term not in `Glossary`,
- behavior outside `Discovery scope`,
- code↔spec contradiction without a `Delta`,
- missing `Policy` ref, `applicability`, `concurrency_model`, or
  `data_scope` on a boundary the test exercises,
- missing `baseline_version` on the `Delta` / `Migration` you're closing.

Do not improvise the test to "make progress". Full stop-condition list:
`@sdd/spec-driven-development.md` → Stop conditions.

## Refactor under SDD

Refactor must keep tests green **and** preserve every observable behavior
declared on `approved` IDs:

- Internal renaming, extraction, dedup → fine.
- Updating an `ImplementationBinding` target (file / class / function) →
  fine, as long as the binding is updated in lockstep.
- Renaming a public `Surface` field, changing a `Contract` shape, altering
  an `Invariant` predicate → **not refactor**. That's a `Delta` —
  stop, edit spec, re-lint, re-Red.

If you discover a missing `Test obligation` mid-refactor, finish the
refactor commit, then go back to Spec → Red. Don't extend the obligation
list inside a refactor commit (see `@rules/commits.md` → Granularity).
