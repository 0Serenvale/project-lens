#!/bin/bash
# scan.sh — Calls OpenRouter with a cheap LLM to analyze a file and
# write/update its feature doc in .lens/features/.
#
# Usage: scan.sh <file_path> <project_root>

set -euo pipefail

FILE_PATH="${1:-}"
PROJECT_ROOT="${2:-$(pwd)}"

if [[ -z "$FILE_PATH" || ! -f "$FILE_PATH" ]]; then
  echo "scan.sh: file not found: $FILE_PATH" >&2
  exit 1
fi

# Get API key and model from plugin userConfig env vars
API_KEY="${CLAUDE_PLUGIN_OPTION_openrouter_key:-}"
MODEL="${CLAUDE_PLUGIN_OPTION_model:-deepseek/deepseek-chat}"

if [[ -z "$API_KEY" ]]; then
  echo "scan.sh: CLAUDE_PLUGIN_OPTION_openrouter_key not set. Run: /lens:init to configure." >&2
  exit 1
fi

LENS_DIR="$PROJECT_ROOT/.lens"
mkdir -p "$LENS_DIR/features"

RELATIVE_PATH="${FILE_PATH#$PROJECT_ROOT/}"
FILE_CONTENT=$(cat "$FILE_PATH")
LINE_COUNT=$(wc -l < "$FILE_PATH")

# Determine feature name from file path
# e.g. src/collections/league/Matches.ts → matches
# e.g. src/components/search/SearchBar.tsx → search
FEATURE_GUESS=$(echo "$RELATIVE_PATH" | sed 's|.*/||' | sed 's/\.[^.]*$//' | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g')

# Build the prompt
PROMPT="You are a senior software engineer analyzing a codebase file to create structured documentation.

Analyze this file and produce a concise feature doc (max 250 lines).

FILE: $RELATIVE_PATH
LINES: $LINE_COUNT

\`\`\`
$FILE_CONTENT
\`\`\`

Produce a markdown document with EXACTLY these sections — no extras:

## Feature
One sentence: what this file does and why it exists.

## Entry Points
List every exported function/class/component with a one-line description each.

## Dependencies
- Internal: other project files this imports (list file paths)
- External: npm packages used
- Globals/Config: any global state, env vars, or config it reads

## Called By
Which other parts of the codebase would typically import or use this. If unknown, say \"Unknown — run lens:init for full map\".

## Data Flow
Step-by-step: how data enters, transforms, and exits this file.

## Gotchas
Any non-obvious behavior, edge cases, known bugs, performance concerns, or things that would trip up someone unfamiliar with this code. If none, write \"None identified.\".

## Status
- [ ] Fully implemented
- [ ] Has known issues
- [ ] Needs tests
- [ ] Needs optimization
Mark whichever apply based on what you see in the code.

## Last Scanned
$(date -u +"%Y-%m-%d %H:%M UTC")

Keep each section tight. No padding. No repeated information."

# Call OpenRouter
RESPONSE=$(curl -s -X POST "https://openrouter.ai/api/v1/chat/completions" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -H "HTTP-Referer: https://github.com/0Serenvale/project-lens" \
  -H "X-Title: project-lens" \
  -d "$(jq -n \
    --arg model "$MODEL" \
    --arg content "$PROMPT" \
    '{
      model: $model,
      max_tokens: 2000,
      messages: [{role: "user", content: $content}]
    }'
  )")

# Extract the doc content
DOC=$(echo "$RESPONSE" | jq -r '.choices[0].message.content // empty')

if [[ -z "$DOC" ]]; then
  ERROR=$(echo "$RESPONSE" | jq -r '.error.message // "Unknown error"')
  echo "scan.sh: OpenRouter error: $ERROR" >&2
  exit 1
fi

# Write the feature doc
DOC_PATH="$LENS_DIR/features/$FEATURE_GUESS.md"

# If doc already exists, preserve the feature name from the header
if [[ -f "$DOC_PATH" ]]; then
  EXISTING_FEATURE=$(grep "^## Feature" "$DOC_PATH" -A1 | tail -1)
fi

cat > "$DOC_PATH" << EOF
<!-- project-lens: auto-generated. Do not edit manually. -->
<!-- file: $RELATIVE_PATH -->
<!-- model: $MODEL -->

$DOC
EOF

# Update the index.md file→feature mapping
INDEX="$LENS_DIR/index.md"
touch "$INDEX"

# Remove old entry for this file if exists
TMP=$(mktemp)
grep -v "^$RELATIVE_PATH" "$INDEX" > "$TMP" 2>/dev/null || true
echo "$RELATIVE_PATH → $FEATURE_GUESS" >> "$TMP"
sort "$TMP" > "$INDEX"
rm "$TMP"

echo "scan.sh: updated $DOC_PATH"
exit 0
