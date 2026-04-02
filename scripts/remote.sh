#!/bin/bash
# remote.sh — Targeted extraction from a remote repository.
# Clones a repo, finds files relevant to a topic, and runs the chunked scan.sh.
# Usage: remote.sh <github_url> <target_concept>

set -euo pipefail

REPO_URL="${1:-}"
TOPIC="${2:-}"

if [[ -z "$REPO_URL" || -z "$TOPIC" ]]; then
  echo "Usage: remote.sh <github_url> <target_concept>" >&2
  # exit
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/ram.sh" "$(pwd)"

API_KEY="$OPENROUTER_API_KEY"
if [[ -z "$API_KEY" ]]; then
  echo "ERROR: OpenRouter key not configured. Cannot perform remote scan." >&2
  exit 1
fi

# Create a stable tmp dir for this repo
REPO_NAME=$(basename "$REPO_URL" .git)
TMP_DIR="/tmp/project-lens-remote/$REPO_NAME"

echo "[PROJECT LENS] Fetching remote repository: $REPO_NAME..."
if [[ ! -d "$TMP_DIR" ]]; then
  mkdir -p "/tmp/project-lens-remote"
  git clone --depth 1 "$REPO_URL" "$TMP_DIR" 2>/dev/null || true
else
  # Update if it exists
  git -C "$TMP_DIR" pull --rebase 2>/dev/null || true
fi

if [[ ! -d "$TMP_DIR" ]]; then
  echo "ERROR: Failed to clone repository." >&2
  exit 1
fi

echo "[PROJECT LENS] Searching repository for topic: '$TOPIC'..."

# Create a minimal .lensignore so we don't accidentally match build artifacts
cat > "$TMP_DIR/.lensignore" << 'IGNORE_EOF'
node_modules/
dist/
build/
.next/
coverage/
IGNORE_EOF

# 1. Use an LLM call to get a list of search keywords based on the topic
KEYWORDS_PROMPT="I need to find files in a codebase related to the following topic: '$TOPIC'
Provide a list of 5 single-word search terms (grep keywords) I should use to find relevant files.
Output ONLY the keywords, separated by spaces. No markdown, no punctuation."

KEYWORDS_RESPONSE=$(curl -s -X POST "https://openrouter.ai/api/v1/chat/completions" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -H "HTTP-Referer: https://github.com/0Serenvale/project-lens" \
  -H "X-Title: project-lens" \
  -d "$(jq -n \
    --arg model "$OPENROUTER_MODEL" \
    --arg prompt "$KEYWORDS_PROMPT" \
    '{
      model: $model,
      max_tokens: 50,
      temperature: 0.1,
      messages: [
        {role: "user", content: $prompt}
      ]
    }'
  )")

KEYWORDS=$(echo "$KEYWORDS_RESPONSE" | jq -r '.choices[0].message.content // empty' | tr -d '",.' | tr '\n' ' ')

if [[ -z "$KEYWORDS" ]]; then
  # Fallback to the topic words
  KEYWORDS=$(echo "$TOPIC" | tr ' ' '\n' | grep -vE '^(how|to|in|the|a|an|and|or|for|with)$' | tr '\n' ' ')
fi

echo "[PROJECT LENS] Generated search keywords: $KEYWORDS"

# 2. Find files matching these keywords
MATCHED_FILES=""
for word in $KEYWORDS; do
  if [[ -n "$word" ]]; then
    # Search file contents and paths
    FOUND=$(grep -ril "$word" "$TMP_DIR" 2>/dev/null | grep -v "/\.git/" || true)
    MATCHED_FILES="$MATCHED_FILES\n$FOUND"
  fi
done

# 3. Filter to code files, deduplicate, and take the top 5 most relevant
CODE_FILES=$(echo -e "$MATCHED_FILES" | grep -E '\.(ts|tsx|js|jsx|py|go|rs|php|rb|java|cs|vue|svelte)$' | grep -vE '(node_modules/|dist/|build/)' | sort | uniq -c | sort -nr | awk '{print $2}' | head -5 || true)

if [[ -z "$CODE_FILES" ]]; then
  echo "⚠ No relevant code files found for '$TOPIC' in $REPO_NAME."
  exit 0
fi

FILE_COUNT=$(echo "$CODE_FILES" | grep -c . || echo 0)
echo "[PROJECT LENS] Found $FILE_COUNT highly relevant files. Commencing chunked anti-skim scan..."

# 4. Run scan.sh on these files to build feature docs in the TMP_DIR/.lens/
while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  RELATIVE="${file#$TMP_DIR/}"
  echo "[PROJECT LENS] Scanning: $RELATIVE"

  # Run the scan
  "$SCRIPT_DIR/scan.sh" "$file" "$TMP_DIR"
done <<< "$CODE_FILES"

# 5. Run search.sh on the generated docs to produce the final briefing
echo "[PROJECT LENS] Generating final briefing..."
"$SCRIPT_DIR/search.sh" "$TOPIC" "$TMP_DIR"

# Note: We keep the TMP_DIR around so subsequent queries on the same repo are fast.
exit 0
