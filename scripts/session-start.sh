#!/bin/bash
# session-start.sh — Fires on SessionStart.
# Copies .lens/ docs from disk into /dev/shm (RAM) for fast access this session.

set -euo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
CWD="${CWD:-$(pwd)}"

source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/ram.sh" "$CWD"

# Nothing to load if project has no .lens/ yet
if [[ ! -d "$LENS_DISK" ]]; then
  exit 0
fi

# Create RAM slot for this project
mkdir -p "$LENS_RAM"

# Sync disk → RAM (only copy if disk is newer than RAM)
rsync -a --update "$LENS_DISK/" "$LENS_RAM/" 2>/dev/null \
  || cp -ru "$LENS_DISK/." "$LENS_RAM/" 2>/dev/null \
  || true

# Count what was loaded
DOC_COUNT=$(find "$LENS_RAM/features" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')

if [[ "$DOC_COUNT" -gt 0 ]]; then
  echo "[PROJECT LENS] Loaded $DOC_COUNT feature docs into RAM ($LENS_RAM)"
  echo "[PROJECT LENS] Run /lens:search <topic> before editing any feature."
fi

exit 0
