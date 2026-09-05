# coding-agent-config

Portable coding-agent setup for Claude Code, Codex CLI / IDE and Cursor on
macOS, Linux, and Windows.

Single source of truth for universal coding rules and hooks. One script copies
them into the per-user config locations of each agent and registers hooks in
`~/.claude/settings.json` and `~/.cursor/hooks.json`. The optional `--sdd` flag
delegates Spec-Driven Development setup to the
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
├── skills/             # SKILL.md bundles, copied per-skill into every agent
├── codex-review/       # opt-in review bundle, installed only with --codex-review
│   └── skills/         #   code-review (policy) + codex-cli-review (CLI transport)
├── templates/          # generation fragments (never copied into agents as-is)
│   ├── language/       #   reply-language directive, selected by --lang
│   ├── review/         #   rule index the commit review runs against
│   └── teams/          #   orchestration section, selected by --teams
├── build/              # generated, gitignored
│   ├── AGENTS.md       #   flat file for Codex (built from CLAUDE.md + imports)
│   └── cursor/rules/   #   one .mdc per rule for Cursor (frontmatter + body)
├── tests/              # `bash tests/<name>.test.sh`, `python3 tests/<name>.test.py`
└── scripts/
    ├── build.sh        # rebuild build/AGENTS.md
    ├── build-cursor.sh # rebuild build/cursor/rules/*.mdc
    ├── install.sh      # copy into Claude/Codex/Cursor config locations
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
  unconditionally; `codex-commit-review.sh` (Claude Code) and its Cursor entry
  point `cursor-commit-review.sh` only with `--codex-review`.
- **`skills/`** — SKILL.md bundles (open standard, supported by Claude Code,
  Codex CLI / IDE and Cursor alike). Each subdir is one skill and gets copied
  **per-skill** into `~/.claude/skills/<name>` and `~/.agents/skills/<name>`,
  so the user's own hand-rolled skills in those directories are left untouched.
  Cursor reads `~/.agents/skills` too, which is why the cursor mode installs
  there instead of into a fourth copy. Currently empty — drop new skills here.
- **`codex-review/`** — the review bundle, installed only with `--codex-review`
  (into both `~/.claude/skills/` and `~/.agents/skills/`, removed without the
  flag). `code-review` holds the review policy; `codex-cli-review` holds the
  VCS-neutral transport — `scripts/codex_review.py` starts a fresh read-only
  `codex exec` on a supplied scope file and returns the review as JSON against
  `scripts/review-output.schema.json`. `codex-commit-review.sh` runs its review
  through that script, so hook and skills share one review policy.
- **`templates/review/rules.md`** — the rule index the review is generated
  from. `install.sh --codex-review` inlines it into the review's own
  `AGENTS.md` (see [Review cost](#review-cost)). Process, navigation,
  orchestration and output-style rules are left out: a read-only reviewer drives
  no workflow and talks to no operator, and every rule it carries is re-sent on
  each turn of the review.
- **`scripts/lib/install-lib.sh`** — shell library exposing the copy,
  hook-registration, permission/env, MCP-registration, rule-generation and
  import-inlining primitives. Sourced by this repo's drivers and intended to be
  reused by downstream extension repos. It sources `platform.sh` and
  `npm-mcp-updates.sh`, so `agent_home`, `native_path` and
  `ensure_mcp_npm_global` come with it.
- **`scripts/lib/platform.sh`** — OS detection (`os_kind`, `is_windows`), the
  install root (`agent_home` / `$AGENT_HOME`), path translation
  (`native_path`, `windows_path`, `posix_path`) and the two NTFS junction
  primitives left for migration — an install from an older version of this repo
  linked directories instead of copying them. Everything here is the identity
  on macOS and Linux.

`CLAUDE.md` is intentionally tiny — a table of contents that Claude Code
expands at session start via `@rules/X.md` imports. Codex does not
understand `@import` (it merges one instruction file per directory and nothing
else), so `scripts/build.sh` produces a flattened `build/AGENTS.md` with all
referenced files inlined. Cursor ignores plain `.md` in a rules directory, so
`scripts/build-cursor.sh` republishes each rule as `<name>.mdc` with
`alwaysApply: true` frontmatter and the description taken from the same
`CLAUDE.md` index line.

## Platform support

| Platform | How install.sh runs | Install model |
|---|---|---|
| macOS | any shell | copies |
| Linux (incl. WSL) | any shell | copies |
| Windows, native | **from Git Bash** | copies |

Rules, hooks and skills are **copied**, not linked, on every platform: editing
this repo takes effect on the next `install.sh` run, not on the next agent
session. What the installer wrote is recorded in a `.coding-agent-config`
manifest next to the copies, so a later run removes its own stale files (a rule
dropped from the index, a bundle switched off) and leaves everything else in
that directory alone.

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

Nothing about the install model differs from macOS/Linux any more — every
target is a copy. An install from an older version of this repo left NTFS
junctions behind; those are unlinked (never `mv`-ed, which would drag the repo
contents out) the first time the copy lands on top of them.

Cursor is the one place where a hook is registered without a shell selector of
its own, so a `.sh` hook there needs `bash` on `PATH`; the installer says so
when it registers it.

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
./scripts/install.sh all                # universal rules + hooks, all three agents
./scripts/install.sh all --sdd          # + Spec-Driven Development via agent-sdd
./scripts/install.sh all --lang=en      # pin replies to English (or ru)
./scripts/install.sh cursor             # Cursor only
```

### Flags

| Flag | Effect |
|---|---|
| *(none)* | universal rules + `hooks/`. Agent uses built-in git knowledge. |
| `--lang=ru\|en` | pin the agent's reply language. Omitted, the agent replies in the operator's own language; set, it always replies in Russian or English. |
| `--sdd` | install the `agent-sdd` npm package globally, then run `sdd install <mode>`. agent-sdd installs its own rules, skill, and hooks. |
| `--teams` | delegation-first setup: adds `rules/orchestration.md` to the generated `CLAUDE.md` / `AGENTS.md` and to the Cursor rule set, sets `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in the `env` block of `~/.claude/settings.json` (omitted, the key is removed), and turns both Codex gates on in `~/.codex/config.toml` — `features.multi_agent` and `agents.enabled` (omitted, the config is left as-is). Cursor has no runtime gate to flip, so there it is the rule alone. See [Orchestration](#orchestration). |
| `--codex-review` | install the `codex-review/` skills on every surface, write the trimmed `CODEX_HOME` the review runs in, and register the commit-review hook for Claude Code (`PreToolUse`) and Cursor (`beforeShellExecution`); Codex has no hook configuration to put it in. Omitted, all three are removed. See [Review cost](#review-cost). |
| `--update-mcps` | update npm-backed MCP packages to `latest` without asking per package. |

### Targets

`$AGENT_HOME` below is `$HOME` on macOS and Linux, and `%USERPROFILE%` on
Windows.

| Agent       | Target path                                 | Source                                |
|-------------|---------------------------------------------|---------------------------------------|
| Claude Code | `$AGENT_HOME/.claude/CLAUDE.md` (generated file) | `CLAUDE.md`                      |
| Claude Code | `$AGENT_HOME/.claude/rules` (copied)        | `rules/`                              |
| Claude Code | `$AGENT_HOME/.claude/hooks` (copied)        | `hooks/`                              |
| Claude Code | `$AGENT_HOME/.claude/settings.json` (mutated) | hook entries idempotently upserted; `env` with `--teams` |
| Claude Code | `$AGENT_HOME/.claude/skills/<name>` (copied per skill) | `skills/<name>/`, plus `codex-review/skills/<name>/` with `--codex-review` |
| Codex CLI / IDE | `${CODEX_HOME:-$AGENT_HOME/.codex}/AGENTS.md` (copied) | `build/AGENTS.md` |
| Codex CLI / IDE | `${CODEX_HOME:-$AGENT_HOME/.codex}/config.toml` (mutated) | `[mcp_servers.<name>]`; `features.multi_agent` + `agents.enabled` with `--teams` |
| Codex CLI / IDE | `$AGENT_HOME/.agents/skills/<name>` (copied per skill) | `skills/<name>/`, plus `codex-review/skills/<name>/` with `--codex-review` |
| Cursor | `$AGENT_HOME/.cursor/rules/<name>.mdc` (generated, one per rule) | `build/cursor/rules/`, built from `CLAUDE.md` + `rules/` |
| Cursor | `$AGENT_HOME/.cursor/hooks` (copied)        | `hooks/`                              |
| Cursor | `$AGENT_HOME/.cursor/hooks.json` (mutated)  | `beforeShellExecution` entry with `--codex-review` |
| Cursor | `$AGENT_HOME/.cursor/mcp.json` (mutated)    | `mcpServers.<name>`                   |
| Cursor | `$AGENT_HOME/.agents/skills/<name>` (copied per skill) | shared with the Codex target above |
| Codex CLI (review only) | `$AGENT_HOME/.cache/coding-agent-config/codex-review-home/` (generated) | `templates/review/rules.md` + `rules/`, with `--codex-review` |

Codex reads `AGENTS.override.md` in preference to `AGENTS.md` at every level.
If one exists in the Codex home the install would look successful while nothing
loaded, so `install.sh codex` warns about it.

With `--sdd`, agent-sdd writes its own targets on top of the above
(`~/.claude/sdd/`, `@sdd` imports appended to `~/.claude/CLAUDE.md`, its skill
and hooks); see the [`agent-sdd`](https://www.npmjs.com/package/agent-sdd) docs.

A file at a target path that this repo does not own is renamed to
`<target>.bak.<unix-timestamp>` before the copy lands. Files the installer
wrote earlier are simply overwritten — its own manifest says they are its own.

Re-running with the same flags writes nothing at all: identical copies are
skipped, and the config files (`settings.json`, `.claude.json`, `config.toml`,
`hooks.json`, `mcp.json`) are only rewritten when the result actually differs,
so a repeat install leaves no new `.bak` behind.

If an older install created repo-owned skill symlinks under
`~/.codex/skills/<name>`, `install.sh codex` removes those legacy symlinks
after installing the replacement under `~/.agents/skills/<name>`. It only
removes same-name symlinks for skills managed by this repo; unrelated files
and directories are left untouched. If `~/.codex/skills` becomes empty, the
legacy directory is removed too.

### Hooks

Registered in `~/.claude/settings.json` and `~/.cursor/hooks.json`
idempotently — the entry is replaced where it already sits, so a repeat install
rewrites nothing. Before adding a hook the installer checks what is already
there:

- **An entry it owns** — the same script, or a same-name script from the
  directory this install writes to — is taken out of *every* event first, so a
  hook that moved to another event does not stay registered on the old one.
- **A same-name hook pointing at a path you own** (say
  `/my/tools/code-navigation-reminder.sh`) is left untouched and reported:
  `! /my/tools/... also registers ...; left as is`. Two different scripts may
  legitimately share a file name.
- **Repeats of one command inside the target event**, whoever wrote them (e.g.
  a hook registered twice under `Edit|Write|MultiEdit` and `Edit|Write`),
  collapse to the last registration — the current one, so the tool that wrote
  it finds its own entry next time instead of adding a third.

Unrelated hooks are never touched — other events, other scripts, and the
`UserPromptSubmit` `PROJECT_MAP` reminder stay as they are.

The same collapse runs once more at the very end of the install, across every
event: with `--sdd`, agent-sdd merges its own hooks *after* this script and
re-adds an entry for a script it already registered under a wider matcher.

| Hook | Harness | Event | Matcher | Installed when |
|---|---|---|---|---|
| `code-navigation-reminder.sh` | Claude Code | `PreToolUse` | `Grep\|Read` | always |
| `codex-commit-review.sh` | Claude Code | `PreToolUse` | `Bash` | `--codex-review` |
| `cursor-commit-review.sh` | Cursor | `beforeShellExecution` | — | `--codex-review` |

Cursor has no equivalent of the navigation reminder: a hook there can hand the
agent a message only when it *refuses* the action, and `beforeReadFile` cannot
inject context at all. The same guidance reaches Cursor as the always-applied
`code-navigation.mdc` rule instead.

`codex-commit-review.sh` is opt-in on purpose: before every `git commit` /
`arc commit` it runs a read-only `codex` review of the uncommitted changes and
refuses the commit so the findings reach the agent, which decides what to act
on and re-runs the commit. Nothing on disk is touched by the hook. It is
fail-open (no `codex` on PATH, or a failing review, lets the commit through
untouched) and can be muted at runtime with
`~/.claude/codex-commit-review.disabled` or `CODEX_COMMIT_REVIEW_DISABLED=1`.

The hash of the reviewed change is remembered under
`~/.cache/coding-agent-config/commit-review/`, so the retry is let straight
through instead of starting another review; a change that moved on since is
reviewed again.

One script, two hook protocols, selected by `COMMIT_REVIEW_PROTOCOL`:

- **Claude Code** — `permissionDecision: "deny"` with the review in
  `permissionDecisionReason`.
- **Cursor** — entered through `cursor-commit-review.sh`, which sets the
  variable. `permission: "deny"` with the review in `agent_message`; Cursor
  delivers a hook message to the agent only on a refusal.

The review itself is the `codex-cli-review` skill: the hook writes the status and
the staged plus unstaged diff into a scope file and calls
`codex-cli-review/scripts/codex_review.py` from the first skill root that has
it (`~/.claude/skills`, `~/.agents/skills`, `~/.cursor/skills`), which runs the
review under the `code-review` policy and returns JSON. That is why the flag
installs skills and hook together — without the skill the hook allows the commit
and says the review was skipped.

With `--sdd`, agent-sdd merges its own hooks into `~/.claude/settings.json`.

### Review cost

A review is a full agentic pass: the child re-sends its whole context on every
turn, so what the review costs is (turns × context), not the size of the diff.
Both factors are held down deliberately.

**Its own `CODEX_HOME`.** `--codex-review` generates
`~/.cache/coding-agent-config/codex-review-home/`, and `codex_review.py` points
the child at it. The operator's own codex home carries MCP servers, plugins, an
interactive model and the full rule set; this one carries the review-scoped
rules from `templates/review/rules.md`, `model_reasoning_effort = "medium"`,
`web_search = false` and `multi_agent = false`. Login is a symlink to
`${CODEX_HOME:-~/.codex}/auth.json`, so the review signs in as the operator and
follows a token refresh. An operator whose OAuth tokens live in the OS keyring
has no `auth.json` to share, and a `CODEX_HOME` switched since the install
points that link at another account. In both cases the review falls back to the
operator's own home: the expensive review that works, signed in as the account
the caller selected, beats the cheap one that cannot. For the same reason the
home is not written at all when the operator's `config.toml` selects a model
provider, which the generated config cannot stand in for. Measured on this repo, the per-turn baseline drops from
~25k tokens to ~15k, and one review of the same 15KB scope from 583,735 input
tokens over 23 tool calls to 66,233 over 3.

The model is left to codex's own default: what a review costs is turns, and a
cheaper model that needs more of them to reach the same finding is not cheaper.
`CODEX_REVIEW_MODEL` pins one per machine where the account says otherwise. The
generated file itself is rewritten on every install.

**Gates before the pass.** The hook skips the review outright, and says so, when
the change is only prose or lock files (`CODEX_REVIEW_SKIP_PATHS`, matched
against both sides of a rename) or smaller than `CODEX_REVIEW_MIN_LINES` (10;
untracked files count their own length and a rename or delete clears the floor
outright, since no diff covers either). A diff over `CODEX_REVIEW_MAX_SCOPE_BYTES` (200000) is
truncated, with the cut declared in the scope. Set a list to empty or a floor to
0 to switch that gate off.

The review policy pulls its weight too: `code-review/SKILL.md` treats the rules
already in context as loaded, so the child no longer walks the tree above the
review root re-reading the same rule files it was started with.

### MCP servers

The install also registers MCP servers referenced by the rules into
`~/.claude.json` (`mcpServers.<name>`), `~/.codex/config.toml`
(`[mcp_servers.<name>]`) and `~/.cursor/mcp.json` (`mcpServers.<name>`, with no
`type` key — Cursor infers stdio from `command`). Each file is backed up to
`<path>.bak.<TS>` the first time a run actually changes it.

| MCP | npm package | Installed when | Env vars |
|---|---|---|---|
| `code-skeleton` | `code-skeleton-mcp` (public npm) | always | — |

The script runs `npm install -g <pkg>` once per package (idempotent — skips
if the bin is already on PATH). Other MCP entries you have in
`~/.claude.json`, `~/.codex/config.toml` or `~/.cursor/mcp.json` are left
untouched; only the names listed above are upserted.

On macOS and Linux the registered `command` is the absolute path to the
installed bin. On Windows npm installs a `.cmd` shim, which the agent cannot
spawn without a shell, so the package's own JS entry point is registered as
`node <path>` instead (falling back to `cmd /c <bin>` if it cannot be
resolved).

If `npm install -g` fails (no network, missing registry auth, etc.), the
MCP is skipped with a warning rather than aborting the whole install.

## Orchestration

Both agents can run sub-agents, and both are conservative about it by default.
`--teams` flips two independent things: the runtime switch, and the standing
authorization that makes the agent actually use it.

| | Runtime switch | Authorization |
|---|---|---|
| Claude Code | `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` — a sub-agent that Claude names becomes a teammate: own session, own context, direct messaging, shared task list | `rules/orchestration.md`, imported from the generated `~/.claude/CLAUDE.md` |
| Codex | `features.multi_agent` and `agents.enabled` — two independent gates, either one off keeps `spawn_agent` away from the model. Both ship on, so this only undoes a deliberate opt-out | the same rule, inlined into `~/.codex/AGENTS.md` |
| Cursor | nothing to flip — sub-agents need no config gate | the same rule, published as `~/.cursor/rules/orchestration.mdc` |

The authorization half is not decoration. Codex ships this in the description
of its `spawn_agent` tool:

> Do not spawn sub-agents unless the user or applicable AGENTS.md/skill
> instructions explicitly ask for sub-agents, delegation, or parallel agent
> work. Requests for depth, thoroughness, research, investigation, or detailed
> codebase analysis do not count as permission to spawn.

So `AGENTS.md` is the sanctioned channel for granting it, and the wording has
to name delegation outright. Codex role files (`~/.codex/agents/*.toml`) do not
help here — they pick *which* agent runs once spawning is already authorized.

Two harness limits worth knowing: Claude Code spawns teammates only in an
interactive session (under `-p` a named sub-agent is an ordinary sub-agent),
and teammates cannot spawn teammates of their own.

## Editing rules

Edit files under `rules/` or `hooks/` directly, then re-run the install — every
target is a copy, so nothing reaches an agent until it is copied again:

```bash
./scripts/install.sh all       # rebuilds AGENTS.md and the .mdc set, then copies
```

`./scripts/build.sh` and `./scripts/build-cursor.sh` only refresh the generated
files under `build/`; the install step is what puts them in place.

SDD docs ship inside the `agent-sdd` npm package. To pick up a new release,
re-run `./scripts/install.sh <mode> --sdd` (it installs `agent-sdd` globally;
remove the stale global package first if you need to force a downgrade).

## Per-agent install

```bash
./scripts/install.sh claude [--sdd] [--teams] [--codex-review] [--lang=ru|en]
./scripts/install.sh codex  [--sdd] [--teams] [--codex-review] [--lang=ru|en]  # only Codex (also runs build)
./scripts/install.sh cursor [--teams] [--codex-review] [--lang=ru|en]          # only Cursor (also runs build-cursor)
./scripts/install.sh all    [--sdd] [--teams] [--codex-review] [--lang=ru|en]
```

`--sdd` has no cursor target: `agent-sdd` installs for claude and codex only,
and the cursor mode says so instead of failing.

## Adding a new skill

Drop `skills/<name>/SKILL.md` (plus any supporting files) into the repo, then
re-run `./scripts/install.sh all`. Per-skill copies land in
`~/.claude/skills/<name>` and `~/.agents/skills/<name>` (which Cursor reads as
well). Skills are
auto-discovered from `skills/*/` — no flag, no list to maintain. The
`codex-review/skills/*/` bundle is the exception: it is discovered the same way
but only when `--codex-review` is passed.

User-owned skills with different names (e.g. `~/.claude/skills/my-thing/`)
are untouched. A same-name collision is backed up to
`<target>.bak.<unix-timestamp>` like every other install target.

## Adding a new hook

Drop `hooks/<name>.sh`, then add an `install_hook` call in `install_claude`
in `scripts/install.sh`, or an `install_cursor_hook` call in `install_cursor`.

The two harnesses do not share a hook protocol: Claude Code passes
`tool_name` / `tool_input` and reads `hookSpecificOutput`, Cursor passes the
event's own fields and reads `permission` / `agent_message`, and its event
names are different too. A hook meant for both handles both envelopes, the way
`codex-commit-review.sh` does.

Hook registration is idempotent — re-running install replaces the entry this
repo owns (see [Hooks](#hooks) for what counts as owned) and leaves a same-name
hook of your own alone.

## Downstream extensions

`scripts/lib/install-lib.sh` is the public extension surface. A downstream
repo that wants to layer its own rules, hooks, MCPs, or skills on top of
this install should:

1. Embed this repo as a git submodule.
2. `source <submodule>/scripts/lib/install-lib.sh` from its own
   `scripts/install.sh`.
3. Call `install_tree`, `install_file`, `remove_installed_tree`,
   `install_hook`, `install_cursor_hook`, `install_skills`,
   `install_permission_rules`, `install_teams_env`, `install_codex_subagents`,
   `install_codex_review_hook`, `install_cursor_review_hook`,
   `install_codex_review_skills`, `build_cursor_rules`, `teams_section`,
   `ensure_mcp_npm_global`, `ensure_agent_sdd`, `mcp_launch_spec`,
   `register_mcp_claude`, `register_mcp_codex`, `register_mcp_cursor`,
   `register_core_mcp_claude`, `register_core_mcp_codex`,
   `register_core_mcp_cursor`, etc. with paths inside the extension repo, and
   append its own
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
  install.sh only touches subdirs that match a name in this repo's `skills/` or
  `codex-review/skills/`, and dropping the review bundle removes only the files
  its own manifest lists.
- Rules you keep in `~/.cursor/rules/` yourself — only `<name>.mdc` files this
  repo generated are written or removed there. Cursor's account-synced User
  Rules, project `.cursor/rules/`, and `~/.cursor/plugins/` are not touched.
- `~/.codex/config.toml` — only `[mcp_servers.<name>]` and, with `--teams`,
  `features.multi_agent` (written by `codex features enable`) and
  `agents.enabled`. Everything else, including `[agents.<name>]` role
  declarations, is left untouched.
- Permissions in `~/.claude/settings.json` (`allow`/`deny`/`ask`) — this
  install.sh mutates only the `hooks` block and, with `--teams`, the `env`
  block. The `install_permission_rules` helper exists for downstream repos
  that bring their own tools; nothing else in the file is touched.
