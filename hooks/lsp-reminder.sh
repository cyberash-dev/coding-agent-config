#!/bin/bash
# Stdin: JSON с tool_name и tool_input. Stdout: hookSpecificOutput c additionalContext.
input=$(cat)
tool=$(printf '%s' "$input" | jq -r '.tool_name')
path=$(printf '%s' "$input" | jq -r '.tool_input.path // .tool_input.file_path // empty')
glob=$(printf '%s' "$input" | jq -r '.tool_input.glob // empty')
pattern=$(printf '%s' "$input" | jq -r '.tool_input.pattern // empty')

target="${path}${glob}"
case "$target" in
  *.py|*.pyi|*.go|*.ts|*.tsx|*.js|*.jsx|*.rs|*.java|*.kt|*.kts)
    ;;
  *) exit 0 ;;
esac

# Эвристика: на строковый поиск (TODO, log message, literal) LSP не поможет.
# Reminder только если pattern похож на идентификатор.
if [[ -n "$pattern" && ! "$pattern" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
  exit 0
fi

jq -n --arg tool "$tool" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "allow",
    additionalContext: ("Reminder: for semantic questions (where is X defined / who calls Y / type of Z) prefer the LSP builtin — goToDefinition, findReferences, hover, documentSymbol — over " + $tool + ". Text/literal search is fine as-is.")
  }
}'
