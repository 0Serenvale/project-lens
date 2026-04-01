#!/bin/bash
# session-start.sh — SessionStart hook.
# Copies .lens/ from disk into RAM (/dev/shm) for fast access this session.

set -euo pipefail

INPUT=$(cat)

# Bootstrap ram.sh — also installs jq/curl if missing
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/ram.sh" "$(echo "$INPUT" | jq -r '.cwd // empty' || pwd)"

[[ -z "${CWD:-}" ]] && CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
CWD="${CWD:-$(pwd)}"

# Re-source with correct CWD now that jq is guaranteed
source "$SCRIPT_DIR/lib/ram.sh" "$CWD"

# Nothing to load if project has no .lens/ yet
if [[ ! -d "$LENS_DISK" ]]; then
  exit 0
fi

mkdir -p "$LENS_RAM"

# cp -r is primary (universal). rsync used if available for faster delta sync.
if command -v rsync &>/dev/null; then
  rsync -a --update "$LENS_DISK/" "$LENS_RAM/" 2>/dev/null || cp -r "$LENS_DISK/." "$LENS_RAM/"
else
  cp -r "$LENS_DISK/." "$LENS_RAM/"
fi

DOC_COUNT=$(find "$LENS_RAM/features" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')

if [[ "$DOC_COUNT" -gt 0 ]]; then
  echo "[PROJECT LENS] $DOC_COUNT feature docs loaded into RAM. Use /lens:search <topic> before editing."
fi

exit 0
