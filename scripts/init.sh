#!/bin/bash
# init.sh — First-time project scan.
# Discovers all code files, groups them by feature, runs scan.sh on each.
# Usage: init.sh <project_root>

set -euo pipefail

PROJECT_ROOT="${1:-$(pwd)}"
LENS_DIR="$PROJECT_ROOT/.lens"

# Load config via ram.sh (sets OPENROUTER_API_KEY, OPENROUTER_MODEL)
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/ram.sh" "$PROJECT_ROOT"
API_KEY="$OPENROUTER_API_KEY"
MODEL="$OPENROUTER_MODEL"

if [[ -z "$API_KEY" ]]; then
  echo "ERROR: OpenRouter key not configured." >&2
  echo "  Create ~/.claude/project-lens.env with:" >&2
  echo "  OPENROUTER_API_KEY=your-key" >&2
  echo "  OPENROUTER_MODEL=qwen/qwen-2.5-72b-instruct:free" >&2
  exit 1
fi

# ─── Dependency check ────────────────────────────────────────────────────────
if ! command -v jq &>/dev/null; then
  echo "[PROJECT LENS] Installing missing dependency: jq..."
  if command -v apt-get &>/dev/null; then
    sudo apt-get install -y jq 2>/dev/null || apt-get install -y jq 2>/dev/null
  elif command -v brew &>/dev/null; then
    brew install jq
  elif command -v yum &>/dev/null; then
    sudo yum install -y jq
  else
    echo "ERROR: jq is required but could not be installed automatically." >&2
    echo "  Install manually: https://jqlang.github.io/jq/download/" >&2
    exit 1
  fi
fi

echo "[PROJECT LENS] Initializing project at $PROJECT_ROOT..."

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
     -o -name "*.rb" -o -name "*.java" -o -name "*.vue" -o -name "*.svelte" \
     -o -name "*.sh" \) \
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


# Auto-create .lensignore if it doesn't exist
LENS_IGNORE="$PROJECT_ROOT/.lensignore"
if [[ ! -f "$LENS_IGNORE" ]]; then
  echo "[PROJECT LENS] Creating default .lensignore..."
  cat > "$LENS_IGNORE" << 'IGNORE_EOF'
# project-lens ignore file
# Add files or directories here to skip scanning them (e.g., UI libraries)
components/ui/
IGNORE_EOF
fi

# Filter out files matched by .lensignore
if [[ -f "$PROJECT_ROOT/.lensignore" ]]; then
  while IFS= read -r pattern || [[ -n "$pattern" ]]; do
    # Skip empty lines and comments
    [[ -z "$pattern" || "$pattern" == \#* ]] && continue
    # Convert simple glob to ERE (e.g. *.md -> .*\.md)
    # We only handle basic '*' matching for simplicity and safety across sed versions
    regex=$(echo "$pattern" | sed 's/\./\\./g' | sed 's/\*/.*/g')
    if [[ -n "$regex" ]]; then
      CODE_FILES=$(echo "$CODE_FILES" | grep -vE "$regex" || true)
    fi
  done < "$PROJECT_ROOT/.lensignore"
fi

# Clean up already scanned files that now match .lensignore
if [[ -f "$PROJECT_ROOT/.lensignore" && -f "$LENS_DIR/index.md" ]]; then
  echo "[PROJECT LENS] Cleaning up ignored files from .lens/..."
  while IFS= read -r pattern || [[ -n "$pattern" ]]; do
    [[ -z "$pattern" || "$pattern" == \#* ]] && continue
    regex=$(echo "$pattern" | sed 's/\./\\./g' | sed 's/\*/.*/g')
    if [[ -n "$regex" ]]; then
      # Find ignored files in the index
      IGNORED_IN_INDEX=$(grep -E "$regex" "$LENS_DIR/index.md" || true)
      if [[ -n "$IGNORED_IN_INDEX" ]]; then
        while IFS= read -r line; do
          # Format: path/to/file → slug
          ignored_path=$(echo "$line" | sed 's/ → .*//')
          slug=$(echo "$line" | sed 's/.* → //' | tr -d ' ')
          if [[ -f "$LENS_DIR/features/$slug.md" ]]; then
            rm -f "$LENS_DIR/features/$slug.md"
            echo "[PROJECT LENS] Removed ignored doc: $ignored_path"
          fi
        done <<< "$IGNORED_IN_INDEX"
        # Remove from index
        if sed --version 2>/dev/null | grep -q GNU; then
          sed -i -E "/$regex/d" "$LENS_DIR/index.md"
        else
          sed -i '' -E "/$regex/d" "$LENS_DIR/index.md"
        fi
      fi
    fi
  done < "$PROJECT_ROOT/.lensignore"
fi

TOTAL=$(echo "$CODE_FILES" | grep -c . || echo 0)
echo "[PROJECT LENS] Found $TOTAL code files to scan."

if (( TOTAL > 80 )); then
  echo "[PROJECT LENS] Large project detected ($TOTAL files)."
  echo "[PROJECT LENS] Prioritizing entry points and key directories."

  # For large projects: prioritize entry points, collections, routes, etc.
  # We extract them, then append the rest, so everything gets scanned eventually.
  PRIORITY_FILES=$(echo "$CODE_FILES" | grep -E '(index\.|page\.|route\.|layout\.|config\.|collections/|globals/|hooks/|providers/|api/)' || true)
  OTHER_FILES=$(echo "$CODE_FILES" | grep -vE '(index\.|page\.|route\.|layout\.|config\.|collections/|globals/|hooks/|providers/|api/)' || true)

  # Rebuild the list with priority files at the top
  CODE_FILES=$(echo -e "${PRIORITY_FILES}\n${OTHER_FILES}" | grep -v '^$')
fi

COUNT=0
TOTAL_TO_SCAN=$(echo "$CODE_FILES" | grep -c . || echo 0)

RATE_LIMITED=false

while IFS= read -r file; do
  [[ -z "$file" ]] && continue

  # Skip already-scanned files — allows resuming after rate limit
  RELATIVE="${file#$PROJECT_ROOT/}"
  SLUG=$(echo "$RELATIVE" | sed 's|.*/||' | sed 's/\.[^.]*$//' | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')
  if [[ -f "$LENS_DIR/features/$SLUG.md" ]]; then
    echo "[PROJECT LENS] [skip] Already scanned: $RELATIVE"
    COUNT=$((COUNT + 1))
    continue
  fi

  COUNT=$((COUNT + 1))
  echo "[PROJECT LENS] [$COUNT/$TOTAL_TO_SCAN] Scanning: $RELATIVE"

  "${CLAUDE_PLUGIN_ROOT}/scripts/scan.sh" "$file" "$PROJECT_ROOT"
  EXIT_CODE=$?

  if [[ $EXIT_CODE -eq 2 ]]; then
    # Rate limit hit — stop immediately, don't waste calls
    RATE_LIMITED=true
    break
  elif [[ $EXIT_CODE -ne 0 ]]; then
    echo "[PROJECT LENS] Warning: failed to scan ${file#$PROJECT_ROOT/}"
  fi

  # Small delay to avoid hitting rate limits
  sleep 0.3
done <<< "$CODE_FILES"

if [[ "$RATE_LIMITED" == true ]]; then
  echo ""
  echo "[PROJECT LENS] Stopped early due to rate limit."
  echo "[PROJECT LENS] $(ls "$LENS_DIR/features/" 2>/dev/null | wc -l | tr -d ' ') files scanned so far."
  echo "[PROJECT LENS] Run /lens:init again when the limit resets (usually midnight UTC)."
  exit 0
fi

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

# ─── Auto-add .lens/ to .gitignore ───────────────────────────────────────────
GITIGNORE="$PROJECT_ROOT/.gitignore"
if [[ -f "$GITIGNORE" ]] || git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
  touch "$GITIGNORE"
  if ! grep -qx ".lens/" "$GITIGNORE" 2>/dev/null; then
    echo "" >> "$GITIGNORE"
    echo "# project-lens generated docs" >> "$GITIGNORE"
    echo ".lens/" >> "$GITIGNORE"
    echo "[PROJECT LENS] Added .lens/ to .gitignore"
  fi
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "[PROJECT LENS] Init complete."
echo "  RAM      : $LENS_DIR"
echo "  Disk     : $LENS_DISK (synced at session end)"
echo "  Overview : $LENS_DIR/overview.md"
echo "  Features : $LENS_DIR/features/ ($COUNT docs)"
echo "  Index    : $LENS_DIR/index.md"
echo ""
echo "  Docs live in RAM. Synced to disk on session end."
echo "  .lens/ added to .gitignore automatically."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
exit 0
