#!/bin/bash
# search.sh — Uses OpenRouter to search .lens/ docs and return a focused summary.
# This keeps the search cost off Claude's main context entirely.
#
# Usage: search.sh <topic> <project_root>

set -euo pipefail

TOPIC="${1:-}"
PROJECT_ROOT="${2:-$(pwd)}"

if [[ -z "$TOPIC" ]]; then
  echo "search.sh: topic required" >&2
  exit 1
fi

# Bootstrap: sets OPENROUTER_API_KEY, OPENROUTER_MODEL, LENS_RAM, LENS_DISK
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/ram.sh" "$PROJECT_ROOT"

API_KEY="${OPENROUTER_API_KEY:-}"
MODEL="${OPENROUTER_MODEL:-}"
if [[ -d "$LENS_RAM" ]]; then
  LENS_DIR="$LENS_RAM"
else
  LENS_DIR="$LENS_DISK"
fi

if [[ ! -d "$LENS_DIR" ]]; then
  echo "⚠ No .lens/ directory found. Run /lens:init first." >&2
  exit 1
fi

# ─── Step 1: grep search — free, no LLM needed ───────────────────────────────
# Use bash array to safely handle paths with spaces
declare -A SEEN_DOCS
MATCHED_FILES=()

# Match by feature slug name
TOPIC_LOWER="${TOPIC,,}"
for doc in "$LENS_DIR/features"/*.md; do
  [[ -f "$doc" ]] || continue
  SLUG="${doc##*/}"
  SLUG="${SLUG%.md}"
  SLUG_LOWER="${SLUG,,}"
  if [[ "$SLUG_LOWER" == *"$TOPIC_LOWER"* ]]; then
    MATCHED_FILES+=("$doc")
    SEEN_DOCS["$doc"]=1
  fi
done

# Match by content if no filename match
if [[ ${#MATCHED_FILES[@]} -eq 0 ]]; then
  while IFS= read -r match; do
    [[ -z "$match" ]] && continue
    if [[ -z "${SEEN_DOCS[$match]+_}" ]]; then
      MATCHED_FILES+=("$match")
      SEEN_DOCS["$match"]=1
    fi
  done < <(grep -ril "$TOPIC" "$LENS_DIR/features/" 2>/dev/null || true)
fi

# Also check index for direct file→feature mapping
if [[ -f "$LENS_DIR/index.md" ]]; then
  while IFS= read -r slug; do
    [[ -z "$slug" ]] && continue
    doc="$LENS_DIR/features/$slug.md"
    if [[ -f "$doc" && -z "${SEEN_DOCS[$doc]+_}" ]]; then
      MATCHED_FILES+=("$doc")
      SEEN_DOCS["$doc"]=1
    fi
  done < <(grep -i "$TOPIC" "$LENS_DIR/index.md" 2>/dev/null | head -5 | sed 's/.*→ *//' | tr -d ' ')
fi

if [[ ${#MATCHED_FILES[@]} -eq 0 ]]; then
  echo "⚠ No .lens docs found for topic: '$TOPIC'"
  echo "  Available features: $(ls "$LENS_DIR/features/" | sed 's/\.md//' | tr '\n' ', ')"
  echo "  Run: /lens:scan <file> to generate a doc for a specific file."
  exit 0
fi

# ─── Step 2: collect matched doc content ─────────────────────────────────────
DOCS_CONTENT=""
DOC_NAMES=""

for doc in "${MATCHED_FILES[@]}"; do
  [[ -f "$doc" ]] || continue
  SLUG="${doc##*/}"
  SLUG="${SLUG%.md}"
  DOC_NAMES="$DOC_NAMES $SLUG"
  DOCS_CONTENT="$DOCS_CONTENT

=== FEATURE DOC: $SLUG ===
$(cat "$doc")
"
done

# ─── Step 3: if only one small doc, return it directly (no LLM cost) ─────────
TOTAL_LINES=$(echo "$DOCS_CONTENT" | wc -l)

if [[ $TOTAL_LINES -lt 200 ]]; then
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "[PROJECT LENS] Feature docs for: $TOPIC"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "$DOCS_CONTENT"
  exit 0
fi

# ─── Step 4: use OpenRouter to summarize when multiple/large docs ─────────────
if [[ -z "$API_KEY" ]]; then
  # No API key — just return the raw docs
  echo "$DOCS_CONTENT"
  exit 0
fi

SEARCH_PROMPT="You are a code context retrieval engine. A developer needs to work on: '$TOPIC'

Here are the relevant feature docs from this project:
$DOCS_CONTENT

Produce a focused briefing (max 150 lines) with EXACTLY these sections:

## What This Feature Does
Precise description specific to this project. No generic framework descriptions.

## Files To Read Before Touching Anything
Exact file paths in order of importance. Why each one matters.

## Key Functions / Components
Name, file location, exact signature, what it does. Every one relevant to '$TOPIC'.

## Dependencies To Know About
What this feature depends on. What depends on this feature. What breaks if you change it wrong.

## Data Flow For This Feature
Step by step, specific to '$TOPIC'. Name actual functions and variables.

## Gotchas For This Feature
Concrete warnings. Non-obvious behavior. Known issues. Things that have caused bugs before.

## What Is NOT Yet Built
Any gaps, TODOs, or placeholder code visible in the docs related to '$TOPIC'.

BANNED: vague phrases, 'standard', 'typical', 'various', 'etc.', assumptions.
If uncertain about anything: ⚠ UNCERTAIN: [what]"

RESPONSE=$(curl -s -X POST "https://openrouter.ai/api/v1/chat/completions" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -H "HTTP-Referer: https://github.com/0Serenvale/project-lens" \
  -H "X-Title: project-lens" \
  -d "$(jq -n \
    --arg model "$MODEL" \
    --arg content "$SEARCH_PROMPT" \
    '{
      model: $model,
      max_tokens: 2500,
      temperature: 0.1,
      messages: [
        {
          role: "system",
          content: "You are a code context retrieval engine. Zero vagueness. Every claim backed by what is in the docs. Flag uncertainty explicitly."
        },
        {
          role: "user",
          content: $content
        }
      ]
    }'
  )")

SUMMARY=$(echo "$RESPONSE" | jq -r '.choices[0].message.content // empty')

if [[ -z "$SUMMARY" ]]; then
  # Fallback to raw docs if LLM fails
  echo "$DOCS_CONTENT"
  exit 0
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "[PROJECT LENS] Context briefing for: $TOPIC"
echo "[PROJECT LENS] Docs searched:$DOC_NAMES"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "$SUMMARY"
exit 0
