#!/bin/bash
# pre-edit.sh — PreToolUse hook for Edit|Write.
# Injects feature doc + file content into Claude's context before every edit.
# Feature doc: always injected if available.
# File content: full if ≤200 lines, first+last 80 lines with summary note if larger.

set -euo pipefail

INPUT=$(cat)

# Extract fields — jq guaranteed by ram.sh
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
CWD=$(echo "$INPUT"      | jq -r '.cwd // empty')
CWD="${CWD:-$(pwd)}"

[[ -z "$FILE_PATH" ]] && exit 0

# Resolve absolute path
[[ "$FILE_PATH" != /* ]] && FILE_PATH="$CWD/$FILE_PATH"

# Skip new files and non-code files
[[ ! -f "$FILE_PATH" ]] && exit 0

EXT="${FILE_PATH##*.}"
for skip in json lock png jpg jpeg svg ico gif webp woff woff2 ttf eot mp4 mp3 pdf zip; do
  [[ "$EXT" == "$skip" ]] && exit 0
done

# Bootstrap: sets LENS_RAM, LENS_DISK, CLAUDE_PLUGIN_ROOT, checks jq/curl
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/ram.sh" "$CWD"

# Resolve lens dir: RAM first, disk fallback
if [[ -d "$LENS_RAM" ]]; then
  LENS_DIR="$LENS_RAM"
elif [[ -d "$LENS_DISK" ]]; then
  LENS_DIR="$LENS_DISK"
else
  LENS_DIR=""
fi

RELATIVE_PATH="${FILE_PATH#$CWD/}"
LINE_COUNT=$(wc -l < "$FILE_PATH")
FEATURE_DOC=""

# ─── Find best matching feature doc ──────────────────────────────────────────
if [[ -n "$LENS_DIR" && -d "$LENS_DIR/features" ]]; then
  # Check index.md first — exact file→feature mapping
  if [[ -f "$LENS_DIR/index.md" ]]; then
    FEATURE_SLUG=$(grep "^$RELATIVE_PATH →" "$LENS_DIR/index.md" 2>/dev/null | head -1 | sed 's/.*→ *//' | tr -d ' ')
    if [[ -n "$FEATURE_SLUG" && -f "$LENS_DIR/features/$FEATURE_SLUG.md" ]]; then
      FEATURE_DOC=$(cat "$LENS_DIR/features/$FEATURE_SLUG.md")
    fi
  fi

  # Fallback: match by filename slug (case-insensitive literal match, no subprocesses)
  if [[ -z "$FEATURE_DOC" ]]; then
    BEST_MATCH=""
    BEST_SCORE=0
    RELATIVE_LOWER=$(echo "$RELATIVE_PATH" | tr '[:upper:]' '[:lower:]')
    for doc in "$LENS_DIR/features"/*.md; do
      [[ -f "$doc" ]] || continue
      DOC_NAME="${doc##*/}"
      DOC_NAME="${DOC_NAME%.md}"
      DOC_LOWER=$(echo "$DOC_NAME" | tr '[:upper:]' '[:lower:]')
      if [[ "$RELATIVE_LOWER" == *"$DOC_LOWER"* ]]; then
        SCORE=${#DOC_NAME}
        if (( SCORE > BEST_SCORE )); then
          BEST_SCORE=$SCORE
          BEST_MATCH="$doc"
        fi
      fi
    done
    [[ -n "$BEST_MATCH" ]] && FEATURE_DOC=$(cat "$BEST_MATCH")
  fi
fi

# ─── Build file content section (token-aware) ─────────────────────────────────
if (( LINE_COUNT <= 200 )); then
  FILE_SECTION="## Full File Content ($LINE_COUNT lines)
$(cat "$FILE_PATH")"
else
  # Large file: inject first 80 + last 80 lines with a note
  FILE_SECTION="## File Content — $LINE_COUNT lines (showing first 80 + last 80)
⚠ File exceeds 200 lines. Run /lens:scan on this file for a complete feature doc.

### Lines 1–80
$(head -80 "$FILE_PATH")

### Lines $((LINE_COUNT - 79))–$LINE_COUNT
$(tail -80 "$FILE_PATH")"
fi

# ─── Build output ─────────────────────────────────────────────────────────────
{
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "[PROJECT LENS] Pre-edit context: $RELATIVE_PATH"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  if [[ -n "$FEATURE_DOC" ]]; then
    echo ""
    echo "## Feature Documentation"
    echo "$FEATURE_DOC"
  else
    echo ""
    echo "⚠ No feature doc found for this file. Run /lens:scan $RELATIVE_PATH to generate one."
  fi

  echo ""
  echo "$FILE_SECTION"
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "[PROJECT LENS] Read the above before making any changes."
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

exit 0
