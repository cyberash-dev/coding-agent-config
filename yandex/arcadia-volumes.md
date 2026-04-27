# Arcadia Volumes (FUSE)

`~/arcadia-volumes/` and its top-level subdirectories are FUSE-mounted virtual
monorepo volumes. Broad searches will hang indefinitely or trigger massive
network fetches.

- NEVER run Glob, Grep, find, ls, rg, or any recursive/broad search from
  `~/arcadia-volumes/` or `~/arcadia-volumes/*/`
- Always target a specific deep subdirectory
  (e.g. `~/arcadia-volumes/junk/logbroker/docs/concepts/`), never a shallow root
- For global code search across Arcadia → `mcp__arc-mcp__search-code`,
  not local search tools
- For internal service docs → `mcp__ya-docs-mcp__*`, not manual reads from
  `~/arcadia-volumes/junk/`
