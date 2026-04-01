#!/bin/bash
# session-end.sh — SessionEnd hook.
# Syncs RAM docs back to disk, then clears the RAM slot.

set -euo pipefail

INPUT=$(cat)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || pwd)
CWD="${CWD:-$(pwd)}"

source "$SCRIPT_DIR/lib/ram.sh" "$CWD"

[[ ! -d "$LENS_RAM" ]] && exit 0

# Sync RAM → disk before clearing
if [[ -d "$LENS_DISK" ]]; then
  if command -v rsync &>/dev/null; then
    rsync -a --update "$LENS_RAM/" "$LENS_DISK/" 2>/dev/null || cp -r "$LENS_RAM/." "$LENS_DISK/"
  else
    cp -r "$LENS_RAM/." "$LENS_DISK/"
  fi
elif [[ -d "$(dirname "$LENS_DISK")" ]]; then
  # .lens/ doesn't exist yet — create it from RAM
  cp -r "$LENS_RAM" "$LENS_DISK"
fi

rm -rf "$LENS_RAM"
exit 0
