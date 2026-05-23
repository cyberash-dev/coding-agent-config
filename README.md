# coding-agent-config

Portable coding-agent setup for Claude Code and Codex CLI / IDE on macOS.

Single source of truth for universal coding rules and hooks. One script
symlinks them into the per-user config locations of each agent and registers
hooks in `~/.claude/settings.json`. The optional `--sdd` flag delegates
Spec-Driven Development setup to [sdd-cli](https://github.com/cyberash-dev/sdd-cli),
embedded here as a git submodule.

This repo is intentionally project-, vendor-, and VCS-agnostic. Project- or
vendor-specific extensions live in their own repos that embed this one as a
git submodule and reuse `scripts/lib/install-lib.sh` (see
[Downstream extensions](#downstream-extensions)).

## Layout

```
.
├── CLAUDE.md           # entry point for Claude Code (uses @rules/* imports)
├── rules/              # universal code-quality and process rules
├── sdd-cli/            # git submodule: Spec-Driven Development tooling (--sdd only)
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
- **`sdd-cli/`** — git submodule pinning
  [sdd-cli](https://github.com/cyberash-dev/sdd-cli), the Spec-Driven
  Development tool. Touched only with `--sdd`: install.sh fetches the
  submodule, `npm install` + `npm run build` + `npm link`s it, then runs
  `sdd install <mode>` so sdd-cli installs its own rules, skill, and hooks.
- **`hooks/`** — hook scripts installed unconditionally
  (currently `code-navigation-reminder.sh`).
- **`skills/`** — SKILL.md bundles (open standard, supported by both Claude Code
  and Codex CLI / IDE). Each subdir is one skill and gets symlinked
  **per-skill** into `~/.claude/skills/<name>` and
  `~/.agents/skills/<name>`, so the user's own hand-rolled skills in those
  directories are left untouched. Currently empty — drop new skills here.
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
./scripts/install.sh all --sdd          # + Spec-Driven Development via sdd-cli
```

### Flags

| Flag | Effect |
|---|---|
| *(none)* | universal rules + `hooks/`. Agent uses built-in git knowledge. |
| `--sdd` | fetch the `sdd-cli/` submodule, `npm install` + `npm run build` + `npm link` it, then run `sdd install <mode>`. sdd-cli installs its own rules, skill, and hooks. |

### Targets

| Agent       | Target path                                 | Source                                |
|-------------|---------------------------------------------|---------------------------------------|
| Claude Code | `~/.claude/CLAUDE.md` (generated file)      | `CLAUDE.md`                           |
| Claude Code | `~/.claude/rules` (symlink)                 | `rules/`                              |
| Claude Code | `~/.claude/hooks` (symlink)                 | `hooks/`                              |
| Claude Code | `~/.claude/settings.json` (mutated)         | hook entries idempotently upserted    |
| Claude Code | `~/.claude/skills/<name>` (symlink per skill) | `skills/<name>/`                    |
| Codex CLI / IDE | `${CODEX_HOME:-~/.codex}/AGENTS.md` (symlink) | `build/AGENTS.md`                |
| Codex CLI / IDE | `~/.agents/skills/<name>` (symlink per skill) | `skills/<name>/`                |

With `--sdd`, sdd-cli writes its own targets on top of the above
(`~/.claude/sdd/`, `@sdd` imports appended to `~/.claude/CLAUDE.md`, its skill
and hooks); see the [sdd-cli](https://github.com/cyberash-dev/sdd-cli) docs.

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
| `code-navigation-reminder.sh` | `PreToolUse` | `Grep\|Read` | always |

With `--sdd`, sdd-cli merges its own hooks into `~/.claude/settings.json`.

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

Edit files under `rules/` or `hooks/` directly. Claude Code picks up
`*.md` changes on the next session — no rebuild needed (the symlinks resolve
to live files in this repo).

For Codex, regenerate the flat file after any `*.md` edit:

```bash
./scripts/install.sh codex     # also re-runs the build
# or, equivalently:
./scripts/build.sh
```

SDD docs live in the `sdd-cli` submodule; edit them there and re-run
`./scripts/install.sh <mode> --sdd`.

## Per-agent install

```bash
./scripts/install.sh claude [--sdd]   # only Claude Code
./scripts/install.sh codex  [--sdd]   # only Codex (also runs build)
./scripts/install.sh all    [--sdd]   # both
```

## Adding a new skill

Drop `skills/<name>/SKILL.md` (plus any supporting files) into the repo, then
re-run `./scripts/install.sh all`. Per-skill symlinks land in
`~/.claude/skills/<name>` and `~/.agents/skills/<name>`. Skills are
auto-discovered from `skills/*/` — no flag, no list to maintain.

User-owned skills with different names (e.g. `~/.claude/skills/my-thing/`)
are untouched. A same-name collision is backed up to
`<target>.bak.<unix-timestamp>` like every other install target.

## Adding a new hook

Drop `hooks/<name>.sh`, then add an `install_hook` call in `install_claude`
in `scripts/install.sh`.

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
