# coding-agent-config

Portable coding-agent setup for Claude Code and Codex CLI / IDE on macOS.

Single source of truth for universal coding rules, hooks, and the optional
Spec-Driven Development bundle. One script symlinks them into the per-user
config locations of each agent and registers hooks in
`~/.claude/settings.json`.

This repo is intentionally project-, vendor-, and VCS-agnostic. Project- or
vendor-specific extensions live in their own repos that embed this one as a
git submodule and reuse `scripts/lib/install-lib.sh` (see
[Downstream extensions](#downstream-extensions)).

## Layout

```
.
├── CLAUDE.md           # entry point for Claude Code (uses @rules/* imports)
├── rules/              # universal code-quality and process rules
├── sdd/                # Spec-Driven Development bundle. Optional, --sdd only.
│   ├── *.md            #   methodology, enforcement registry, sdd-cli usage
│   ├── hooks/          #   sdd-lint reminder
│   └── skills/         #   spec-driven-development skill
├── hooks/              # hooks installed unconditionally
├── skills/             # SKILL.md bundles, symlinked per-skill into both agents
├── build/              # generated, gitignored
│   └── AGENTS.md       #   flat file for Codex (built from CLAUDE.md + imports)
└── scripts/
    ├── build.sh        # rebuild build/AGENTS.md
    ├── install.sh      # symlink into Claude/Codex config locations
    └── lib/
        └── install-lib.sh  # reusable shell helpers (public extension surface)
```

### What's where, and why

- **`rules/`** — universal coding rules (naming, architecture, testing,
  commits, errors, review, code-navigation, workflow, simplicity).
  Apply on every machine.
- **`sdd/`** — Spec-Driven Development bundle: `spec-driven-development.md`
  (methodology), `enforcement_registry.md` (mapping requirements ↔ `sdd-cli`
  channels), `sdd-cli-usage.md` (phase-to-command mapping), plus
  `workflow-sdd.md` and `review-sdd.md` addenda extending the universal
  rules. Installed only with `--sdd`. Top-level `*.md` are inlined into
  CLAUDE.md / AGENTS.md; the `sdd/hooks/sdd-lint-reminder.sh` hook and the
  `sdd/skills/spec-driven-development/` skill are wired in alongside.
- **`hooks/`** — hook scripts installed unconditionally
  (currently `lsp-reminder.sh`).
- **`sdd/hooks/`** — hook scripts installed only with `--sdd`
  (currently `sdd-lint-reminder.sh`).
- **`skills/`** — SKILL.md bundles (open standard, supported by both Claude Code
  and Codex CLI / IDE). Each subdir is one skill and gets symlinked
  **per-skill** into `~/.claude/skills/<name>` and
  `~/.agents/skills/<name>`, so the user's own hand-rolled skills in those
  directories are left untouched. Currently empty — drop new non-SDD
  skills here. The SDD skill lives under `sdd/skills/` and is gated by
  `--sdd`.
- **`scripts/lib/install-lib.sh`** — shell library exposing the symlink,
  hook-registration, and import-inlining primitives. Sourced by this repo's
  drivers and intended to be reused by downstream extension repos.

`CLAUDE.md` is intentionally tiny — a table of contents that Claude Code
expands at session start via `@rules/X.md` imports. Codex does not
understand `@import`, so `scripts/build.sh` produces a flattened
`build/AGENTS.md` with all referenced files inlined.

## First-time install on a new machine

```bash
git clone <this-repo> ~/Projects/coding-agent-config
cd ~/Projects/coding-agent-config
./scripts/install.sh all                # universal rules + hooks
./scripts/install.sh all --sdd          # + Spec-Driven Development bundle
```

### Flags

| Flag | Effect |
|---|---|
| *(none)* | universal rules + `hooks/`. Agent uses built-in git knowledge. |
| `--sdd` | + all `sdd/*.md` + `sdd/hooks/sdd-lint-reminder.sh` + `sdd/skills/spec-driven-development/`. Without the flag, any previously installed SDD artefact owned by this repo is removed. |

### Targets

| Agent       | Target path                                 | Source                                |
|-------------|---------------------------------------------|---------------------------------------|
| Claude Code | `~/.claude/CLAUDE.md` (generated file)      | `CLAUDE.md` + optional SDD section    |
| Claude Code | `~/.claude/rules` (symlink)                 | `rules/`                              |
| Claude Code | `~/.claude/hooks` (symlink)                 | `hooks/`                              |
| Claude Code | `~/.claude/sdd` (symlink, with `--sdd`)     | `sdd/`                                |
| Claude Code | `~/.claude/settings.json` (mutated)         | hook entries idempotently upserted    |
| Claude Code | `~/.claude/skills/<name>` (symlink per skill) | `skills/<name>/` and (with `--sdd`) `sdd/skills/<name>/` |
| Codex CLI / IDE | `${CODEX_HOME:-~/.codex}/AGENTS.md` (symlink) | `build/AGENTS.md`                |
| Codex CLI / IDE | `~/.agents/skills/<name>` (symlink per skill) | `skills/<name>/` and (with `--sdd`) `sdd/skills/<name>/` |

If anything already exists at a target path it is renamed to
`<target>.bak.<unix-timestamp>` before the symlink/file is created.

`~/.claude/CLAUDE.md` and `~/.claude/settings.json` are **regenerated on
every run** (so flag changes take effect). All other targets are
symlinks — re-running with the same flags is a no-op (`= already linked`).

If an older install created repo-owned skill symlinks under
`~/.codex/skills/<name>`, `install.sh codex` removes those legacy symlinks
after installing the replacement under `~/.agents/skills/<name>`. It only
removes same-name symlinks for skills managed by this repo; unrelated files
and directories are left untouched. If `~/.codex/skills` becomes empty, the
legacy directory is removed too.

### Hooks

Registered in `~/.claude/settings.json` idempotently — entries are matched
by script basename, stale paths are removed, the canonical path is
upserted. The script will not delete unrelated hook entries (e.g.
the `UserPromptSubmit` `PROJECT_MAP` reminder).

| Hook | Event | Matcher | Installed when |
|---|---|---|---|
| `lsp-reminder.sh` | `PreToolUse` | `Grep\|Read` | always |
| `sdd-lint-reminder.sh` | `PreToolUse` | `Edit\|Write\|MultiEdit` | `--sdd` (and removed when re-run without `--sdd`) |

### MCP servers

The install also registers MCP servers referenced by the rules into
`~/.claude.json` (`mcpServers.<name>`) and `~/.codex/config.toml`
(`[mcp_servers.<name>]`). Both files are backed up to `<path>.bak.<TS>`
on first mutation per run.

| MCP | npm package | Installed when | Env vars |
|---|---|---|---|
| `code-skeleton` | `code-skeleton-mcp` (public npm) | always | — |

The script runs `npm install -g <pkg>` once per package (idempotent — skips
if the bin is already on PATH). Other MCP entries you have in
`~/.claude.json` / `~/.codex/config.toml` are left untouched; only the names
listed above are upserted.

If `npm install -g` fails (no network, missing registry auth, etc.), the
MCP is skipped with a warning rather than aborting the whole install.

## Editing rules

Edit files under `rules/`, `sdd/`, or `hooks/` directly. Claude Code picks up
`*.md` changes on the next session — no rebuild needed (the symlinks resolve
to live files in this repo).

For Codex, regenerate the flat file after any `*.md` edit:

```bash
./scripts/install.sh codex --sdd     # match the flags you installed with
# or, equivalently:
./scripts/build.sh --sdd
```

If you change which top-level `sdd/*.md` files exist (add or remove one),
re-run `./scripts/install.sh claude --sdd` so `~/.claude/CLAUDE.md` is
regenerated with the new `@`-import list.

## Per-agent install

```bash
./scripts/install.sh claude [--sdd]   # only Claude Code
./scripts/install.sh codex  [--sdd]   # only Codex (also runs build)
./scripts/install.sh all    [--sdd]   # both
```

## Adding a new SDD doc

Drop `sdd/<topic>.md` into the repo. It is auto-discovered (alphabetical)
and inlined when `--sdd` is set.

## Adding a new skill

Drop `skills/<name>/SKILL.md` (plus any supporting files) into the repo, then
re-run `./scripts/install.sh all`. Per-skill symlinks land in
`~/.claude/skills/<name>` and `~/.agents/skills/<name>`. Skills are
auto-discovered from `skills/*/` — no flag, no list to maintain.

User-owned skills with different names (e.g. `~/.claude/skills/my-thing/`)
are untouched. A same-name collision is backed up to
`<target>.bak.<unix-timestamp>` like every other install target.

## Adding a new hook

- Universal hook: drop `hooks/<name>.sh`, then add an `install_hook`
  call in `install_claude` in `scripts/install.sh`.
- SDD-only hook: drop `sdd/hooks/<name>.sh`, add an `install_hook` call
  inside the `if [[ "$SDD" -eq 1 ]]` block, and a paired `remove_hook`
  call in the `else` branch so the hook is dropped from settings.json
  when the user re-runs without `--sdd`.

Hook registration is idempotent — re-running install will replace any
prior entry that points at a script with the same basename.

## Downstream extensions

`scripts/lib/install-lib.sh` is the public extension surface. A downstream
repo that wants to layer its own rules, hooks, MCPs, or skills on top of
this install should:

1. Embed this repo as a git submodule.
2. `source <submodule>/scripts/lib/install-lib.sh` from its own
   `scripts/install.sh`.
3. Call `link`, `install_hook`, `install_skills`, `register_mcp_claude`,
   `register_mcp_codex`, etc. with paths inside the extension repo, and
   append its own `## <Section>` blocks to `~/.claude/CLAUDE.md` after the
   core driver has written it.

The lib is the only stable contract. Helpers are documented in the file
header and remain backwards-compatible across patch releases.

## Out of scope

- `~/.claude/agents/`, `~/.claude/commands/`,
  `~/.claude/projects/*/memory/` — not managed by this repo.
- Skills you authored yourself in `~/.claude/skills/` or `~/.agents/skills/` —
  install.sh only touches subdirs that match a name in this repo's `skills/`.
- `~/.codex/config.toml` — not managed.
- Permissions in `~/.claude/settings.json` (`allow`/`deny`/`ask`) —
  install.sh only mutates the `hooks` block; everything else is left
  intact.
