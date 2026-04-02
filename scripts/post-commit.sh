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
# Filter against .lensignore
if [[ -f "$CWD/.lensignore" ]]; then
  while IFS= read -r pattern || [[ -n "$pattern" ]]; do
    [[ -z "$pattern" || "$pattern" == \#* ]] && continue
    regex=$(echo "$pattern" | sed 's/\./\\./g' | sed 's/\*/.*/g')
    if [[ -n "$regex" ]]; then
      CODE_FILES=$(echo "$CODE_FILES" | grep -vE "$regex" || true)
    fi
  done < "$CWD/.lensignore"
fi

if [[ -z "$CODE_FILES" ]]; then
  exit 0
fi

FILE_COUNT=$(echo "$CODE_FILES" | grep -c . || echo 0)
echo "[PROJECT LENS] Detected commit. Updating docs for $FILE_COUNT changed file(s) (sequential to respect rate limits)..."

# Run scans sequentially — parallel spawning causes rate limit floods on large commits
SCANNED=0
while IFS= read -r file; do
  FULL_PATH="$CWD/$file"
  if [[ -f "$FULL_PATH" ]]; then
    "${CLAUDE_PLUGIN_ROOT}/scripts/scan.sh" "$FULL_PATH" "$CWD"
    EXIT_CODE=$?
    if [[ $EXIT_CODE -eq 2 ]]; then
      echo "[PROJECT LENS] Rate limit reached — stopping. $SCANNED/$FILE_COUNT files updated."
      echo "[PROJECT LENS] Run /lens:update when the limit resets (usually midnight UTC)."
      exit 0
    fi
    SCANNED=$((SCANNED + 1))
  fi
done <<< "$CODE_FILES"

echo "[PROJECT LENS] Documentation updated ($SCANNED file(s))."
exit 0
