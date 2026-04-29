---
name: spec-driven-development
description: Full reference for spec-driven development on brownfield code. Use when writing, drafting, reviewing, auditing, or evolving a specification before code; when the user says spec-first, spec-driven, the spec is the source of truth, write a spec, draft a specification, review my spec, is this spec valid, spec out X, напиши спеку, составь спецификацию, спека первой, написать ТЗ, or описать в спеке. Covers typed normative templates, three gates, Brownfield baseline, Discovery scope, Delta, Migration, Surface semver, Policy, Contract, Invariant, Open-Q, ASSUMPTION, test obligations, and what belongs in the spec versus what the agent decides.
---

# Specification Authoring Rules for Spec-Driven Development

This document is the working manual for an agent that authors a specification against existing code (brownfield) and then maintains it as the single source of truth for downstream code generation. Every rule is operational: each one can be checked mechanically or as an explicit item in spec code review.

Foundational principle: **the specification is the single source of truth. Any change in system behavior appears in the spec first; only then is the code-gen agent invoked.** Behavior found in code but absent from the spec is never silently legitimized: it is either lifted into a normative element through `Discovery scope`/`Open-Q` via the standard process, or explicitly marked as `unmodeled` and never silently deleted or rewritten.

When to use this skill:
- the author writes a new spec or revises an existing one and must verify it is ready to hand off to a code-gen agent;
- the agent runs read-only reconnaissance on brownfield code and produces a `Brownfield baseline`;
- there is a dispute about which template fits a particular statement (Contract vs Invariant vs Policy vs Migration), which gate must pass first, or why the agent halted instead of implementing;
- a patch / PR needs to be checked against one of the silent invariants (semver cascade, Migration cycle, self-approval, baseline freshness).

For day-to-day use the condensed rule in `rules/spec-driven-development.md` is enough (the global CLAUDE.md imports it automatically). This skill is the full reference with tables and rationale, consulted when in doubt.

---

## 0. Lifecycle and the three gates

Spec and implementation are checked by three independent CI gates. **All gates run per `Partition`** (see §13), not "across the whole repository", otherwise any drift blocks everyone.

- **`baseline-valid`** — verifies that the partition's `Discovery scope` covers declared entrypoints / datasets / flags / tenants / environments / generated artifacts; every `coverage_evidence` entry references a machine-readable artefact (entrypoint registry, code-skeleton dump, IaC inventory, schema registry snapshot, DB introspection); the baseline contains no contradictory descriptions of the same as-is ID; the `freshness_token` (hash of recon input sources) matches the current state. **Every `Delta`/`Migration` MUST carry a `baseline_version` field pinning it to a specific baseline revision.** A `freshness_token` mismatch flips the baseline to `stale` but **does NOT block authoring of new `Delta`/`Open-Q`** against the pinned `baseline_version` — it only blocks the transition of those `Delta`/`Migration` into `implementation-valid` until rebase. Recovery from `stale` goes through **`baseline_refresh`**, which MUST emit a machine-readable `diff(baseline_old, baseline_new)` and **automatically open a `Delta` stub or `Open-Q` for every change crossing the footprint of an already-normative ID** — otherwise refresh becomes a back-door for silent removal of normative behavior.
- **`spec-valid`** — blocks the code-gen agent. Verifies completeness, machine-readable structure, fields populated per the `Template Requiredness Matrix` (§14), a `Test obligation` on every normative ID, no unresolved `Open-Q.blocking=yes`, no weasel words in normative sections, correct semver markup of the per-`Surface` diff, an `approval_record` on every `approved`/`deprecated`/`removed` ID, and a hard ban on self-approval by the code-gen agent.
- **`implementation-valid`** — blocks code merge. Verifies that every `Test obligation` is materialized into ≥1 executable test with a two-way ID reference, every `approved` ID is covered by green tests, every `removed` ID has tests for its `compatibility_action`, and every internal decision the agent took (and the spec did not fix) is enumerated in the PR. **This gate is a signal, not a proof**: a test can be syntactically green yet semantically vacuous; for a major-bump `Surface`, an explicit human review of the test is required (per-ID mutation-testing kill rate is recommended, not blocking).

---

## 1. The atomic unit: a typed normative ID-element

1.1. Every normative statement in the spec is materialized as an **ID-element** with a unique stable identifier.

1.2. The ID is **semantically neutral** at the local-number level: `REQ-017`, `CONTRACT-004`, `SCN-021`. Global uniqueness is composed via the partition namespace: `<partition_id>:<neutral_id>` (e.g. `billing:REQ-017`). The partition name is neutral (`billing`, `auth`), but it is not the domain semantics inside the element; renaming meaning inside an ID is forbidden, renaming a partition is a separate procedure with reference migration.

1.3. IDs are never reused. A removed element stays in the graph as a `removed` record; the number is not handed to a new element. Numbers are allocated through the partition's `id_namespace` — no central allocator is needed.

1.4. Every ID-element belongs to one of the following closed **templates**. The full list of required and conditional fields is in §14.

| Template | When to use |
|----------|-------------|
| `Behavior` | Synchronous observable behavior (single-actor). Fields: `given`, `when`, `then`, `negative_cases`, `out_of_scope`, `applicability`, `Policy`-ref, `concurrency_model` (C), `data_scope` (C). |
| `Invariant` | A property that always/never holds. Fields: `always`/`never`, `scope`, `evidence` (`public_api`/`test_probe`/`db_constraint`/`operational_signal`), `stability` (`contractual`/`internal`), `data_scope` (`new_writes_only`/`all_data`/`post_migration:<MIG-ID>`), `applicability`, `concurrency_model` (C), `negative_cases`, `out_of_scope`. |
| `Contract` | A boundary contract (HTTP API, DB schema, event, file format, CLI, error code). Fields: `Surface`-ref, `schema`, `preconditions`, `postconditions`, `external_identifiers`, `compatibility_rules`, `error_taxonomy` (R on boundary), `applicability`, `concurrency_model` (C), `data_scope` (C). |
| `Scenario` | Stateful / async / event-driven scenario. Fields: `initial_state`, `trigger`, `observable_sequence`, `ordering ∈ {strict, partial, unordered}`, `idempotency`, `retry_policy`, `timeout`, `applicability`. |
| `NFR` | Non-functional requirement. Fields: `target` (SLO/resource declaration with `metric`, `threshold`, `environment`), `verification_obligation` with `verification_stage ∈ {ci_unit, ci_integration, perf_lab, staging_canary, prod_slo}` and a reference to an artefact (load profile, dashboard query, SLO recorder). `implementation-valid` accepts "green" only for the matching stage; everything else is `awaiting_evidence:<stage>`. |
| `Constraint` | An external constraint on technology / implementation. Fields: `constraint`, `rationale` (regulatory / security / compatibility). |
| `Policy` | Authorization / tenant isolation / PII redaction / audit / rate-limit policy. Fields: `policy_kind`, `applicability` (scope of ID classes), `negative_test_obligations`. Every boundary `Contract`/`Behavior` MUST reference ≥1 `Policy` or carry `Policy: not_applicable` with rationale. |
| `Migration` | A change to data at-rest or a switchover procedure. Fields: `target_ids`, `direction ∈ {forward_only, reversible}`, `mode ∈ {online, offline, dual_write, backfill, dual_emit_with_legacy_text}`, `data_window`, `success_criteria`, `rollback_plan`, `tests_pre`, `tests_during`, `tests_post`, `data_scope`, `partition_slice[]` (migration slices per partition, each with its own `approval_record`), `coordinator_id` (single ID joining the slices), `enforcement_stage` (see §11), `runtime_state ∈ {pre_cutover, in_progress, cutover_done, rolled_back}` (see §11). A cross-partition Migration **MUST NOT** be authored as a single block with joint approval — it MUST be split via `partition_slice[]` with local approval per slice plus `coordinator_id`, otherwise the migration does not fit into the iterative debt budget §6. |
| `Delta` | A change in behavior relative to `As-is`. Fields: `target_id`, `kind ∈ {preserve, replace, remove, migrate}`, `compatibility_action ∈ {reject, ignore, migrate, no_longer_guaranteed}`, `tests_old_behavior`, `tests_new_behavior`, `baseline_version`. |
| `GeneratedArtifact` | Generated code / client / SDK. Fields: `source_ids`, `generator` + `version`, `command`, `output_paths`, `regeneration_mode ∈ {clean, with_whitelisted_patches:<PATCH-ID...>}`, `published_surface ∈ {yes, no}`, `Surface`-ref (R if `published_surface=yes`). |
| `ExternalDependency` | Third-party provider (Stripe, S3, CRM, identity provider). Fields: `provider`, `provider_surface@version`, `authority_url_or_doc`, `consumer_contract` (what we send and expect, pinned to `provider_surface@version`), `drift_detection.mechanism ∈ {contract_test_against_sandbox, openapi_diff, schema_registry_subscription, changelog_watcher, none_with_review_by:<date>}`, `last_verified_at`, `auth_scope` (C), `rate_limits` (C), `retry/idempotency` (C), `error_taxonomy` (C), `sandbox_or_fixture` (C). |
| `LocalizationContract` | Localization / internationalization. Fields: `message_id` (stable external identifier), `icu_args_schema`, `locale_coverage`, `fallback_chain`, `text_is_contract ∈ {yes, no}`, `timezone/currency/source` (C), `collation_rule` (C), `rtl_layout` (C). Boundary errors reference a stable `code/message_id`, never localized text. |
| `Surface` | An external compatibility unit (HTTP API, SDK, public DB schema, event bus, CLI, published generated artifact). Fields: `name`, `version`, `boundary_type ∈ {api, sdk, event_bus, cli, public_db, public_storage, generated_published_artifact}`, `members[]` (Contract-ID, GeneratedArtifact-ID), `consumer_compat_policy`. Semver applies per-Surface. |
| `Partition` | A team / domain area of responsibility. Fields: `partition_id` (neutral), `owner_team`, `gate_scope`, `dependencies_on_other_partitions[]` (only via `Surface@version`/`Policy@version` references), `default_policy_set[]` (see §10.1). |
| `Implementation binding` | A link between normative IDs and internal artefacts (table names, queues, jobs, storage keys). Fields: `target_ids`, `authority ∈ {code_annotation, migration_file, iac_state, schema_registry, db_introspection, manual_inventory}`, `verification_method`. Not normative for compatibility; used only where internal names are operationally unavoidable (`Migration`, test probes, data lifecycle). |
| `Open-Q` | An open question. Fields: `question`, `options[]` (≥2 with consequences), `blocking ∈ {yes, no}`, `owner`, `default_if_unresolved` (R when `blocking=no`). |
| `ASSUMPTION` | A default taken on a non-blocking `Open-Q` or an explicit assumption. Fields: `assumption`, `source_open_q` (if any), `blocking ∈ {yes, no}`, `review_by`, `default_if_unresolved`, `tests`, `partition_id`. |

1.5. **Field types instead of "closed enum for everything".** Normative fields are typed from a closed set: `enum`, `scalar_with_unit`, `range_with_unit`, `schema_dsl`, `predicate_dsl`, `reference`, `bounded_free_text_with_review`. Every field of every template declares its field type; the linter from §12 validates the value against the declared type. Free prose is allowed only in `Context`, `Glossary`, `bounded_free_text_with_review` (with an explicit review marker), and comments.

1.6. Every required field carries a value of the required field type or an explicit `not_applicable` with a one-line `reason`. An empty field in a normative section is invalid spec.

1.7. An element that cannot be checked from outside is rewritten via **`Invariant.evidence`**: only `evidence: public_api` and explicitly `stability: contractual` operational signals become external contract. `test_probe`, `db_constraint`, internal `operational_signal` are allowed for verification but not for compatibility with external consumers (this does not promote logs and metrics into a public API).

---

## 2. Spec document structure

A partition's spec document MUST contain the following sections in this exact order:

1. **`Context`** (non-normative). Any statement in `Context` referenced by code or tests MUST be lifted into a normative element or the `Glossary`.
2. **`Glossary`**. The agent has no right to interpret a term that is not in `Glossary` — it MUST halt and raise `Open-Q`.
3. **`Partition`** (partition metadata).
4. **`Brownfield baseline`** — `Discovery scope` + as-is elements + `coverage_evidence` + `freshness_token`.
5. **`Surfaces`** — `Surface` elements.
6. **`Requirements`** — `Behavior` / `Invariant` / `Scenario` / `NFR`.
7. **`Data contracts`** — `Contract` elements.
8. **`External dependencies`** — `ExternalDependency` elements.
9. **`Generated artifacts`** — `GeneratedArtifact` elements.
10. **`Localization`** — `LocalizationContract` elements.
11. **`Policies`** — `Policy` elements.
12. **`Constraints`** — `Constraint` elements.
13. **`Migrations`** — `Migration` elements.
14. **`Deltas`** — `Delta` elements.
15. **`Implementation bindings`** — `Implementation binding` elements.
16. **`Open questions`** — `Open-Q` elements.
17. **`Assumptions`** — `ASSUMPTION` elements.
18. **`Out of scope`** — global exclusions.

A missing section (even an empty one with explicit `none`) makes the spec invalid.

---

## 3. The "spec vs agent" boundary

### 3.1. The spec MUST fix
- externally observable system behavior;
- boundary contracts (`Surface` + `Contract`);
- domain invariants and forbidden states (`Invariant`);
- external identifiers (API field names, events, CLI, public-DB tables/columns, error codes, message_id) — part of `Surface`/`Contract`/`LocalizationContract`;
- third-party dependencies via `ExternalDependency`, never via a direct `Contract`;
- external constraints as `Constraint` with rationale;
- security, multitenancy, audit, rate-limit as `Policy` with explicit negative test obligations;
- data-at-rest migrations as `Migration`;
- conditional behavior via `applicability` (feature_flag, tenant, locale, env, plan_tier, api_version).

### 3.2. The spec MUST NOT fix
- internal file / module / class / function / variable names (exception — `Implementation binding`, non-normative for compatibility);
- library or framework choice (unless wrapped as a `Constraint` with external rationale);
- directory layout;
- internal layering / service split, when not externally observable;
- effort estimates, schedules, owner assignments.

### 3.3. The agent's domain
Anything not fixed in §3.1 as normative is the agent's call. **The agent MUST list, in the PR, every internal decision it took** that the spec did not fix (names, structure, libraries, internal split). That list becomes candidates for new `REQ`/`Constraint`/`Policy`/`ASSUMPTION` in the next cycle.

---

## 4. Traceability and Test obligations

4.1. **Two-way N:M traceability** ID ↔ test. Before code-gen there are no executable tests, so traceability runs through **`Test obligation`**: every normative ID declares `predicate`, `test_template ∈ {unit, integration, contract, property, e2e, perf}`, `boundary_classes`, `failure_scenarios`. Any `REQ`/`Behavior`/`Scenario`/`NFR`/`Contract`/`Invariant`/`Policy` without a `Test obligation` is invalid.

4.2. After implementation, every `Test obligation` MUST be materialized into ≥1 executable test with a two-way reference `@covers <partition>:<id>,...` or equivalent.

4.3. Coverage is valid at `implementation-valid` only when, for every ID, the following are checked: happy path, boundary cases, declared failure scenarios, and (for boundary `Contract` with `Policy`) negative authz / tenant-isolation / redaction tests.

4.4. **`implementation-valid` is a signal, not a proof.** A test can be green and semantically empty (`assert response is not None`). For a major-bump `Surface`, explicit human review of the test is required: oracle/assertion summary + input classes + negative oracle — this does not replace the linter, it surfaces the semantic gap the linter cannot close.

---

## 5. Ambiguities, open questions, defaults

5.1. **Weasel words are banned** in normative sections (`Requirements`, `Data contracts`, `Constraints`, `Deltas`, `Invariants`, `Migrations`, `Policies`, `External dependencies`, `Localization`). Forbidden: "possibly", "probably", "usually", "as a rule", "etc.", "and so on", "and other", "as needed", "if necessary", "where appropriate", "when applicable", "may", "might", "should usually", "similar to", "like X". Allowed in `Context`, `Glossary`, comments.

5.2. Any detected ambiguity is raised as `Open-Q`. **The agent has no right to silently pick a variant.** With `blocking=yes` the agent halts. With `blocking=no` the agent uses `default_if_unresolved` and materializes it into an `ASSUMPTION` with `review_by` and a trace to tests, flagging in the PR as "decision taken by default, requires confirmation".

5.3. **`ASSUMPTION` is split into `blocking` and `advisory`.** A `blocking` ASSUMPTION fails CI when its target ID is touched. An `advisory` ASSUMPTION past `review_by` produces a warning and an automatic `Open-Q: review_overdue:<ASM-ID>`, but CI block kicks in only when the per-partition overdue-advisory budget is exceeded — otherwise the calendar becomes the main source of false positives in `spec-valid`.

5.4. **Downgrading an ASSUMPTION `blocking → advisory` requires an `approval_record` with `approver_identity ≠ agent_identity`** (the same rule as Surface approval §7.5). Otherwise the expiry of `review_by`, or an explicit downgrade, becomes a self-approval back-door: the code-gen agent unblocks its own ASSUMPTION by simply changing the status, bypassing no-self-approval. Date expiry alone does NOT downgrade `blocking` — only an explicit downgrade with approval from a different identity.

---

## 6. Brownfield: Discovery scope, As-is, Delta, debt budget

6.1. **`Discovery scope`** — a mandatory part of every partition's `Brownfield baseline`. Declares which entrypoints, datasets, flags, tenants, environments, generated artifacts have been surveyed. Every scope item carries `coverage_evidence` (a reference to an artefact: entrypoint registry, code-skeleton dump, IaC inventory, schema registry snapshot, DB introspection).

6.2. Anything **outside** `Discovery scope` is marked `unmodeled`. **`unmodeled` MUST NOT be silently deleted, rewritten, or declared non-existent** — modifying it requires the recon agent to expand `Discovery scope` and an explicit `Open-Q`/`Delta`. This closes the "didn't find = doesn't exist" loophole.

6.3. **`Brownfield baseline` is non-normative on its own.** As-is becomes normative only when an explicit `Behavior`/`Invariant`/`Contract` references it as preserved. As-is does not describe the target state and does not opine on code quality.

6.4. **Every change is authored as a `Delta`** with all required fields. Without a `Delta` the agent has no right to change existing behavior. A code↔spec contradiction without a `Delta` → agent halts + `Open-Q`.

6.5. **`freshness_token`** (hash of recon input sources) is part of the baseline. When it diverges from current source state the baseline becomes `stale`, and `baseline-valid` blocks new `Delta`/`Migration` from reaching `implementation-valid` until the relevant scope is re-checked. Authoring of new `Delta`/`Open-Q` against a pinned `baseline_version` is still allowed (see §0).

6.6. **Iterative debt budget.** Bringing as-is to target in one PR is impossible on a typical brownfield. Each partition has an explicit `unmodeled` / legitimate-debt budget (numeric or percent), which **shrinks per PR/sprint**; the metric is mandatory and tracked. This makes "behavior without an approved ID is removed or lifted" an iterative rule, not an "all in one go" rule.

---

## 7. Per-Surface versioning

7.1. **`Surface` is the unit of semver.** Every `Contract` / `GeneratedArtifact.published_surface=yes` MUST belong to exactly one `Surface`. `Constraint`/`Open-Q`/`ASSUMPTION` have no semver (`not_applicable: no_external_surface`).

7.2. Every normative ID-element (Surface, Contract, Behavior, Invariant, Scenario, NFR, Policy, Migration, GeneratedArtifact, ExternalDependency, LocalizationContract, Constraint) carries a unified `lifecycle.status ∈ {draft, proposed, approved, deprecated, removed}` and `version: N`. Lifecycle is shared across all normative templates, not Surface only.

7.3. Agent rights by status:
- `draft` — experimental generation **only in the sandbox** (`spike/`). Forbidden to touch the `approved` graph.
- `proposed` — spec-valid for review, but **not `implementation-valid` and not mergeable**. This is the legitimate state of a change-set between recon and approval; it removes the livelock of "the change exists, but `draft` is forbidden and `approved` requires human approval".
- `approved` — required to be implemented.
- `deprecated` — requires `sunset_version` (= the version of the `Surface` the ID belongs to) and `replacement_id`.
- `removed` — requires `compatibility_action`. Removing behavior from the spec does **NOT** automatically mean removing the code: the agent acts strictly per `compatibility_action`.

7.3-bis. **Approval ordering by reference graph.** Approval of a normative ID requires every referenced normative ID (Surface→Contract→Policy/ExternalDependency, Migration→Invariant, Behavior→Policy, etc.) to be `≥ approved` in the same PR or earlier. An `approved` Surface with a `proposed` Policy/Contract is forbidden — otherwise `Policy-ref` and other references degrade into dangling pointers and open a new class of gate bypass.

7.4. **The diff between revisions** is a machine-readable list `(id, old_status → new_status, semver_change)`. Per-`Surface` `semver_change` is computed as `max` over the affected IDs of that Surface:
- `major` — contract break; requires `Delta` + breakage tests + human review of the test + (for a published Surface) a compatibility plan.
- `minor` — extension; existing tests stay green.
- `patch` — wording refinement without changing the acceptance predicate.

7.4-bis. **Bump cascading via references.** A bump to a `Policy` or an `Invariant(stability=contractual)` referenced by a `Surface` MUST cascade into the `semver_change` of every referencing Surface:
- any change to Policy/Invariant content ⇒ `≥ minor` on every referencing Surface;
- a change to the **predicate** of a Policy (authz rule, tenant scope, redaction rule, rate-limit threshold) or the **predicate** of an Invariant ⇒ `major` on every referencing Surface.

Without this rule, a breaking change in a centralized Policy would land as `minor` in every consumer, bypassing the human-review requirement for major bumps.

7.5. **`approval_record`** is required for every `approved`/`deprecated`/`removed` ID: `owner_role`, `approver_identity`, `timestamp`, change-request reference, `scope`. **Self-approval by the code-gen agent is forbidden** (a hard rule of `spec-valid`). A major-bump `Surface` requires an owner of the same or higher role. `spec-valid` distinguishes the first-time approval of a new ID from the approval of a diff to an existing approved ID.

---

## 8. External identifiers as contract

8.1. Names of API fields, events, CLI commands, public-DB tables/columns, error codes, HTTP headers, queues, file formats, localization message_ids — are **part of the contract** and live inside `Contract`/`Surface`/`LocalizationContract`.

8.2. Evolution goes through explicit rules: `alias`, `deprecation` (with `sunset_version`), `migration` (with procedure and test).

8.3. Silent renaming of an external identifier is forbidden, regardless of how "safe" it looks.

8.4. For text that became a de-facto contract in legacy code (downstream parsers rely on it), the transition to `code/message_id`-as-contract is authored via `Migration.mode: dual_emit_with_legacy_text` with a fixed window before the old text is removed.

---

## 9. Predicate testability and concurrency

9.1. The predicate of a `Behavior`/`Contract` is expressed via observable inputs/outputs/state. An `Invariant` uses the `evidence` channel (see §1.7).

9.2. **`concurrency_model`** is required for `Behavior`/`Contract`/`Invariant` that cross a concurrency boundary:
- `actor_concurrency ∈ {single, multi_per_resource, multi_global}`;
- `read_consistency ∈ {strong, read_your_writes, monotonic, eventual:<max_lag>}`;
- `idempotency ∈ {none, at_least_once_with_key:<field>, exactly_once_with_key:<field>}`;
- `time_source ∈ {none, monotonic, wall_clock:<max_skew>, external:<service>}`.

Negative `Test obligations` are required for: race window, replay, clock skew, partition. Without an explicit `concurrency_model`, a boundary element is considered ambiguous.

9.3. `Scenario` is an observable trace with explicit `ordering` and `timeout`.

9.4. `NFR` carries `verification_obligation.verification_stage`. `implementation-valid` accepts green only for the matching stage; everything else is `awaiting_evidence:<stage>`. An NFR without `measurement_method` or without an artefact reference is invalid.

---

## 10. Security, policies, multitenancy, localization

10.1. **`Policy`** is a separate first-class template for authorization, tenant isolation, PII redaction, audit, rate-limit. Every boundary `Contract`/`Behavior` MUST reference ≥1 `Policy`. To avoid an avalanche of `Policy: not_applicable+rationale` in brownfield partitions with dozens of legacy endpoints, **every `Partition` declares a `default_policy_set`** (the minimal set of Policy IDs applied by default to every boundary Contract/Behavior of the partition). A specific Contract either inherits `default_policy_set` implicitly, or **explicitly opts out via a `Policy.override` block** that names the rejected Policy ID and a rationale; a bare `not_applicable` without an override block is invalid. This turns mass absence of Policy from a silent ritual into an active decision the linter sees and counts.

10.2. Negative `Test obligations` are required for every `Policy`: unauthorized actor, cross-tenant access, forbidden data exposure, rate-limit violation.

10.3. **`LocalizationContract`** is a separate first-class template. Boundary errors reference a stable `code/message_id`, never localized text. `text_is_contract: yes` lifts the text to contract level (with all alias/deprecation/migration rules); the default is `no`.

10.4. **Conditional behavior via `applicability`** (feature_flag, tenant, locale, env, plan_tier, api_version). A missing axis = "invariant across all values" requires an explicit `Open-Q` the first time a variable on that axis is detected in the code.

---

## 11. Third-party APIs, migrations, generated code

11.1. **`ExternalDependency`** is a separate template for third-party providers. Recording provider-owned behavior as a regular `Contract` without provenance is forbidden — otherwise the agent freezes incidentally observed Stripe/S3/CRM behavior as if it were ours. `consumer_contract` is always pinned to `provider_surface@version`.

11.2. **`drift_detection.mechanism`** is a closed set: `contract_test_against_sandbox`, `openapi_diff`, `schema_registry_subscription`, `changelog_watcher`, `none_with_review_by:<date>`. A free-text label like "watcher will be set up" is invalid.

11.3. **`Migration`** is a separate first-class template for data at-rest and switchover procedures. Without `Migration`, an `Invariant`/`Contract` is ambiguous with respect to legacy data: a mandatory `data_scope ∈ {new_writes_only, all_data, post_migration:<MIG-ID>}` is required.

11.3-bis. **Migration spec-lifecycle vs runtime-state — two separate axes**, and conflating them breaks the gate.
- **Spec-lifecycle** (governance, see §7.2): `lifecycle.status ∈ {draft, proposed, approved, deprecated, removed}` — describes whether the migration is agreed upon as a normative document.
- **Runtime-state** (operational evidence): `runtime_state ∈ {pre_cutover, in_progress, cutover_done, rolled_back}` — describes **where the migration's execution currently is** in the repo.

An `approved` Migration in `pre_cutover` runtime-state is normal; treating it as "executed" merely because it is approved would be a false-green `implementation-valid`.

11.3-ter. **`enforcement_stage` for normative IDs tied to a Migration.** Every `Invariant`/`Contract`/`Behavior` with `data_scope=post_migration:<MIG-ID>` MUST carry `enforcement_stage` that points to a **deterministic test-controllable marker in the repo** (`feature_flag`, `migration completion sentinel`, `cutover_marker:<MIG-ID>` — but NOT a live deployment state, NOT a production signal, NOT a runtime feature-flag service). CI runs pre/during/post-cutover test sets by toggling that marker, **never by reading the environment** — otherwise the gate starts depending on deployment state and loses reproducibility.

11.3-quater. **`implementation-valid` checks only the tests applicable to the current Migration runtime-state**:
- `runtime_state = pre_cutover` → `tests_pre` green; `tests_post` may be `awaiting_marker:<MIG-ID>:cutover_done` and do not block merge;
- `runtime_state = in_progress` → `tests_pre` + `tests_during` green (for `dual_write`/`backfill`/`dual_emit_with_legacy_text`);
- `runtime_state = cutover_done` → `tests_post` green; dependent `Invariant`s with `enforcement_stage=post_migration:<MIG-ID>` MUST be green;
- `runtime_state = rolled_back` → `tests_pre` green; `Invariant`s with `data_scope=post_migration:<MIG-ID>` move to `awaiting_marker` or `deprecated`.

This closes the `Migration → Invariant → implementation-valid` cycle: the invariant becomes mandatory only after cutover, evidenced by a deterministic marker, not before.

11.4. **`GeneratedArtifact`** — normative IDs are allowed only on the source schema/contract. `regeneration_mode ∈ {clean, with_whitelisted_patches:<PATCH-ID...>}` — every patch gets its own normative ID and `Test obligation`. `published_surface: yes` makes the generated output its own `Surface` with independent semver.

11.4-bis. **Derived semver for `GeneratedArtifact(published_surface=yes)`.** The `semver_change` of the generated artifact's own Surface is computed as:
```
semver_change(generated_surface) = max(
    semver_change(upstream_source),
    structural_diff_class(generated_emission)
)
```
where `structural_diff_class` evaluates a change in **the emission itself** (field order in serialization, renaming of generated identifiers, wire-format change, removal/renaming of generated methods). **A structural-breaking diff is mandatorily `major`, regardless of the upstream bump** — a minor in the source plus a breaking diff in the emission (field order, names in serialization) yields a `major` on the generated Surface, otherwise the SDK breaks downstream consumers under the cover of a minor.

---

## 12. Storage format and linter

12.1. The spec is stored in a format amenable to **static checking**: structured markdown with YAML frontmatter on ID-elements, or standalone YAML/JSON, or markdown with fixed headers and fields. Every field of every template declares its field type from §1.5.

12.2. **The spec linter runs in CI as a blocking step.** The linter implements:
- the section structure of §2 per partition;
- the `Template Requiredness Matrix` §14 — presence of required and conditional (by trigger) fields;
- field types §1.5;
- the weasel-word ban §5.1 in normative sections;
- two-way ID ↔ `Test obligation` traceability;
- per-`Surface` semver markup of the diff §7.4;
- `approval_record` presence and the self-approval ban §7.5;
- `baseline-valid` per partition §0.

12.3. Anything the linter cannot check stays a wish, not a rule, and has no normative force.

---

## 13. Partitioning

13.1. **`Partition`** is a first-class object. Fields: `partition_id` (neutral), `owner_team`, `gate_scope`, `dependencies_on_other_partitions[]`, `default_policy_set[]` (the minimal set of Policy IDs applied by default to every boundary Contract/Behavior of the partition — see §10.1).

13.2. Cross-partition references go only through `Surface@version` or `Policy@version`. Direct references to another partition's internal IDs are forbidden.

13.3. ID allocation is local to the partition (`<partition_id>:<neutral_id>`); this fulfils §1.3 without a central allocator and removes merge conflicts on ID allocation.

13.4. `gate_scope` defines exactly what each gate (`baseline-valid`/`spec-valid`/`implementation-valid`) checks for this partition and its declared dependencies, not for the whole repository.

13.5. A cross-partition `Migration` is authored via `Migration.partition_slice[]` (each slice belongs to a single partition and carries a local `approval_record` from that partition's owner team) plus a single `coordinator_id`. Joint approval as a monolith is forbidden — it does not fit into the iterative debt budget §6 and would block the migration indefinitely.

---

## 14. Template Requiredness Matrix

`R` = required (always); `C` = conditional (R when triggered); `O` = optional. For conditional fields a default is allowed, but when the trigger fires an explicit value is required.

| Template | Field | Card. | Conditional trigger / default |
|---|---|---|---|
| `Behavior` | `applicability` | R | default `invariant_to_all_axes`; explicit value R when an axis variable is detectable in scope |
| `Behavior` | `concurrency_model` | C | R if Behavior crosses a Surface boundary or `actor_concurrency=multi` is detected in baseline |
| `Behavior` | `data_scope` | C | R if Behavior interacts with persistent state or there is an active Migration on the affected data |
| `Behavior` | `Policy`-ref | C | R on a boundary; otherwise `Policy: not_applicable` with rationale |
| `Contract` | `Surface`-ref | R | always |
| `Contract` | `applicability` | R | default allowed |
| `Contract` | `error_taxonomy` | C | R if `Surface.boundary_type ∈ {api, sdk, event_bus, cli, public_db, public_storage}` |
| `Contract` | `concurrency_model` | C | R if Surface is concurrent; default `single_actor_per_resource` for sync request/response |
| `Contract` | `data_scope` | C | R if Contract reads/writes persisted data |
| `Invariant` | `evidence` + `stability` | R | always |
| `Invariant` | `data_scope` | R | default `all_data`; explicit value R when there is a Migration or data-shape evolution |
| `Invariant` | `applicability` | R | default allowed |
| `Invariant` | `concurrency_model` | C | R if invariant references shared mutable state or contains a temporal/ordering predicate |
| `Scenario` | all template fields | R | always |
| `NFR` | `target` | R | always |
| `NFR` | `verification_obligation.stage` + artefact ref | R | always |
| `Migration` | all template fields (`target_ids`, `direction`, `mode`, `data_window`, `success_criteria`, `rollback_plan`, `tests_pre`, `tests_during`, `tests_post`, `data_scope`, `runtime_state`, `enforcement_stage`) | R | always (the template is created only for migrations) |
| `Migration` | `partition_slice[]`, `coordinator_id` | C | R if migration crosses >1 partition; joint approval as a monolith is forbidden |
| `Delta` | `baseline_version` | R | always (Delta is pinned to a specific baseline revision) |
| Normative ID tied to a Migration | `enforcement_stage` (points to a deterministic test-controllable marker in the repo) | C | R when `data_scope=post_migration:<MIG-ID>` |
| `Partition` | `default_policy_set[]` | R | always (even if empty — explicitly `[]`) |
| `Contract`/`Behavior` boundary | `Policy.override` block when opting out of `default_policy_set` | C | R on opt-out; bare `not_applicable` without an override block is invalid |
| `Policy` | all template fields | R | always |
| `Constraint` | `constraint`, `rationale` | R | always |
| `GeneratedArtifact` | `source_ids`, `regeneration_mode`, `published_surface` | R | always |
| `GeneratedArtifact` | `Surface`-ref | C | R if `published_surface=yes` |
| `ExternalDependency` | `provider`, `provider_surface@version`, `drift_detection.mechanism`, `last_verified_at`, `consumer_contract` | R | always |
| `ExternalDependency` | `auth_scope` | C | R if integration requires auth |
| `ExternalDependency` | `rate_limits` | C | R if provider publishes or enforces rate limits |
| `ExternalDependency` | `retry/idempotency` | C | R if interaction is not read-only-fetch |
| `ExternalDependency` | `error_taxonomy` | C | R if provider errors are observable on our boundary |
| `ExternalDependency` | `sandbox_or_fixture` | C | R if `drift_detection.mechanism = contract_test_against_sandbox` |
| `LocalizationContract` | `message_id`, `icu_args_schema`, `locale_coverage`, `fallback_chain`, `text_is_contract` | R | always inside the template |
| `LocalizationContract` | `timezone/currency/source` | C | R if behavior depends on time/currency formatting |
| `LocalizationContract` | `collation_rule` | C | R if behavior contains string sorting/comparison |
| `LocalizationContract` | `rtl_layout` | C | R if `locale_coverage` includes RTL locales |
| `Surface` | `name`, `version`, `boundary_type`, `members[]`, `consumer_compat_policy` | R | always |
| `Partition` | `partition_id`, `owner_team`, `gate_scope`, `dependencies_on_other_partitions` | R | always |
| `Implementation binding` | `target_ids`, `authority`, `verification_method` | R | always (the template is created only when binding is needed) |
| ID-level | `partition_id` namespace + neutral local ID | R | always |
| ID-level (normative templates) | `lifecycle.status ∈ {draft, proposed, approved, deprecated, removed}` | R | always; unified lifecycle for Surface/Contract/Behavior/Invariant/Scenario/NFR/Policy/Migration/GeneratedArtifact/ExternalDependency/LocalizationContract/Constraint |
| ID-level | `approval_record` (owner_role, approver_identity, timestamp, change_request, scope) | C | R for `approved`/`deprecated`/`removed`; forbidden for `draft`/`proposed`; self-approval ban is a hard rule of `spec-valid`; Surface approval requires `≥approved` for every referenced normative ID |
| `ASSUMPTION` downgrade `blocking → advisory` | `approval_record` with `approver_identity ≠ agent_identity` | R | always on downgrade; expiry of `review_by` alone does NOT downgrade `blocking` |
| `Open-Q` | `question`, `options[]` (≥2), `blocking`, `owner` | R | always |
| `Open-Q` | `default_if_unresolved` | C | R when `blocking=no` |
| `ASSUMPTION` | `assumption`, `blocking ∈ {yes, no}`, `review_by`, `default_if_unresolved`, `tests`, `partition_id` | R | always |
| `ASSUMPTION` | `source_open_q` | O | when the assumption flows from an explicit Open-Q |
| Discovery / baseline | `Discovery scope`, `coverage_evidence`, `freshness_token` | R | per partition |

**Process rules (not template fields):**
- Iterative debt budget for as-is → target — R.
- `baseline-valid` as the third gate, partition-scoped — R.
- `ASSUMPTION advisory` with overdue budget per partition — R.
- Human review of the test on a major-bump `Surface` — R.
- Per-ID mutation-testing kill rate — O.
- Field types §1.5 — R, every template declares the type of each of its fields.

---

## 15. Agent behavior on existing code

15.1. **Recon first** (read-only recon agent). Builds `Discovery scope` + `Brownfield baseline` without interpretation and without opinion on code quality. This is a separate artefact. `coverage_evidence` is mandatory. No `Delta`/`Migration` until `baseline-valid`.

15.2. **Then target.** The agent authors `Requirements`/`Data contracts`/`Policies`/`Constraints`/`Deltas`/`Migrations` against the `Brownfield baseline`. Every as-is fact the agent decides to preserve becomes a normative element. Every difference from as-is is authored as a `Delta`. Every data-at-rest migration is a `Migration`.

15.3. **No silent decisions.** The agent MUST halt and raise `Open-Q` on any of:
- a term not in `Glossary`;
- behavior outside `Discovery scope` (`unmodeled`);
- a code↔spec contradiction without a `Delta`;
- a weasel word in a normative section;
- removal without a `compatibility_action`;
- missing `Policy`-ref on a boundary;
- missing `applicability` when an axis variable is detectable;
- missing `concurrency_model` on a boundary;
- missing `data_scope` on persistent state;
- provider-owned behavior without an `ExternalDependency`;
- generated output without a `GeneratedArtifact`;
- text-as-contract without a `LocalizationContract`;
- missing `baseline_version` on a `Delta`/`Migration`;
- a `proposed → approved` Surface transition while a referenced Policy/Contract is not yet approved;
- a Migration `runtime_state` change without updating dependent `Invariant.enforcement_stage`;
- a structural-breaking diff in a `GeneratedArtifact(published_surface=yes)` without a major bump on its own Surface.

15.4. **PR report.** When generating or editing code, the agent's PR explicitly lists:
- which `Test obligation`s were closed and by which tests (with oracle/assertion summary, input classes, negative oracle for major-bump);
- internal decisions taken (names, structure, libraries);
- `ASSUMPTION`s used and their `review_by`;
- remaining `Open-Q`s and why they do not block this specific PR;
- reduction of the `unmodeled` / legitimate-debt budget vs the previous PR (when applicable).

15.5. **No code without an `approved` ID** in the long run. Behavior not covered by an `approved` element is either removed from code or lifted into the spec as `REQ`/`Contract` with resolution. This rule applies **iteratively via the debt budget §6.6**, not "all in one PR" — otherwise brownfield is paralyzed.

15.6. **Self-approval is forbidden** in all its forms. The code-gen agent has no right to set `approval_record` on IDs it created or modified itself, **and no right to downgrade `ASSUMPTION` `blocking → advisory`** (§5.4) without a different approver_identity. Approval is a separate role (a human owner or another autonomous approver-agent with a different identity).

---

## 16. v3 recommendation (not a blocker)

In v2.1 the temporal axes are scattered across multiple sections and interact in subtle ways:

- baseline livelock and `freshness_token` (§0/§6) — snapshot versioning;
- spec-lifecycle `{draft, proposed, approved, deprecated, removed}` (§7.2) — governance;
- Migration runtime-state `{pre_cutover, in_progress, cutover_done, rolled_back}` (§11.3-bis) — operational evidence;
- `enforcement_stage` of normative IDs (§11.3-ter) — when an invariant becomes mandatory;
- `ASSUMPTION.review_by` (§5) — calendar deadline;
- semver chaining via references (§7.4-bis) — derived versioning.

Every cycle the second review caught walks through this layer. **In v3 the recommendation is to consolidate the temporal layer into a dedicated section `§LX "Lifecycle & temporal evidence"` with an explicit ER graph**: which axis blocks which other, which inter-axis relations are admissible, which transitions are atomic. Without this consolidation, every next patch risks opening a new temporal cycle. This is a recommendation, not a blocker, for handing v2.1 off to the agent.
