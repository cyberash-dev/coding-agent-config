# code-aget-config

Portable coding-agent setup for Claude Code and Codex CLI on macOS.

Single source of truth for personal rules and instructions; one script
symlinks them into the per-user config locations of each agent.

## Layout

```
.
├── CLAUDE.md         # entry point for Claude Code (uses @rules/* imports)
├── rules/            # canonical rule files referenced from CLAUDE.md
├── build/            # generated, gitignored
│   └── AGENTS.md     # flat file for Codex (built from CLAUDE.md + rules/)
└── scripts/
    ├── build.sh      # rebuild build/AGENTS.md
    └── install.sh    # symlink into ~/.claude and/or ~/.codex
```

`CLAUDE.md` is intentionally tiny — just a table of contents that Claude
Code expands at session start via `@rules/X.md` imports. Codex does not
understand `@import`, so `scripts/build.sh` produces a flattened
`build/AGENTS.md` with the rules inlined.

## First-time install on a new machine

```bash
git clone <this-repo> ~/Projects/code-aget-config
cd ~/Projects/code-aget-config
./scripts/install.sh all
```

Targets:

| Agent       | Target path             | Symlink source        |
|-------------|-------------------------|-----------------------|
| Claude Code | `~/.claude/CLAUDE.md`   | `CLAUDE.md`           |
| Claude Code | `~/.claude/rules`       | `rules/`              |
| Codex CLI   | `~/.codex/AGENTS.md`    | `build/AGENTS.md`     |

If anything already exists at a target path it is renamed to
`<target>.bak.<unix-timestamp>` before the symlink is created. Re-running
`install.sh` is idempotent — targets already pointing into this repo are
left alone.

## Editing rules

Edit files under `rules/` directly. Claude Code picks up changes on the
next session — no rebuild needed. For Codex, regenerate the flat file:

```bash
./scripts/build.sh
```

Re-running `./scripts/install.sh codex` does the same and ensures the
symlink is correct.

## Per-agent install

```bash
./scripts/install.sh claude   # only Claude Code
./scripts/install.sh codex    # only Codex (also runs build)
./scripts/install.sh all      # both
```

## Out of scope (for now)

Other parts of `~/.claude/` (agents/, commands/, skills/, hooks/,
settings.json) and `~/.codex/config.toml` are not managed by this repo
yet.
