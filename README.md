# coding-agent-config

Portable coding-agent setup for Claude Code and Codex CLI / IDE on macOS,
Linux, and Windows.

Single source of truth for universal coding rules and hooks. One script
symlinks them into the per-user config locations of each agent and registers
hooks in `~/.claude/settings.json`. The optional `--sdd` flag delegates
Spec-Driven Development setup to the
[`agent-sdd`](https://www.npmjs.com/package/agent-sdd) npm package.

This repo is intentionally project-, vendor-, and VCS-agnostic. Project- or
vendor-specific extensions live in their own repos that embed this one as a
git submodule and reuse `scripts/lib/install-lib.sh` (see
[Downstream extensions](#downstream-extensions)).

## Layout

```
.
├── CLAUDE.md           # entry point for Claude Code (uses @rules/* imports)
├── rules/              # universal code-quality and process rules
├── hooks/              # hooks installed unconditionally
├── skills/             # SKILL.md bundles, symlinked per-skill into both agents
├── templates/          # generation fragments (not symlinked into agents)
│   └── language/       #   reply-language directive, selected by --lang
├── build/              # generated, gitignored
│   └── AGENTS.md       #   flat file for Codex (built from CLAUDE.md + imports)
├── tests/              # shell tests for the install libs (`bash tests/<name>.test.sh`)
└── scripts/
    ├── build.sh        # rebuild build/AGENTS.md
    ├── install.sh      # symlink into Claude/Codex config locations
    └── lib/
        ├── install-lib.sh      # reusable shell helpers (public extension surface)
        ├── platform.sh         # OS detection and path translation (sourced by install-lib)
        └── npm-mcp-updates.sh  # npm-backed MCP install/update (sourced by install-lib)
```

### What's where, and why

- **`rules/`** — universal coding rules (naming, architecture, typescript,
  python, testing, commits, errors, review, code-navigation, workflow,
  simplicity). Apply on every machine.
- **Spec-Driven Development** — the [`agent-sdd`](https://www.npmjs.com/package/agent-sdd)
  npm package, the Spec-Driven Development tool. Touched only with `--sdd`:
  install.sh installs it globally (`npm install -g agent-sdd`), then runs
  `sdd install <mode>` so agent-sdd installs its own rules, skill, and hooks.
- **`hooks/`** — hook scripts. `code-navigation-reminder.sh` is registered
  unconditionally; `codex-commit-review.sh` only with `--codex-review`.
- **`skills/`** — SKILL.md bundles (open standard, supported by both Claude Code
  and Codex CLI / IDE). Each subdir is one skill and gets symlinked
  **per-skill** into `~/.claude/skills/<name>` and
  `~/.agents/skills/<name>`, so the user's own hand-rolled skills in those
  directories are left untouched. Currently empty — drop new skills here.
- **`scripts/lib/install-lib.sh`** — shell library exposing the symlink,
  hook-registration, permission/env, MCP-registration, and import-inlining
  primitives. Sourced by this repo's drivers and intended to be reused by
  downstream extension repos. It sources `platform.sh` and
  `npm-mcp-updates.sh`, so `agent_home`, `native_path` and
  `ensure_mcp_npm_global` come with it.
- **`scripts/lib/platform.sh`** — OS detection (`os_kind`, `is_windows`), the
  install root (`agent_home` / `$AGENT_HOME`), path translation
  (`native_path`, `windows_path`, `posix_path`) and the NTFS junction
  primitives. Everything here is the identity on macOS and Linux.

`CLAUDE.md` is intentionally tiny — a table of contents that Claude Code
expands at session start via `@rules/X.md` imports. Codex does not
understand `@import`, so `scripts/build.sh` produces a flattened
`build/AGENTS.md` with all referenced files inlined.

## Platform support

| Platform | How install.sh runs | Link model |
|---|---|---|
| macOS | any shell | symlinks |
| Linux (incl. WSL) | any shell | symlinks |
| Windows, native | **from Git Bash** | junctions for directories, copy for files |

Required on every platform: `bash`, `jq`, `awk`. `node` + `npm` are optional —
without them the MCP registration is skipped with a warning and everything else
installs. `install.sh` checks for the required tools before it mutates
anything, so a missing `jq` aborts the run cleanly instead of leaving a
half-install.

### Windows

Run `./scripts/install.sh` **from Git Bash**, not PowerShell or CMD.
[Git for Windows](https://git-scm.com/downloads/win) is required: it provides
the bash that runs the installer and the bash that Claude Code uses to execute
the `hooks/*.sh` scripts. Without it Claude Code falls back to PowerShell,
where a `.sh` hook cannot run — hooks are therefore registered with
`"shell": "bash"` on Windows so that failure is explicit.

Two behaviours differ from macOS/Linux:

- **Directories are NTFS junctions, not symlinks.** `ln -s` under Git Bash
  copies unless Developer Mode is on, so `rules/`, `hooks/` and each skill are
  linked with `mklink /J`, which needs no elevation. The repo stays the live
  source: editing `rules/*.md` takes effect on the next Claude Code session,
  exactly as on macOS.
- **`AGENTS.md` is a copy.** A single file has no junction equivalent, so
  `${CODEX_HOME:-%USERPROFILE%\.codex}\AGENTS.md` is copied. After editing any
  `*.md`, re-run `./scripts/install.sh codex` to refresh it.

Install targets are anchored at `%USERPROFILE%`, not `$HOME`: Git Bash derives
`$HOME` from `HOMEDRIVE`/`HOMEPATH`, which corporate profiles point at a
network share, while Claude Code itself reads `%USERPROFILE%\.claude`.

### WSL

WSL is treated as Linux and works with no special handling. Note that a WSL
install configures the Claude Code **inside** WSL — it does not reach a
Windows-side installation, and vice versa. Pick one and install there.

## First-time install on a new machine

```bash
git clone <this-repo> ~/Projects/coding-agent-config
cd ~/Projects/coding-agent-config
./scripts/install.sh all                # universal rules + hooks
./scripts/install.sh all --sdd          # + Spec-Driven Development via agent-sdd
./scripts/install.sh all --lang=en      # pin replies to English (or ru)
```

### Flags

| Flag | Effect |
|---|---|
| *(none)* | universal rules + `hooks/`. Agent uses built-in git knowledge. |
| `--lang=ru\|en` | pin the agent's reply language. Omitted, the agent replies in the operator's own language; set, it always replies in Russian or English. |
| `--sdd` | install the `agent-sdd` npm package globally, then run `sdd install <mode>`. agent-sdd installs its own rules, skill, and hooks. |
| `--teams` | set `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in the `env` block of `~/.claude/settings.json` (claude/all). Omitted, the key is removed. |
| `--codex-review` | register the `codex-commit-review.sh` `PreToolUse` hook (claude/all). Omitted, the hook is removed. |
| `--update-mcps` | update npm-backed MCP packages to `latest` without asking per package. |

### Targets

`$AGENT_HOME` below is `$HOME` on macOS and Linux, and `%USERPROFILE%` on
Windows. "symlink" means a junction on Windows (see
[Platform support](#platform-support)).

| Agent       | Target path                                 | Source                                |
|-------------|---------------------------------------------|---------------------------------------|
| Claude Code | `$AGENT_HOME/.claude/CLAUDE.md` (generated file) | `CLAUDE.md`                      |
| Claude Code | `$AGENT_HOME/.claude/rules` (symlink)       | `rules/`                              |
| Claude Code | `$AGENT_HOME/.claude/hooks` (symlink)       | `hooks/`                              |
| Claude Code | `$AGENT_HOME/.claude/settings.json` (mutated) | hook entries idempotently upserted; `env` with `--teams` |
| Claude Code | `$AGENT_HOME/.claude/skills/<name>` (symlink per skill) | `skills/<name>/`          |
| Codex CLI / IDE | `${CODEX_HOME:-$AGENT_HOME/.codex}/AGENTS.md` (symlink, copy on Windows) | `build/AGENTS.md` |
| Codex CLI / IDE | `$AGENT_HOME/.agents/skills/<name>` (symlink per skill) | `skills/<name>/`      |

With `--sdd`, agent-sdd writes its own targets on top of the above
(`~/.claude/sdd/`, `@sdd` imports appended to `~/.claude/CLAUDE.md`, its skill
and hooks); see the [`agent-sdd`](https://www.npmjs.com/package/agent-sdd) docs.

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
| `codex-commit-review.sh` | `PreToolUse` | `Bash` | `--codex-review` |

`codex-commit-review.sh` is opt-in on purpose: before every `git commit` /
`arc commit` it runs `codex` twice — a read-only review pass, then a
`workspace-write` pass that edits the working copy and re-stages the files that
were already staged. It never asks for confirmation, it reports what it did
through the hook's `additionalContext`. It is fail-open (no `codex` on PATH,
or a failing pass, lets the commit through untouched) and can be muted at
runtime with `~/.claude/codex-commit-review.disabled` or
`CODEX_COMMIT_REVIEW_DISABLED=1`.

With `--sdd`, agent-sdd merges its own hooks into `~/.claude/settings.json`.

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

On macOS and Linux the registered `command` is the absolute path to the
installed bin. On Windows npm installs a `.cmd` shim, which the agent cannot
spawn without a shell, so the package's own JS entry point is registered as
`node <path>` instead (falling back to `cmd /c <bin>` if it cannot be
resolved).

If `npm install -g` fails (no network, missing registry auth, etc.), the
MCP is skipped with a warning rather than aborting the whole install.

## Editing rules

Edit files under `rules/` or `hooks/` directly. Claude Code picks up
`*.md` changes on the next session — no rebuild needed (the symlinks, and the
junctions on Windows, resolve to live files in this repo).

For Codex, regenerate the flat file after any `*.md` edit:

```bash
./scripts/install.sh codex     # also re-runs the build
# or, equivalently:
./scripts/build.sh
```

On Windows `./scripts/build.sh` alone is not enough: `AGENTS.md` is a copy, not
a link, so use `./scripts/install.sh codex` to rebuild **and** re-copy it.

SDD docs ship inside the `agent-sdd` npm package. To pick up a new release,
re-run `./scripts/install.sh <mode> --sdd` (it installs `agent-sdd` globally;
remove the stale global package first if you need to force a downgrade).

## Per-agent install

```bash
./scripts/install.sh claude [--sdd] [--teams] [--codex-review] [--lang=ru|en]
./scripts/install.sh codex  [--sdd] [--lang=ru|en]   # only Codex (also runs build)
./scripts/install.sh all    [--sdd] [--teams] [--codex-review] [--lang=ru|en]
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
3. Call `link`, `install_hook`, `install_skills`, `install_permission_rules`,
   `install_teams_env`, `install_codex_review_hook`, `ensure_mcp_npm_global`,
   `ensure_agent_sdd`, `mcp_launch_spec`, `register_mcp_claude`,
   `register_mcp_codex`, `register_core_mcp_claude`, `register_core_mcp_codex`,
   etc. with paths inside the extension repo, and append its own
   `## <Section>` blocks to `$AGENT_HOME/.claude/CLAUDE.md` after the core
   driver has written it.

Downstream drivers should anchor their own targets at `$AGENT_HOME` rather than
`$HOME`, and pass anything that lands in a config file consumed by the agent
(hook commands, MCP commands) through `native_path`. Both come from
`platform.sh`, which `install-lib.sh` sources.

The lib is the only stable contract. Helpers are documented in the file
header and remain backwards-compatible across patch releases.

## Out of scope

- `~/.claude/agents/`, `~/.claude/commands/`,
  `~/.claude/projects/*/memory/` — not managed by this repo.
- Skills you authored yourself in `~/.claude/skills/` or `~/.agents/skills/` —
  install.sh only touches subdirs that match a name in this repo's `skills/`.
- `~/.codex/config.toml` — not managed.
- Permissions in `~/.claude/settings.json` (`allow`/`deny`/`ask`) — this
  install.sh mutates only the `hooks` block and, with `--teams`, the `env`
  block. The `install_permission_rules` helper exists for downstream repos
  that bring their own tools; nothing else in the file is touched.
