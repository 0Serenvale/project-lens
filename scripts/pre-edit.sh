#!/bin/bash
# pre-edit.sh — Fires before every Edit/Write tool call.
# Reads the target file path, finds the matching .lens feature doc,
# and injects its content + the full file content into Claude's context.
# Claude receives this as already-read context — nothing to skip.

set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

# Nothing to do if no file path
if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

# Resolve absolute path
if [[ "$FILE_PATH" != /* ]]; then
  FILE_PATH="$CWD/$FILE_PATH"
fi

# Skip if file doesn't exist yet (new file creation)
if [[ ! -f "$FILE_PATH" ]]; then
  exit 0
fi

# Skip non-code files
EXT="${FILE_PATH##*.}"
SKIP_EXTS="json lock png jpg svg ico gif webp woff woff2 ttf eot mp4 mp3 pdf zip"
for skip in $SKIP_EXTS; do
  if [[ "$EXT" == "$skip" ]]; then
    exit 0
  fi
done

# Resolve RAM path — fast read from /dev/shm if loaded, fallback to disk
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/ram.sh" "$CWD"
LENS_DIR="${LENS_RAM:-$LENS_DISK}"
[[ -d "$LENS_DIR" ]] || LENS_DIR="$LENS_DISK"

FEATURE_DOC=""
OUTPUT=""

# --- Inject feature doc if it exists ---
if [[ -d "$LENS_DIR/features" ]]; then
  # Find the most relevant feature doc by matching file path fragments
  RELATIVE_PATH="${FILE_PATH#$CWD/}"
  BEST_MATCH=""
  BEST_SCORE=0

  # Check if the file path contains the feature name or vice versa
  shopt -s nocasematch
  for doc in "$LENS_DIR/features"/*.md; do
    [[ -f "$doc" ]] || continue
    DOC_NAME="${doc##*/}"
    DOC_NAME="${DOC_NAME%.md}"
    if [[ "$RELATIVE_PATH" =~ $DOC_NAME ]]; then
      SCORE=${#DOC_NAME}
      if (( SCORE > BEST_SCORE )); then
        BEST_SCORE=$SCORE
        BEST_MATCH="$doc"
      fi
    fi
  done
  shopt -u nocasematch

  # Also check index.md for file→feature mapping
  if [[ -f "$LENS_DIR/index.md" ]] && grep -q "$RELATIVE_PATH" "$LENS_DIR/index.md" 2>/dev/null; then
    FEATURE_NAME=$(grep "$RELATIVE_PATH" "$LENS_DIR/index.md" | head -1 | sed 's/.*→ *//;s/ .*//')
    if [[ -n "$FEATURE_NAME" && -f "$LENS_DIR/features/$FEATURE_NAME.md" ]]; then
      BEST_MATCH="$LENS_DIR/features/$FEATURE_NAME.md"
    fi
  fi

  if [[ -n "$BEST_MATCH" ]]; then
    FEATURE_DOC=$(cat "$BEST_MATCH")
  fi
fi

# --- Count file lines ---
LINE_COUNT=$(wc -l < "$FILE_PATH")

# --- Build context output ---
OUTPUT="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[PROJECT LENS] Pre-edit context for: ${FILE_PATH#$CWD/}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ -n "$FEATURE_DOC" ]]; then
  OUTPUT="$OUTPUT

## Feature Documentation
$FEATURE_DOC"
fi

OUTPUT="$OUTPUT

## Full File Content ($LINE_COUNT lines)
$(cat "$FILE_PATH")"

if [[ -n "$FEATURE_DOC" || $LINE_COUNT -gt 0 ]]; then
  OUTPUT="$OUTPUT

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[PROJECT LENS] Read the above completely before making any changes.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
fi

echo "$OUTPUT"
exit 0
