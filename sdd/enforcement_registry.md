# SDD Enforcement Registry

Single source of truth for «which SDD requirement is closed by which channel». Every MUST and every stop-condition from `spec-driven-development.md` and `SKILL.md` has exactly one row here. Adding a normative requirement without a row is invalid; adding a CLI diagnostic without a row is invalid.

## Compatibility metadata

| Field | Value |
|---|---|
| sdd_methodology_version | 1.0.0 |
| compatible_sdd_cli | >=1.0 <2.0 |
| diagnostic_surface | @cyberash/sdd-cli/diagnostics@1.0 |

## Schema

Each row carries:
- `id` — `ENF-NNN[A-Z]?` (suffix letter when split via `parent_id`).
- `parent_id` — optional; links rows that decompose one requirement.
- `requirement` — short imperative statement (one sentence).
- `enforcement_class` — one of 10 semantic classes (see below).
- `executor` — one of `sdd lint | sdd check | sdd refresh | sdd ready | sdd finalize | sdd report | sdd doctor | agent | human`.
- `gate` — `baseline-valid | spec-valid | implementation-valid` (omitted for process-class rows).
- `diagnostic_id` — required for mechanical with `maturity=implemented`. Contains the exact string the CLI emits (`sdd:*` for lint, snake-case for ready violation kinds).
- `maturity` — `implemented | planned | out_of_scope` (omitted for process-class rows). Suffix `:hybrid` when the row mixes mechanical and human verdicts.
- `process_owner` — required when `executor ∈ {agent, human}`.
- `review_trigger` — required when `executor ∈ {agent, human}`; one of `PR merge | sprint close | release cut`.

### Enforcement classes

- `structural-lint` — single-record textual/typed check.
- `graph-consistency` — cross-record reference validation.
- `freshness` — comparison against recorded baseline.
- `aggregate-gate` — composite check across multiple sub-rules.
- `derived-versioning` — semver/diff classification computed from references.
- `derived-artifact` — structural diff over emitted artefact.
- `report-evidence` — produces machine-readable narrative for PR.
- `agent-halt` — agent reflex on closed stop-condition (term not in Glossary → Open-Q).
- `agent-judgment` — agent semantic classification (provider-owned → ExternalDependency).
- `human-review` — human-only gate (test oracle quality, debt content).

## Registry

| id | parent_id | requirement | enforcement_class | executor | gate | diagnostic_id | maturity | process_owner | review_trigger |
|----|-----------|-------------|-------------------|----------|------|---------------|----------|---------------|----------------|
| ENF-001 | — | Weasel words banned in normative sections; modal phrases in `is_normative=true` fields | structural-lint | sdd lint | spec-valid | sdd:weasel-word | implemented | — | — |
| ENF-002 | — | Surface refs ≥ approved before `lifecycle.status=approved` is materialised | graph-consistency | sdd finalize | spec-valid | surface_unapproved_ref | implemented | — | — |
| ENF-003 | — | Delta/Migration carries `baseline_version` | structural-lint | sdd lint | spec-valid | sdd:baseline-version-required | implemented | — | — |
| ENF-004A | ENF-004 | Major Surface bump computed via semver cascade (Policy / Invariant(contractual) → referencing Surface) | derived-versioning | sdd ready | spec-valid | surface_semver_cascade | implemented | — | — |
| ENF-004B | ENF-004 | Major-bump test oracle reviewed (input classes, negative oracle, assertion summary) | human-review | human | — | — | — | surface owner | PR merge |
| ENF-005 | — | Unknown Glossary term → agent raises Open-Q | agent-halt | agent | — | — | — | PR author | PR merge |
| ENF-006 | — | Provider-owned behavior → agent classifies as ExternalDependency | agent-judgment | agent | — | — | — | PR author | PR merge |
| ENF-007A | ENF-007 | PR report lists closed Test obligations + tests | report-evidence | sdd report | implementation-valid | sdd:report-test-obligations | implemented | PR author | PR merge |
| ENF-007B | ENF-007 | PR report lists internal decisions (candidates for new Constraint/Policy/ASSUMPTION) | report-evidence | sdd report | implementation-valid | sdd:report-internal-decisions | implemented | PR author | PR merge |
| ENF-007C | ENF-007 | PR report lists ASSUMPTIONs + `review_by` | report-evidence | sdd report | implementation-valid | sdd:report-assumptions | implemented | PR author | PR merge |
| ENF-007D | ENF-007 | PR report lists remaining Open-Qs + non-block reason | report-evidence | sdd report | implementation-valid | sdd:report-open-qs | implemented | PR author | PR merge |
| ENF-007E | ENF-007 | PR report shows debt budget delta vs previous PR | report-evidence | sdd report | implementation-valid | sdd:report-debt-delta | implemented:hybrid | PR author | PR merge |
| ENF-008 | — | Diagnostic rule IDs are stable public Surface (drift kinds: `version_mismatch`, `missing_diagnostic`, `stale_diagnostic`) | graph-consistency | sdd doctor | — | version_mismatch \| missing_diagnostic \| stale_diagnostic | implemented | — | release cut |
| ENF-009 | — | `deprecated` ⇒ `sunset_version` + `replacement_id` | structural-lint | sdd lint | spec-valid | sdd:deprecated-fields-required | implemented | — | — |
| ENF-010 | — | ASSUMPTION downgrade `blocking → advisory` requires `approval_record` (≠ agent identity) | structural-lint | sdd lint | spec-valid | sdd:assumption-downgrade-approval | implemented | — | — |
| ENF-011 | — | Partition declares `default_policy_set[]` (≥0, explicit) | structural-lint | sdd lint | spec-valid | sdd:partition-default-policy-set | implemented | — | — |
| ENF-012 | — | `GeneratedArtifact.published_surface=yes` ⇒ Surface-ref | structural-lint | sdd lint | spec-valid | sdd:generated-artifact-surface-ref | implemented | — | — |
| ENF-013 | — | Boundary Contract/Behavior references ≥1 Policy or carries explicit `Policy.override` | structural-lint | sdd lint | spec-valid | sdd:boundary-policy-ref | implemented | — | — |
| ENF-014 | — | `concurrency_model` present on boundary elements with required sub-fields | structural-lint | sdd lint | spec-valid | sdd:boundary-concurrency-model | implemented | — | — |
| ENF-015 | — | `applicability` present (or `invariant_to_all_axes: true`) | structural-lint | sdd lint | spec-valid | sdd:applicability-required | implemented | — | — |
| ENF-016 | — | `data_scope` present on persistent-state elements | structural-lint | sdd lint | spec-valid | sdd:data-scope-required | implemented | — | — |
| ENF-017 | — | Migration `runtime_state` ↔ `enforcement_stage` marker consistency | structural-lint | sdd lint | spec-valid | sdd:migration-enforcement-stage | implemented | — | — |
| ENF-018 | — | Cross-partition Migration uses `partition_slice[]` + `coordinator_id` | structural-lint | sdd lint | spec-valid | sdd:migration-cross-partition | implemented | — | — |
| ENF-019 | — | `GeneratedArtifact(published_surface=yes)` structural-breaking diff ⇒ major bump | derived-artifact | sdd ready | spec-valid | generated_artifact_structural_diff_unbumped | implemented | — | — |
| ENF-020 | — | Iterative debt budget per Partition (form + monotonic non-increase) | aggregate-gate | sdd ready | implementation-valid | debt_budget_increased | implemented:hybrid | partition owner | sprint close |
| ENF-021 | — | Brownfield baseline `freshness_token` matches source tree | freshness | sdd check | baseline-valid | — | implemented | — | — |
| ENF-022 | — | weasel-words list has single canonical source (drift detected by `sdd doctor`) | graph-consistency | sdd doctor | — | sdd:weasel-source-drift | planned | — | release cut |
| ENF-023 | — | Code↔spec contradiction outside Delta → agent halts | agent-halt | agent | — | — | — | PR author | PR merge |
| ENF-024 | — | Text-as-contract → agent classifies as LocalizationContract | agent-judgment | agent | — | — | — | PR author | PR merge |
| ENF-025 | — | Generated output → agent classifies as GeneratedArtifact | agent-judgment | agent | — | — | — | PR author | PR merge |
| ENF-026 | — | Removal without `compatibility_action` → agent halts | agent-halt | agent | — | — | — | PR author | PR merge |
| ENF-027 | — | Missing `Policy`-ref on a boundary detected by agent → halt | agent-halt | agent | — | — | — | PR author | PR merge |
| ENF-028 | — | Missing `applicability` when an axis variable is detectable in baseline → halt | agent-halt | agent | — | — | — | PR author | PR merge |
| ENF-029 | — | Missing `concurrency_model` on a boundary → halt | agent-halt | agent | — | — | — | PR author | PR merge |
| ENF-030 | — | Missing `data_scope` on persistent state → halt | agent-halt | agent | — | — | — | PR author | PR merge |
| ENF-031 | — | Missing `baseline_version` on Delta/Migration → halt before relying on lint | agent-halt | agent | — | — | — | PR author | PR merge |
| ENF-032 | — | `proposed → approved` Surface while referenced Policy/Contract not yet approved → halt before invoking finalize | agent-halt | agent | — | — | — | PR author | PR merge |
| ENF-033 | — | Migration `runtime_state` change without updating dependent `enforcement_stage` → halt | agent-halt | agent | — | — | — | PR author | PR merge |
| ENF-034 | — | Structural-breaking diff in `GeneratedArtifact(published_surface=yes)` without major bump → halt before commit | agent-halt | agent | — | — | — | PR author | PR merge |

## Maturity transitions

- `planned` → `implemented`: requires CHANGELOG entry in `sdd-cli` with PR number and integration test; `compatible_sdd_cli` range in this registry must cover the implementing CLI version.
- `implemented` → `deprecated`: alias period ≥1 minor on `Surface: diagnostics` (SUR-009 in `sdd-cli/spec/spec.md`); the alias is recorded in CLI's `DiagnosticRegistry.ts`.
- `out_of_scope` → ничего: фиксирует, что это не будет автоматизировано в данной major-line.

Many `agent-halt` rows duplicate mechanical lint coverage (e.g. ENF-027 vs ENF-013, ENF-031 vs ENF-003). The duplication is intentional — `sdd lint` catches the violation at gate-2 (`spec-valid`), but the agent must still raise it as `Open-Q` proactively rather than relying on the linter to find it. `enforcement_class: agent-halt` is the *behavior expected from the agent*; `structural-lint` is the *mechanical safety net*.

## How to add a new requirement

1. Сформулировать как одно предложение MUST.
2. Выбрать `enforcement_class` (одно из 10) и `executor`.
3. Если class mechanical и `maturity=implemented` — обязателен `diagnostic_id`. Если `executor ∈ {agent, human}` — обязательны `process_owner` и `review_trigger`.
4. Добавить строку в Registry. Если требование декомпозируется (mechanical part + human-review part) — две строки с общим `parent_id`.
5. В `rules/spec-driven-development.md` и/или `SKILL.md` сформулировать сам MUST и сослаться на ENF-id.
