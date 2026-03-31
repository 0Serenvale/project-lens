#!/bin/bash
# init.sh — First-time project scan.
# Discovers all code files, groups them by feature, runs scan.sh on each.
# Usage: init.sh <project_root>

set -euo pipefail

PROJECT_ROOT="${1:-$(pwd)}"
LENS_DIR="$PROJECT_ROOT/.lens"

API_KEY="${OPENROUTER_API_KEY:-${CLAUDE_PLUGIN_OPTION_openrouter_key:-}}"
MODEL="${OPENROUTER_MODEL:-${CLAUDE_PLUGIN_OPTION_model:-deepseek/deepseek-chat}}"

if [[ -z "$API_KEY" ]]; then
  echo "ERROR: OpenRouter key not configured." >&2
  echo "  Option 1 (global): export OPENROUTER_API_KEY=your-key in ~/.bashrc" >&2
  echo "  Option 2 (plugin): claude plugin config project-lens openrouter_key your-key" >&2
  exit 1
fi

echo "[PROJECT LENS] Initializing project at $PROJECT_ROOT..."

# Load RAM paths
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/ram.sh" "$PROJECT_ROOT"

# Write to RAM during init — session-end.sh syncs to disk
if [[ -d "/dev/shm" ]]; then
  mkdir -p "$LENS_RAM/features"
  LENS_DIR="$LENS_RAM"
  echo "[PROJECT LENS] Writing to RAM ($LENS_RAM) — will sync to disk at session end."
else
  mkdir -p "$LENS_DISK/features"
  LENS_DIR="$LENS_DISK"
fi

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
FILE_TREE=$(echo "$CODE_FILES" | head -50 | sed "s|$PROJECT_ROOT/||" | sort)

SUMMARY_PROMPT="You are a code analysis engine producing a project overview document.

BANNED phrases — using these makes your output invalid:
- \"standard\", \"typical\", \"common\", \"straightforward\", \"simple\"
- \"various\", \"several\", \"some\", \"etc.\", \"and more\", \"...\"
- \"as expected\", \"nothing unusual\", \"similar to\"

Feature modules found: $FILE_LIST

File tree:
$FILE_TREE

Produce EXACTLY this document — every section required, no vagueness:

## Project Type
Precise description: what kind of system this is, what it serves, who uses it.
Not: 'a web application'. Yes: 'A sports league management CMS built on PayloadCMS 3 + Next.js 15, serving league administrators and public visitors with match results, standings, and documents.'

## Stack
List every major technology with its exact version and its specific role in this project.
Format: Technology vX.X — role

## Architecture
Describe the actual architecture as seen in the file tree.
Name the layers, how they connect, and what owns what.
Be specific to this project — not a generic description of the framework.

## Feature Map
| Feature slug | Key files (exact paths) | What it does | Dependencies |
List every feature module found.

## Data Flow
Trace the main data path end-to-end for this specific project.
Number each step. Name actual files and functions where visible.

## Entry Points
The exact files a developer should read first to understand each major area.
Format: Area → file path → why start here

## Known Gaps
Anything missing, incomplete, or that the file tree suggests is not yet built.
If none visible: write 'None identified from file tree.'

## Last Generated
$(date -u +"%Y-%m-%d %H:%M UTC")"

SUMMARY_RESPONSE=$(curl -s -X POST "https://openrouter.ai/api/v1/chat/completions" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -H "HTTP-Referer: https://github.com/0Serenvale/project-lens" \
  -H "X-Title: project-lens" \
  -d "$(jq -n \
    --arg model "$MODEL" \
    --arg content "$SUMMARY_PROMPT" \
    '{
      model: $model,
      max_tokens: 2000,
      temperature: 0.1,
      messages: [
        {
          role: "system",
          content: "You are a code analysis engine. Zero vagueness. Every field explicit. Flag uncertainty with ⚠ UNCERTAIN."
        },
        {
          role: "user",
          content: $content
        }
      ]
    }'
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
echo "  RAM      : $LENS_DIR"
echo "  Disk     : $LENS_DISK (synced at session end)"
echo "  Overview : $LENS_DIR/overview.md"
echo "  Features : $LENS_DIR/features/ ($COUNT docs)"
echo "  Index    : $LENS_DIR/index.md"
echo ""
echo "  Docs live in RAM this session. Persisted to $LENS_DISK on exit."
echo "  Add .lens/ to .gitignore or commit it — your choice."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
exit 0
