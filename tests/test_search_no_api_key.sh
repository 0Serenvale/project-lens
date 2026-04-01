#!/bin/bash
# tests/test_search_no_api_key.sh — Test that search.sh returns raw docs when API key is missing.

set -euo pipefail

# 1. Setup temporary environment
TEMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TEMP_ROOT"' EXIT

# Mock home directory to avoid touching real config
MOCK_HOME="$TEMP_ROOT/mock_home"
mkdir -p "$MOCK_HOME/.claude"

# Mock project directory
TEMP_PROJECT_ROOT="$TEMP_ROOT/temp_project"
mkdir -p "$TEMP_PROJECT_ROOT/.lens/features"

# Create a large feature file (> 200 lines)
for i in {1..250}; do
  echo "Line $i of test feature content" >> "$TEMP_PROJECT_ROOT/.lens/features/test-feature.md"
done

# 2. Configure environment for test
export CLAUDE_PLUGIN_ROOT="$(pwd)"
export HOME="$MOCK_HOME"
unset OPENROUTER_API_KEY
unset CLAUDE_PLUGIN_OPTION_openrouter_key

TOPIC="test-feature"

# 3. Run the script
echo "Running scripts/search.sh with no API key and large doc..."
# Capturing stderr too to check for any unbound variable errors
OUTPUT=$(./scripts/search.sh "$TOPIC" "$TEMP_PROJECT_ROOT" 2>&1) || {
  echo "❌ Script exited with error"
  echo "$OUTPUT"
  exit 1
}

# 4. Verify output
# The script should return DOCS_CONTENT which contains "=== FEATURE DOC: $SLUG ==="
# since it bypasses summarization when API_KEY is missing and TOTAL_LINES >= 200.
if echo "$OUTPUT" | grep -q "=== FEATURE DOC: test-feature ==="; then
  echo "✅ Test Passed: Raw content was outputted when API key was missing."
else
  echo "❌ Test Failed: Raw content not found in output."
  echo "Output was:"
  echo "$OUTPUT"
  exit 1
fi

# Ensure it didn't try to call curl (which would likely fail or produce some error message)
if echo "$OUTPUT" | grep -q "curl"; then
  echo "❌ Test Failed: It seems curl was invoked even without an API key."
  exit 1
fi
