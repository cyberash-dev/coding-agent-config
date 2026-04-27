#!/bin/bash
# PreToolUse hook: block broad searches from arcadia-volumes roots.
# Stdin format: {"tool_name":"Glob","tool_input":{"path":"/...","pattern":"..."}, ...}

INPUT=$(cat)
AV_EXPANDED="$HOME/arcadia-volumes"

# Paths (relative to arcadia-volumes/) where depth 2 is sufficient.
# Everything else requires depth 3.
SHALLOW_OK_PREFIXES=(
  "payoffline/pay"
  "payoffline/wallet"
)

check_path() {
  local path="$1"
  path="${path/#\~/$HOME}"

  if [[ "$path" != "$AV_EXPANDED"* ]]; then
    return 0
  fi

  local relative="${path#$AV_EXPANDED}"
  relative="${relative#/}"

  # Check if path falls under a shallow-ok prefix
  local min_depth=3
  for prefix in "${SHALLOW_OK_PREFIXES[@]}"; do
    if [[ "$relative" == "$prefix"/* || "$relative" == "$prefix" ]]; then
      min_depth=2
      break
    fi
  done

  local depth=0
  IFS='/' read -ra PARTS <<< "$relative"
  for part in "${PARTS[@]}"; do
    if [[ -n "$part" ]]; then
      ((depth++))
    fi
  done

  if [[ $depth -lt $min_depth ]]; then
    echo "{\"decision\":\"block\",\"reason\":\"BLOCKED: Broad search in arcadia-volumes (FUSE mount). Target a deeper subdirectory (${min_depth}+ levels for this volume).\"}"
    exit 0
  fi
}

# Extract paths from the hook JSON (tool_input is nested)
PATHS=$(echo "$INPUT" | python3 -c "
import sys, json, re, os
try:
    data = json.load(sys.stdin)
    tool_input = data.get('tool_input', {})
    av = os.path.expanduser('~/arcadia-volumes')
    # Direct path fields from tool_input
    for key in ('path', 'file_path'):
        v = tool_input.get(key, '')
        if v:
            print(v)
    # For Bash commands, extract arcadia-volumes paths from command string
    cmd = tool_input.get('command', '')
    if cmd:
        for pattern in [r'~/arcadia-volumes[/\w.*-]*', re.escape(av) + r'[/\w.*-]*']:
            for match in re.findall(pattern, cmd):
                print(match)
except:
    pass
" 2>/dev/null)

if [[ -n "$PATHS" ]]; then
  while IFS= read -r p; do
    if [[ -n "$p" ]]; then
      check_path "$p"
    fi
  done <<< "$PATHS"
fi
