# Spec-Driven Development

Spec is the single source of truth for code generation. Change the spec first, then generate code. Behavior in code that is not in the spec is either lifted into the spec or removed; never legitimized silently.

## Atomic unit: typed normative ID

Every normative statement is an ID-element with one of these templates:
`Behavior`, `Invariant`, `Contract`, `Scenario`, `NFR`, `Constraint`, `Policy`, `Migration`, `Delta`, `GeneratedArtifact`, `ExternalDependency`, `LocalizationContract`, `Surface`, `Partition`, `ImplementationBinding`, `Open-Q`, `ASSUMPTION`.

- IDs are semantically neutral and partition-scoped: `<partition>:<neutral>` (e.g. `billing:REQ-017`). Numbers are never reused.
- Each field is typed: `enum | scalar_with_unit | range_with_unit | schema_dsl | predicate_dsl | reference | bounded_free_text_with_review`.
- Required fields take a typed value or explicit `not_applicable + reason`. Empty = invalid.
- Predicates must be checkable from observable inputs/outputs/state. `Invariant` may use `evidence ∈ {public_api, test_probe, db_constraint, operational_signal}` + `stability ∈ {contractual, internal}` — only `public_api` and `contractual` operational signals are external contract.

## What spec MUST fix
External behavior · `Surface`/`Contract` boundaries · `Invariant` · external identifiers (API fields, events, CLI, public DB columns, error codes, message_ids) · `ExternalDependency` (third-party providers) · `Policy` (authz/tenant/PII/audit/rate-limit) · `Migration` (data at-rest) · `applicability` (feature_flag, tenant, locale, env, plan_tier, api_version) · `concurrency_model` on boundaries.

## What spec MUST NOT fix
Internal file/module/class/function names · library/framework choice (unless a `Constraint` with external rationale) · directory layout · internal layering not observable from outside · estimates, schedules, owners.

The agent decides everything not normatively fixed. The agent MUST list its internal decisions in the PR as candidates for new `REQ`/`Constraint`/`Policy`/`ASSUMPTION`.

## Lifecycle and approval

- `lifecycle.status ∈ {draft, proposed, approved, deprecated, removed}` — for every normative template.
- `draft` — sandbox only (`spike/`). `proposed` — spec-valid, not mergeable. `approved` — implementable. `deprecated` — has `sunset_version` + `replacement_id`. `removed` — has `compatibility_action ∈ {reject, ignore, migrate, no_longer_guaranteed}`.
- `approval_record` (owner_role, approver_identity, timestamp, change_request) is required for `approved`/`deprecated`/`removed`. **Self-approval by the code-gen agent is forbidden** — also for downgrading `ASSUMPTION` `blocking → advisory`.
- Approving a Surface requires every referenced normative ID to be `≥ approved` already.
- Approval is a two-step process. Step 1 records a `pending_approval_record` in a plan-namespace artefact (no change to `lifecycle.status`); step 2 validates the resulting reference graph and atomically materialises `lifecycle.status=approved` plus an ID-level `approval_record`. Between steps the invariant «`approved` ⇒ graph-consistent» is preserved by construction. Self-approval ban applies to step 1 (the attestation), not just to step 2. See `rules/enforcement_registry.md#ENF-002`.
- `Surface` is the unit of semver. Bumping `Policy` or `Invariant(stability=contractual)` cascades to every referencing Surface: content change ⇒ ≥minor; predicate change ⇒ major.

## Three gates (per partition)

1. **`baseline-valid`** — `Discovery scope` is covered by `coverage_evidence`; `freshness_token` matches input sources. Each `Delta`/`Migration` pins to a `baseline_version`. Stale baseline blocks only the move into `implementation-valid`, not authoring of new `Delta`/`Open-Q`. `baseline_refresh` MUST emit `diff(old, new)` and auto-open `Delta`-stub or `Open-Q` for any change crossing a normative ID footprint.
2. **`spec-valid`** — structure, Template Requiredness Matrix, field types, no weasel words in normative sections, two-way `ID ↔ Test obligation`, semver per Surface, `approval_record` present, no self-approval, no unresolved `Open-Q.blocking=yes`.
3. **`implementation-valid`** — every `Test obligation` materialized as ≥1 executable test with `@covers <partition>:<id>`; all `approved` IDs green; `removed` IDs have tests for their `compatibility_action`; agent's internal decisions listed in PR. **Signal, not proof** — for major-bump `Surface`, human review of the test (oracle/assertion summary, input classes, negative oracle) is required.

## Brownfield rules

- `Brownfield baseline` is non-normative until a `REQ`/`Invariant`/`Contract` references it as preserved.
- Anything outside `Discovery scope` is `unmodeled` — never silently deleted, renamed or rewritten. Expanding scope requires recon.
- Every behavior change → `Delta` (with `kind`, `compatibility_action`, `tests_old_behavior`, `tests_new_behavior`, `baseline_version`).
- Data-at-rest changes → `Migration`. Two orthogonal axes: spec-lifecycle `{draft..removed}` (governance) and runtime-state `{pre_cutover, in_progress, cutover_done, rolled_back}` (operational evidence). Cross-partition migrations use `partition_slice[]` + `coordinator_id`, not joint approval.
- `Invariant`/`Contract` with `data_scope=post_migration:<MIG-ID>` MUST carry `enforcement_stage` pointing to a **deterministic test-controllable marker in the repo** (feature flag, completion sentinel, `cutover_marker`) — never a live deployment signal. CI runs pre/during/post tests by toggling the marker.
- `implementation-valid` only checks tests applicable to the current Migration runtime-state.
- Iterative debt budget: each partition tracks `unmodeled` / legitimate-debt that shrinks per PR/sprint. "Bring as-is to target in one PR" is not required.

## Stop conditions (agent MUST raise `Open-Q`, not guess)

Term not in `Glossary` · behavior outside `Discovery scope` · code↔spec contradiction without `Delta` · weasel word in a normative section · removal without `compatibility_action` · missing `Policy`-ref on a boundary · missing `applicability` when an axis variable is detectable · missing `concurrency_model` on a boundary · missing `data_scope` on persistent state · provider-owned behavior without `ExternalDependency` · generated output without `GeneratedArtifact` · text-as-contract without `LocalizationContract` · missing `baseline_version` on `Delta`/`Migration` · `proposed → approved` Surface while a referenced Policy/Contract is not yet approved · `Migration` runtime-state change without updating dependent `enforcement_stage` · structural-breaking diff in `GeneratedArtifact(published_surface=yes)` without major bump.

Stop conditions split by enforcement class: `agent-halt` (reflex on a closed condition — term not in `Glossary`, code↔spec contradiction without `Delta`, removal without `compatibility_action`, missing `Policy`-ref / `applicability` / `concurrency_model` / `data_scope` / `baseline_version` on declared boundaries) and `agent-judgment` (semantic classification — provider-owned → `ExternalDependency`, generated output → `GeneratedArtifact`, text-as-contract → `LocalizationContract`). The split is normative for the PR-report shape: `agent-halt` produces a list of raised `Open-Q`s with trigger references; `agent-judgment` produces a list of classification decisions with rationale. Full mapping in `rules/enforcement_registry.md` rows ENF-005, ENF-006, ENF-023..ENF-034.

## Forbidden in normative sections
Canonical list lives at `skills/spec-driven-development/data/weasel-words.json`. Two classes: `absolute` (blocked in any normative section) and `modal_in_normative` (`may be`, `might be` — blocked only in template fields marked `is_normative=true`; allowed in `Context`, `Glossary`, comments, and in `Scenario`-prose where the alternative is captured by an explicit `options[]`/branching). See `rules/enforcement_registry.md#ENF-001`. Conditional fields take a value from a closed enum; `not_applicable` requires `reason`.

## PR report (every change)
- Closed `Test obligation`s and the tests that close them (with oracle/assertion summary, input classes, negative oracle for major-bump).
- Internal decisions taken (names, structure, libraries) — candidates for new `Constraint`/`Policy`/`ASSUMPTION`.
- `ASSUMPTION`s used and their `review_by`.
- Remaining `Open-Q`s and why they don't block this PR.
- Reduction of `unmodeled` / legitimate-debt budget vs previous PR.

## Agent flow on existing code
1. Read-only recon → `Discovery scope` + `Brownfield baseline` + `coverage_evidence`. No `Delta`/`Migration` until `baseline-valid`.
2. Author target → `Surface`/`Contract`/`Policy`/`Constraint`/`Delta`/`Migration` against the baseline.
3. Make tests fail (red) per `Test obligation` before implementing.
4. Implement; only modify what the spec authorizes.
5. Self-review against this rule and `review.md` before presenting.
