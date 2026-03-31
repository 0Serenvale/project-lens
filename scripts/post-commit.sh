#!/bin/bash
# post-commit.sh — Fires after every Bash tool call.
# Detects git commits and triggers OpenRouter scan on changed files.

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

# Only act on git commit commands
if ! echo "$COMMAND" | grep -qE "^git commit|git commit "; then
  exit 0
fi

# Check if .lens exists for this project (only update if initialized)
LENS_DIR="$CWD/.lens"
if [[ ! -d "$LENS_DIR" ]]; then
  exit 0
fi

# Get changed files from last commit
CHANGED=$(git -C "$CWD" diff --name-only HEAD~1 HEAD 2>/dev/null || echo "")
if [[ -z "$CHANGED" ]]; then
  exit 0
fi

# Filter to code files only
CODE_FILES=$(echo "$CHANGED" | grep -E '\.(ts|tsx|js|jsx|py|go|rs|php|rb|java|cs|vue|svelte|sql)$' || true)
if [[ -z "$CODE_FILES" ]]; then
  exit 0
fi

echo "[PROJECT LENS] Detected commit. Updating docs for changed files..."

# Run scan for each changed file
while IFS= read -r file; do
  FULL_PATH="$CWD/$file"
  if [[ -f "$FULL_PATH" ]]; then
    "${CLAUDE_PLUGIN_ROOT}/scripts/scan.sh" "$FULL_PATH" "$CWD" &
  fi
done <<< "$CODE_FILES"

# Wait for all background scans
wait

echo "[PROJECT LENS] Documentation updated."
exit 0
