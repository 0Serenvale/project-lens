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

# Create a large feature file (> 200 lines) to trigger summarization path
for i in {1..250}; do
  echo "Line $i of test feature content" >> "$TEMP_PROJECT_ROOT/.lens/features/test-feature.md"
done

# 2. Configure environment for test
SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export CLAUDE_PLUGIN_ROOT="$SCRIPT_ROOT"
export HOME="$MOCK_HOME"
unset OPENROUTER_API_KEY 2>/dev/null || true
unset CLAUDE_PLUGIN_OPTION_openrouter_key 2>/dev/null || true

TOPIC="test-feature"

# 3. Run the script
echo "Running scripts/search.sh with no API key and large doc..."
OUTPUT=$("$SCRIPT_ROOT/scripts/search.sh" "$TOPIC" "$TEMP_PROJECT_ROOT" 2>&1) || {
  echo "FAIL: Script exited with error"
  echo "$OUTPUT"
  exit 1
}

# 4. Verify raw content returned (no API key → skip summarization)
if echo "$OUTPUT" | grep -q "=== FEATURE DOC: test-feature ==="; then
  echo "PASS: Raw content returned when API key is missing."
else
  echo "FAIL: Raw content not found in output."
  echo "Output was:"
  echo "$OUTPUT"
  exit 1
fi

# 5. Verify curl was not invoked
if echo "$OUTPUT" | grep -q "curl"; then
  echo "FAIL: curl was invoked even without an API key."
  exit 1
fi

echo "All checks passed."
