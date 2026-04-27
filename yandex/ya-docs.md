# Internal Service Documentation (ya-docs-mcp)

MCP server for internal Yandex service docs. Tool names are in the schema —
these are usage rules.

## When to use
- Looking up internal service behavior (TVM tickets, deploy pods, logbroker
  concepts, etc.) → start with `mcp__ya-docs-mcp__search-docs`
- Browsing a service's docs → `mcp__ya-docs-mcp__list-docs`
- Reading a known doc → `mcp__ya-docs-mcp__read-doc`

## When NOT to use
- Do NOT read docs manually from `~/arcadia-volumes/junk/` — always use the
  MCP tools (FUSE volume, broad reads will hang)

Available services: `deploy`, `blackbox`, `tvm`, `logbroker`, `unified-agent`,
`load-testing`, `ci`.
