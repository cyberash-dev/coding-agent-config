# arc-mcp (Arcanum integration)

MCP server for Arcanum (code review) and global Arcadia code search.
Tool names and parameters are in the MCP schema — these are usage rules.

## When to use
- **Global code search** across the Arcadia monorepo → `mcp__arc-mcp__search-code`.
  NEVER use Grep, Glob, find, or rg for global searches — the working copy is
  FUSE-mounted and broad searches will hang or fetch massive amounts of data.
- **PR / code review** workflows → use `mcp__arc-mcp__get-pr-*` and
  `get-review-comments` instead of parsing `arc pr view` output by hand.

## When NOT to use
- Local search **inside the current project directory** — ordinary Grep/Glob
  is faster and fine.
