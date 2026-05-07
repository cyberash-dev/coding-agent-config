#!/bin/bash
# Stdin: JSON с tool_name и tool_input.
# Stdout: hookSpecificOutput c additionalContext: reminder запустить `sdd lint`
# после Edit/Write на spec файл в SDD-проекте (проект, где найден .sdd/config.json).
input=$(cat)
tool=$(printf '%s' "$input" | jq -r '.tool_name')
path=$(printf '%s' "$input" | jq -r '.tool_input.path // .tool_input.file_path // empty')

# Триггер только на spec-файлы (markdown под /spec/).
case "$path" in
  */spec/*.md) ;;
  *) exit 0 ;;
esac

# Если нет .sdd/config.json в дереве над spec-файлом — sdd-cli не настроен, тихо.
config_dir="$(dirname "$path")"
found_config=
while [[ "$config_dir" != "/" && "$config_dir" != "." ]]; do
  if [[ -f "$config_dir/.sdd/config.json" ]]; then
    found_config=1
    break
  fi
  config_dir="$(dirname "$config_dir")"
done

if [[ -z "$found_config" ]]; then
  exit 0
fi

jq -n --arg tool "$tool" --arg path "$path" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "allow",
    additionalContext: ("Reminder: " + $path + " is a spec file in an SDD project (.sdd/config.json found). After this " + $tool + " completes, run `sdd lint` and do not proceed to Implement/Commit until exit 0. See @sdd/sdd-cli-usage.md for full phase-to-command mapping.")
  }
}'
