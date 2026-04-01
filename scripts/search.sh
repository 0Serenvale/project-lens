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

API_KEY="${OPENROUTER_API_KEY:-}"
MODEL="${OPENROUTER_MODEL:-}"

# Read from RAM if loaded, fallback to disk
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/ram.sh" "$PROJECT_ROOT"
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
# Find matching docs by filename and content
MATCHED_FILES=""

# Match by feature slug name
for doc in "$LENS_DIR/features"/*.md; do
  [[ -f "$doc" ]] || continue
  SLUG=$(basename "$doc" .md)
  if echo "$SLUG" | grep -qi "$TOPIC"; then
    MATCHED_FILES="$MATCHED_FILES $doc"
  fi
done

# Match by content if no filename match
if [[ -z "$MATCHED_FILES" ]]; then
  CONTENT_MATCHES=$(grep -ril "$TOPIC" "$LENS_DIR/features/" 2>/dev/null || true)
  MATCHED_FILES="$CONTENT_MATCHES"
fi

# Also check index for direct file→feature mapping
if [[ -f "$LENS_DIR/index.md" ]]; then
  INDEX_MATCH=$(grep -i "$TOPIC" "$LENS_DIR/index.md" | head -5 | sed 's/.*→ *//' | tr -d ' ' || true)
  if [[ -n "$INDEX_MATCH" ]]; then
    for slug in $INDEX_MATCH; do
      [[ -f "$LENS_DIR/features/$slug.md" ]] && MATCHED_FILES="$MATCHED_FILES $LENS_DIR/features/$slug.md"
    done
  fi
fi

# Deduplicate
MATCHED_FILES=$(echo "$MATCHED_FILES" | tr ' ' '\n' | sort -u | grep -v '^$' || true)

if [[ -z "$MATCHED_FILES" ]]; then
  echo "⚠ No .lens docs found for topic: '$TOPIC'"
  echo "  Available features: $(ls "$LENS_DIR/features/" | sed 's/\.md//' | tr '\n' ', ')"
  echo "  Run: /lens:scan <file> to generate a doc for a specific file."
  exit 0
fi

# ─── Step 2: collect matched doc content ─────────────────────────────────────
DOCS_CONTENT=""
DOC_NAMES=""

while IFS= read -r doc; do
  [[ -z "$doc" || ! -f "$doc" ]] && continue
  SLUG=$(basename "$doc" .md)
  DOC_NAMES="$DOC_NAMES $SLUG"
  DOCS_CONTENT="$DOCS_CONTENT

=== FEATURE DOC: $SLUG ===
$(cat "$doc")
"
done <<< "$MATCHED_FILES"

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
