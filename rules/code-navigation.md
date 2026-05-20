# Code Navigation & Exploration

Tool priority for understanding code:
1. `LSP.*` — for semantic questions when the file is in Python/Go/TS/JS/Rust/Java/Kotlin.
2. `mcp__code-skeleton__*` — file/directory structure for any supported
   language (when LSP is not configured for the project).
3. `Grep` — text search only (bare identifier, comments, string literals).
4. `Read` — when exact contents are required (before `Edit`) or the file is short.

## Read discipline
- Read a file before writing or editing it. Don't re-read a file you
  already read this session unless it changed since.
- Skip files over 100KB unless the task requires their contents; reach
  for `mcp__code-skeleton__get_outline` or a targeted `Grep` instead.

<!-- lsp:rules:start -->
## Semantic code navigation (builtin LSP)

Claude Code has a builtin `LSP` tool. Use it for semantic questions —
"where is it defined", "who calls it", "what is the type of this expression",
"what symbol is at this position" — **instead of Grep/Read**.

Operations:
- `goToDefinition(file, line, col)` — where the symbol at the position is declared.
- `findReferences(file, line, col)` — all usages of the symbol.
- `hover(file, line, col)` — signature, type, docstring.
- `documentSymbol(file)` — file outline with resolved types.
- `getDiagnostics(file)` — errors/warnings from LSP.

Decision rule:
- "Where is X defined?" → `goToDefinition`, not Grep by name.
- "Who calls Y?" → `findReferences`, not `grep -r`.
- "What is the type/signature?" → `hover`, not reading the file by hand.
- File structure, public API → `documentSymbol` (better than
  `code-skeleton.get_outline` — LSP knows resolved types).
- Searching for a string/TODO/log message/literal → Grep (LSP is not for this).
- `Read`/`Edit` are still used to modify files — LSP does not replace them.

Languages with working LSP: Python (pyright), Go (gopls), TypeScript/JavaScript
(typescript-language-server), Rust (rust-analyzer), Java (jdtls),
Kotlin (kotlin-lsp). For everything else — Grep/Read as before.
<!-- lsp:rules:end -->

<!-- code-skeleton-mcp:rules:start -->
## Code exploration (code-skeleton-mcp)

When exploring unfamiliar code, prefer these MCP tools over `Read`:

- `mcp__code-skeleton__get_outline` — structural skeleton of a file or
  directory (classes, functions, method signatures, first-line docs).
  **Default choice** when reading to *understand what's in a file* rather
  than to edit it.
- `mcp__code-skeleton__get_function` — body of one function or method by
  dotted path (e.g. `ClassName.method`, `outer.inner.fn`). Returns all
  `variants[]` for Python `@overload`.
- `mcp__code-skeleton__get_class` — class / interface / struct with method
  signatures (pass `include_bodies: true` for full bodies).
- `mcp__code-skeleton__get_imports` — imports with `isStdlib` /
  `isThirdParty` / `isRelative` flags and best-effort path resolution.

Decision rule:
- File > 200 lines AND goal is to understand structure → start with
  `get_outline`, not `Read`.
- Need exactly one function body → `get_function` instead of `Read` with
  offset/limit.
- About to edit → use `Read` (`Edit` needs exact line content).
- File < 100 lines → `Read` is fine, outline adds little.

Supported languages: Python, Go, TypeScript, JavaScript, TSX. Other
languages fall back to `Read`.
<!-- code-skeleton-mcp:rules:end -->
