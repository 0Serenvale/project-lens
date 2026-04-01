#!/bin/bash
# scan.sh — Calls OpenRouter LLM to analyze a file and write a structured
# feature doc in .lens/features/. The prompt is engineered to eliminate
# every shortcut a lazy LLM (or Claude) would normally take.
#
# Usage: scan.sh <file_path> <project_root>

set -euo pipefail

FILE_PATH="${1:-}"
PROJECT_ROOT="${2:-$(pwd)}"

if [[ -z "$FILE_PATH" || ! -f "$FILE_PATH" ]]; then
  echo "scan.sh: file not found: $FILE_PATH" >&2
  exit 1
fi

# Load config + RAM paths (ram.sh sets OPENROUTER_API_KEY and OPENROUTER_MODEL)
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/ram.sh" "$PROJECT_ROOT"
API_KEY="$OPENROUTER_API_KEY"
MODEL="$OPENROUTER_MODEL"

if [[ -z "$API_KEY" ]]; then
  echo "scan.sh: no OpenRouter key found." >&2
  echo "  Add to ~/.claude/project-lens.env:" >&2
  echo "  OPENROUTER_API_KEY=your-key" >&2
  exit 1
fi

# Write to RAM if available, disk as fallback
# session-end.sh will sync RAM → disk at end of session
if [[ -d "/dev/shm" || -d "$LENS_RAM" ]]; then
  mkdir -p "$LENS_RAM/features"
  LENS_DIR="$LENS_RAM"
else
  mkdir -p "$LENS_DISK/features"
  LENS_DIR="$LENS_DISK"
fi

RELATIVE_PATH="${FILE_PATH#$PROJECT_ROOT/}"
FILE_CONTENT=$(cat "$FILE_PATH")
LINE_COUNT=$(wc -l < "$FILE_PATH")
SCAN_DATE=$(date -u +"%Y-%m-%d %H:%M UTC")

# Derive feature slug from file path
# src/collections/league/Matches.ts      → matches
# src/components/search/SearchBar.tsx    → search-bar
# src/app/(frontend)/page.tsx            → page-frontend
FEATURE_SLUG=$(echo "$RELATIVE_PATH" \
  | sed 's|.*/||' \
  | sed 's/\.[^.]*$//' \
  | tr '[:upper:]' '[:lower:]' \
  | sed 's/[^a-z0-9]/-/g' \
  | sed 's/--*/-/g' \
  | sed 's/^-//;s/-$//')

# ─── Hardened prompt ──────────────────────────────────────────────────────────
# This prompt is engineered to push every shortcut, assumption, and lazy summary
# back onto the LLM as a required explicit field.
# The things Claude skips become mandatory output fields.
# ──────────────────────────────────────────────────────────────────────────────
read -r -d '' PROMPT_TEMPLATE << 'PROMPT_EOF' || true
You are a code analysis engine. Your job is to produce a complete, precise, zero-assumption feature document for a single source file.

RULES — violating any rule makes your output invalid:

1. NEVER write vague phrases. These are BANNED:
   - "standard implementation", "typical pattern", "as expected"
   - "nothing unusual", "similar to X", "handles X appropriately"
   - "various", "several", "some", "etc.", "and more", "..."
   - "straightforward", "simple", "basic", "common"

2. EVERY import must be listed explicitly — no grouping, no omissions.

3. EVERY exported symbol must be documented — no skipping "minor" exports.

4. EVERY conditional branch must be named — what triggers it, what it does.

5. EVERY place data can be null, undefined, empty, or invalid must be flagged.

6. If you are UNCERTAIN about something, write it explicitly as:
   ⚠ UNCERTAIN: [what you're unsure about]
   Never silently guess.

7. If a section has nothing to report, write "None." — never leave a section empty.

Now analyze this file:

FILE: {{RELATIVE_PATH}}
LINES: {{LINE_COUNT}}
SCANNED: {{SCAN_DATE}}

Produce EXACTLY this document structure — every section required:

---

## Purpose
One precise sentence: what this file does, why it exists, and what breaks if it is removed.

## Exports
List every exported symbol (function, class, component, constant, type, interface).
For each:
- Name, type (function/class/component/const/type)
- Exact signature (parameters with types, return type)
- One-line description of what it does
- Side effects (if any): DB calls, API calls, state mutations, file writes

## Imports — Internal
Every import from within the project (not node_modules).
For each: exact import path → what is used from it → why this file needs it.
If none: write "None."

## Imports — External
Every import from node_modules.
For each: package name → what is imported → why.
If none: write "None."

## Imports — Framework / Config
Any framework primitives, config files, env vars, or globals this file reads.
For each: name → what it provides → where it comes from.
If none: write "None."

## Called By
Every other file in the project that would import or use this file's exports.
Be explicit — list file paths if visible from imports/naming conventions.
If cannot be determined from this file alone: write "⚠ UNCERTAIN: requires full project scan — run /lens:init"

## Data Flow
Number each step. Trace exactly how data enters, transforms, and exits.
Include: input source → validation → transformation → output destination.
Every branch that changes the flow must be on its own numbered step.
Example:
1. Input: `req.user` from Payload auth middleware — can be null if unauthenticated
2. Branch: if user is null → returns { visibility: { equals: 'PUBLIC' } }
3. Branch: if user.role in ADMIN_ROLES → returns true (unrestricted access)
4. Default: returns { visibility: { not_in: ['ADMIN_ONLY'] } }

## Conditional Logic
List every if/else, switch, ternary, and optional chain (?.) that changes behavior.
For each: condition → what happens when true → what happens when false/missing.
If none: write "None."

## Null / Undefined / Empty Risks
Every place in this file where a value could be null, undefined, empty array, or zero.
For each: variable name → where it comes from → what happens if it's missing → is it handled?
If none: write "None."

## Side Effects
Everything this file does beyond returning a value:
- Database reads or writes
- API calls (internal or external)
- File system operations
- Cache invalidation
- Event emissions
- State mutations
If none: write "None."

## Gotchas
Non-obvious behavior that would trip up someone unfamiliar with this file.
Things that look like bugs but aren't. Things that ARE bugs. Performance traps.
Ordering dependencies. Race conditions. Anything surprising.
Each gotcha must be a concrete statement, not a vague warning.
If none: write "None."

## Status
Check all that apply — be honest based on what you actually see in the code:
- [ ] Fully implemented — all logic complete, no TODOs
- [ ] Has TODOs or incomplete sections — list them
- [ ] Has known bugs — describe them
- [ ] Missing error handling — where?
- [ ] Missing input validation — where?
- [ ] Performance concerns — what and where?
- [ ] No tests visible — (note: test files are separate)
- [ ] Needs refactoring — why?

---
PROMPT_EOF

# Substitute safe placeholders (metadata only — file content passed separately to jq)
PROMPT_TEMPLATE="${PROMPT_TEMPLATE//\{\{RELATIVE_PATH\}\}/$RELATIVE_PATH}"
PROMPT_TEMPLATE="${PROMPT_TEMPLATE//\{\{LINE_COUNT\}\}/$LINE_COUNT}"
PROMPT_TEMPLATE="${PROMPT_TEMPLATE//\{\{SCAN_DATE\}\}/$SCAN_DATE}"

# ─── Call OpenRouter ──────────────────────────────────────────────────────────
# FILE_CONTENT passed as --arg to jq so it is safely JSON-encoded.
# The prompt template and file content are concatenated inside jq — no bash substitution on untrusted content.
RESPONSE=$(curl -s -X POST "https://openrouter.ai/api/v1/chat/completions" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -H "HTTP-Referer: https://github.com/0Serenvale/project-lens" \
  -H "X-Title: project-lens" \
  -d "$(jq -n \
    --arg model "$MODEL" \
    --arg prompt "$PROMPT_TEMPLATE" \
    --arg fileContent "$FILE_CONTENT" \
    '{
      model: $model,
      max_tokens: 3000,
      temperature: 0.1,
      messages: [
        {
          role: "system",
          content: "You are a code analysis engine. You produce structured documentation with zero vagueness. You never skip fields. You never use filler phrases. You flag uncertainty explicitly."
        },
        {
          role: "user",
          content: ($prompt + "\n\n```\n" + $fileContent + "\n```")
        }
      ]
    }'
  )")

# ─── Extract and validate response ───────────────────────────────────────────
DOC=$(echo "$RESPONSE" | jq -r '.choices[0].message.content // empty')

if [[ -z "$DOC" ]]; then
  ERROR=$(echo "$RESPONSE" | jq -r '.error.message // "Unknown error"')

  # Rate limit — stop everything, don't waste more calls
  if echo "$ERROR" | grep -qi "rate limit\|per.day\|quota\|limit exceeded"; then
    echo "" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "[PROJECT LENS] Rate limit reached for model: $MODEL" >&2
    echo "[PROJECT LENS] Stopped at: $RELATIVE_PATH" >&2
    echo "[PROJECT LENS] Scanned so far: $(ls "$LENS_DIR/features/" 2>/dev/null | wc -l | tr -d ' ') files" >&2
    echo "[PROJECT LENS] Run /lens:init again when the limit resets (usually midnight UTC)." >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    exit 2  # Exit code 2 = rate limit signal to init.sh
  fi

  echo "scan.sh: OpenRouter error for $RELATIVE_PATH: $ERROR" >&2
  exit 1
fi

# Basic validation — check required sections are present
MISSING=""
for section in "## Purpose" "## Exports" "## Imports" "## Data Flow" "## Gotchas" "## Status"; do
  if ! echo "$DOC" | grep -q "^$section"; then
    MISSING="$MISSING $section"
  fi
done

if [[ -n "$MISSING" ]]; then
  echo "scan.sh: WARNING — response missing sections:$MISSING" >&2
  echo "scan.sh: Writing doc anyway but quality may be degraded." >&2
fi

# ─── Write feature doc ────────────────────────────────────────────────────────
DOC_PATH="$LENS_DIR/features/$FEATURE_SLUG.md"

cat > "$DOC_PATH" << EOF
<!-- project-lens auto-generated — do not edit manually -->
<!-- file: $RELATIVE_PATH -->
<!-- model: $MODEL -->
<!-- scanned: $SCAN_DATE -->

$DOC
EOF

# ─── Update index ─────────────────────────────────────────────────────────────
INDEX="$LENS_DIR/index.md"
touch "$INDEX"

TMP=$(mktemp)
grep -v "^$RELATIVE_PATH" "$INDEX" > "$TMP" 2>/dev/null || true
echo "$RELATIVE_PATH → $FEATURE_SLUG" >> "$TMP"
sort "$TMP" > "$INDEX"
rm "$TMP"

echo "scan.sh: ✓ $RELATIVE_PATH → $DOC_PATH"
exit 0
