# coding-agent-config

Portable coding-agent setup for Claude Code and Codex CLI on macOS.

Single source of truth for rules, hooks, and tool-specific guidance;
one script symlinks them into the per-user config locations of each
agent and registers hooks in `~/.claude/settings.json`.

## Layout

```
.
├── CLAUDE.md           # entry point for Claude Code (uses @rules/* imports)
├── rules/              # universal code-quality and process rules
├── vcs/                # VCS-specific rules (e.g. arc.md). Optional.
├── yandex/             # Arcadia/Yandex-specific tool rules. Optional.
│   ├── *.md            #   short pointer files (inlined into CLAUDE.md)
│   ├── refs/           #   long reference docs (lazy-loaded by path)
│   └── hooks/          #   yandex-specific hook scripts
├── hooks/              # hooks installed unconditionally
├── skills/             # SKILL.md bundles, symlinked per-skill into both agents
├── build/              # generated, gitignored
│   └── AGENTS.md       #   flat file for Codex (built from CLAUDE.md + imports)
└── scripts/
    ├── build.sh        # rebuild build/AGENTS.md
    └── install.sh      # symlink into ~/.claude and/or ~/.codex
```

### What's where, and why

- **`rules/`** — universal coding rules (naming, architecture, testing,
  commits, errors, review, code-navigation, workflow, simplicity).
  Apply on every machine.
- **`vcs/`** — guidance for non-git VCS. Currently only `arc.md` (Yandex
  Arcadia). Without `--vcs`, the agent uses its built-in git knowledge.
- **`yandex/`** — Arcadia-specific MCP tools, internal-service docs,
  `a.yaml` (CI), `infractl`, `tasklet`, Yandex Cloud, payment-services
  domain knowledge. Top-level `*.md` are short pointer files inlined into
  CLAUDE.md; `yandex/refs/*.md` are large schema/reference docs read
  on-demand via paths embedded in the pointer files.
- **`hooks/`** — hook scripts installed unconditionally
  (currently `lsp-reminder.sh`).
- **`yandex/hooks/`** — hook scripts installed only with `--yandex`
  (currently `block-arcadia-broad-search.sh`).
- **`skills/`** — SKILL.md bundles (open standard, supported by both Claude Code
  and Codex CLI). Each subdir is one skill and gets symlinked **per-skill** into
  `~/.claude/skills/<name>` and `~/.codex/skills/<name>`, so the user's own
  hand-rolled skills in those directories are left untouched.

`CLAUDE.md` is intentionally tiny — a table of contents that Claude Code
expands at session start via `@rules/X.md` imports. Codex does not
understand `@import`, so `scripts/build.sh` produces a flattened
`build/AGENTS.md` with all referenced files inlined.

## First-time install on a new machine

```bash
git clone <this-repo> ~/Projects/coding-agent-config
cd ~/Projects/coding-agent-config
./scripts/install.sh all                # universal rules only
./scripts/install.sh all --yandex       # + Arcadia, implies --vcs arc
./scripts/install.sh all --vcs arc      # + Arc VCS, no Yandex tooling
```

### Flags

| Flag | Effect |
|---|---|
| *(none)* | universal rules + `hooks/`. Agent uses built-in git knowledge. |
| `--vcs arc` | + `vcs/arc.md` |
| `--vcs git` | explicit "no VCS bundle" — same as omitting the flag |
| `--yandex` | + all `yandex/*.md` + `yandex/hooks/`. Implies `--vcs arc` unless `--vcs` is given explicitly. |

### Targets

| Agent       | Target path                                 | Source                                     |
|-------------|---------------------------------------------|--------------------------------------------|
| Claude Code | `~/.claude/CLAUDE.md` (generated file)      | `CLAUDE.md` + optional VCS/Yandex sections |
| Claude Code | `~/.claude/rules` (symlink)                 | `rules/`                                   |
| Claude Code | `~/.claude/hooks` (symlink)                 | `hooks/`                                   |
| Claude Code | `~/.claude/vcs` (symlink, with `--vcs`)     | `vcs/`                                     |
| Claude Code | `~/.claude/yandex` (symlink, with `--yandex`)| `yandex/`                                 |
| Claude Code | `~/.claude/settings.json` (mutated)         | hook entries idempotently upserted         |
| Claude Code | `~/.claude/skills/<name>` (symlink per skill) | `skills/<name>/`                         |
| Codex CLI   | `~/.codex/AGENTS.md` (symlink)              | `build/AGENTS.md`                          |
| Codex CLI   | `~/.codex/skills/<name>` (symlink per skill)  | `skills/<name>/`                         |

If anything already exists at a target path it is renamed to
`<target>.bak.<unix-timestamp>` before the symlink/file is created.

`~/.claude/CLAUDE.md` and `~/.claude/settings.json` are **regenerated on
every run** (so flag changes take effect). All other targets are
symlinks — re-running with the same flags is a no-op (`= already linked`).

### Hooks

Registered in `~/.claude/settings.json` idempotently — entries are matched
by script basename, stale paths are removed, the canonical path is
upserted. The script will not delete unrelated hook entries (e.g.
the `UserPromptSubmit` `PROJECT_MAP` reminder).

| Hook | Event | Matcher | Installed when |
|---|---|---|---|
| `lsp-reminder.sh` | `PreToolUse` | `Grep\|Read` | always |
| `block-arcadia-broad-search.sh` | `PreToolUse` | `Bash\|Grep\|Glob` | `--yandex` |

## Editing rules

Edit files under `rules/`, `vcs/`, `yandex/`, or `hooks/` directly.
Claude Code picks up `*.md` changes on the next session — no rebuild
needed (the symlinks resolve to live files in this repo).

For Codex, regenerate the flat file after any `*.md` edit:

```bash
./scripts/install.sh codex --yandex     # match the flags you installed with
# or, equivalently:
./scripts/build.sh --yandex
```

If you change which top-level files exist (add/remove a `yandex/*.md` or
swap `vcs/arc.md`), re-run `./scripts/install.sh claude --yandex` so
`~/.claude/CLAUDE.md` is regenerated with the new `@`-import list.

## Per-agent install

```bash
./scripts/install.sh claude [flags]   # only Claude Code
./scripts/install.sh codex  [flags]   # only Codex (also runs build)
./scripts/install.sh all    [flags]   # both
```

## Adding a new VCS or tool bundle

- New VCS: drop `vcs/<name>.md` into the repo. Install with
  `--vcs <name>`. The generated CLAUDE.md gets `@vcs/<name>.md`.
- New top-level Yandex topic: drop `yandex/<topic>.md` into the repo.
  It is auto-discovered (alphabetical) and inlined when `--yandex` is set.
- Long reference docs that should NOT bloat the always-on context: put
  them in `yandex/refs/` and reference them by path from a top-level
  `yandex/<topic>.md` pointer file.

## Adding a new skill

Drop `skills/<name>/SKILL.md` (plus any supporting files) into the repo, then
re-run `./scripts/install.sh all`. Per-skill symlinks land in
`~/.claude/skills/<name>` and `~/.codex/skills/<name>`. Skills are
auto-discovered from `skills/*/` — no flag, no list to maintain.

User-owned skills with different names (e.g. `~/.claude/skills/my-thing/`)
are untouched. A same-name collision is backed up to
`<target>.bak.<unix-timestamp>` like every other install target.

## Adding a new hook

- Universal hook: drop `hooks/<name>.sh`, then add an `install_hook`
  call in `install_claude` in `scripts/install.sh`.
- Yandex-only hook: drop `yandex/hooks/<name>.sh`, add an `install_hook`
  call inside the `if [[ "$YANDEX" -eq 1 ]]` block.

Hook registration is idempotent — re-running install will replace any
prior entry that points at a script with the same basename.

## Out of scope

- `~/.claude/agents/`, `~/.claude/commands/`,
  `~/.claude/projects/*/memory/` — not managed by this repo.
- Skills you authored yourself in `~/.claude/skills/` or `~/.codex/skills/` —
  install.sh only touches subdirs that match a name in this repo's `skills/`.
- `~/.codex/config.toml` — not managed.
- Permissions in `~/.claude/settings.json` (`allow`/`deny`/`ask`) —
  install.sh only mutates the `hooks` block; everything else is left
  intact.
