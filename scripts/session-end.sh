#!/bin/bash
# session-end.sh — Fires on SessionEnd.
# Syncs any RAM changes (new scans during session) back to disk,
# then clears the RAM slot.

set -euo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
CWD="${CWD:-$(pwd)}"

source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/ram.sh" "$CWD"

# Nothing to do if no RAM slot exists
if [[ ! -d "$LENS_RAM" ]]; then
  exit 0
fi

# Sync RAM → disk (persist any docs generated during this session)
if [[ -d "$LENS_DISK" ]]; then
  rsync -a --update "$LENS_RAM/" "$LENS_DISK/" 2>/dev/null \
    || cp -ru "$LENS_RAM/." "$LENS_DISK/" 2>/dev/null \
    || true
fi

# Clear RAM slot — free the memory
rm -rf "$LENS_RAM"

exit 0
