#!/bin/bash
# Stdin: JSON с tool_name и tool_input. Stdout: hookSpecificOutput c additionalContext.
# Две ветки:
#   Read  → подсказка про mcp__code-skeleton__* (структурный обзор)
#   Grep  → подсказка про builtin LSP (семантика по идентификатору)
[[ "$CODE_NAV_REMINDER_DISABLED" == "1" ]] && exit 0
input=$(cat)
tool=$(printf '%s' "$input" | jq -r '.tool_name')
path=$(printf '%s' "$input" | jq -r '.tool_input.path // .tool_input.file_path // empty')
glob=$(printf '%s' "$input" | jq -r '.tool_input.glob // empty')
pattern=$(printf '%s' "$input" | jq -r '.tool_input.pattern // empty')

emit() {
  jq -n --arg msg "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "allow",
      additionalContext: $msg
    }
  }'
}

case "$tool" in
  Read)
    # code-skeleton-mcp поддерживает: Python, Go, TS, TSX, JS, JSX.
    case "$path" in
      *.py|*.pyi|*.go|*.ts|*.tsx|*.js|*.jsx) ;;
      *) exit 0 ;;
    esac
    emit "Reminder: if you're reading this file to understand its structure (file >200 lines, want an outline, one function body, or class signatures), prefer mcp__code-skeleton__get_outline / get_function / get_class over Read. Use Read when you're about to Edit (needs exact line content) or the file is small (<100 lines)."
    ;;
  Grep)
    # LSP-only языки rs/java/kt тоже учитываем — это про семантику, не про outline.
    case "$glob" in
      *.py|*.pyi|*.go|*.ts|*.tsx|*.js|*.jsx|*.rs|*.java|*.kt|*.kts) ;;
      *) exit 0 ;;
    esac
    # На строковый поиск (TODO, log message, literal) LSP не поможет.
    # Reminder только если pattern похож на идентификатор.
    if [[ -n "$pattern" && ! "$pattern" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
      exit 0
    fi
    emit "Reminder: for semantic questions (where is X defined / who calls Y / type of Z) prefer the LSP builtin — goToDefinition, findReferences, hover, documentSymbol — over Grep. Text/literal search is fine as-is."
    ;;
  *) exit 0 ;;
esac
