#!/bin/bash
# init.sh — First-time project scan.
# Discovers all code files, groups them by feature, runs scan.sh on each.
# Usage: init.sh <project_root>

set -euo pipefail

PROJECT_ROOT="${1:-$(pwd)}"
LENS_DIR="$PROJECT_ROOT/.lens"

API_KEY="${CLAUDE_PLUGIN_OPTION_openrouter_key:-}"
MODEL="${CLAUDE_PLUGIN_OPTION_model:-deepseek/deepseek-chat}"

if [[ -z "$API_KEY" ]]; then
  echo "ERROR: OpenRouter key not configured." >&2
  echo "Run: claude plugin config project-lens openrouter_key <your-key>" >&2
  exit 1
fi

echo "[PROJECT LENS] Initializing project at $PROJECT_ROOT..."
mkdir -p "$LENS_DIR/features"

# Find all code files (skip node_modules, .git, dist, build, .next, generated)
CODE_FILES=$(find "$PROJECT_ROOT" -type f \
  \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" \
     -o -name "*.py" -o -name "*.go" -o -name "*.rs" -o -name "*.php" \
     -o -name "*.rb" -o -name "*.java" -o -name "*.vue" -o -name "*.svelte" \) \
  -not -path "*/node_modules/*" \
  -not -path "*/.git/*" \
  -not -path "*/dist/*" \
  -not -path "*/build/*" \
  -not -path "*/.next/*" \
  -not -path "*/coverage/*" \
  -not -path "*/.turbo/*" \
  -not -name "*.d.ts" \
  -not -name "*.generated.*" \
  -not -name "payload-types.ts" \
  2>/dev/null)

TOTAL=$(echo "$CODE_FILES" | grep -c . || echo 0)
echo "[PROJECT LENS] Found $TOTAL code files to scan."

if (( TOTAL > 80 )); then
  echo "[PROJECT LENS] Large project detected ($TOTAL files)."
  echo "[PROJECT LENS] Scanning top-level entry points and key directories only."
  echo "[PROJECT LENS] Run '/lens:scan <file>' on specific files for deeper docs."

  # For large projects: prioritize entry points, collections, components, routes
  CODE_FILES=$(echo "$CODE_FILES" | grep -E \
    '(index\.|page\.|route\.|layout\.|config\.|collections/|globals/|components/|hooks/|providers/|api/)' \
    | head -60 || echo "$CODE_FILES" | head -60)
fi

COUNT=0
TOTAL_TO_SCAN=$(echo "$CODE_FILES" | grep -c . || echo 0)

while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  COUNT=$((COUNT + 1))
  echo "[PROJECT LENS] [$COUNT/$TOTAL_TO_SCAN] Scanning: ${file#$PROJECT_ROOT/}"
  "${CLAUDE_PLUGIN_ROOT}/scripts/scan.sh" "$file" "$PROJECT_ROOT" 2>/dev/null || \
    echo "[PROJECT LENS] Warning: failed to scan $file"
  # Small delay to avoid rate limiting
  sleep 0.3
done <<< "$CODE_FILES"

# Generate project summary doc
echo "[PROJECT LENS] Generating project overview..."

FILE_LIST=$(ls "$LENS_DIR/features/" 2>/dev/null | sed 's/\.md$//' | sort | tr '\n' ', ')

SUMMARY_PROMPT="Based on a codebase with these feature modules: $FILE_LIST

And this file tree sample:
$(echo "$CODE_FILES" | head -30 | sed "s|$PROJECT_ROOT/||")

Write a concise project overview (max 100 lines) with:
## Project Type
What kind of project this is (CMS, API, frontend app, etc.)

## Architecture
Key architectural decisions visible from the file structure.

## Feature Map
Table: Feature | Key Files | Purpose

## Workflow
How the main data flows through the system end-to-end.

## Entry Points
The main files to start reading to understand the project."

SUMMARY_RESPONSE=$(curl -s -X POST "https://openrouter.ai/api/v1/chat/completions" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -H "HTTP-Referer: https://github.com/0Serenvale/project-lens" \
  -H "X-Title: project-lens" \
  -d "$(jq -n \
    --arg model "$MODEL" \
    --arg content "$SUMMARY_PROMPT" \
    '{model: $model, max_tokens: 1500, messages: [{role: "user", content: $content}]}'
  )")

SUMMARY=$(echo "$SUMMARY_RESPONSE" | jq -r '.choices[0].message.content // "Could not generate summary."')

cat > "$LENS_DIR/overview.md" << EOF
<!-- project-lens: auto-generated overview -->
<!-- generated: $(date -u +"%Y-%m-%d %H:%M UTC") -->
<!-- model: $MODEL -->

$SUMMARY
EOF

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "[PROJECT LENS] Init complete."
echo "  Overview : $LENS_DIR/overview.md"
echo "  Features : $LENS_DIR/features/ ($COUNT docs)"
echo "  Index    : $LENS_DIR/index.md"
echo ""
echo "  Add .lens/ to .gitignore or commit it — your choice."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
exit 0
