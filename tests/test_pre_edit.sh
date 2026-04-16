#!/bin/bash
# tests/test_pre_edit.sh — Test pre-edit.sh hook logic.

set -euo pipefail

# 1. Setup temporary environment
TEMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TEMP_ROOT"' EXIT

# Mock home directory
MOCK_HOME="$TEMP_ROOT/mock_home"
mkdir -p "$MOCK_HOME/.claude"

# Mock project directory
TEMP_PROJECT_ROOT="$TEMP_ROOT/temp_project"
mkdir -p "$TEMP_PROJECT_ROOT/.lens/features"

# Configure environment for test
SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export CLAUDE_PLUGIN_ROOT="$SCRIPT_ROOT"
export HOME="$MOCK_HOME"

# Helper to run pre-edit.sh
run_pre_edit() {
  local input="$1"
  echo "$input" | "$SCRIPT_ROOT/scripts/pre-edit.sh"
}

echo "Running tests for scripts/pre-edit.sh..."

# --- Test 1: Empty file_path ---
echo "Test 1: Empty file_path..."
INPUT='{"tool_input": {}, "cwd": "'"$TEMP_PROJECT_ROOT"'"}'
OUTPUT=$(run_pre_edit "$INPUT")
if [[ -n "$OUTPUT" ]]; then
  echo "FAIL: Expected empty output for empty file_path"
  exit 1
fi
echo "PASS"

# --- Test 2: Non-existent file ---
echo "Test 2: Non-existent file..."
INPUT='{"tool_input": {"file_path": "non-existent.txt"}, "cwd": "'"$TEMP_PROJECT_ROOT"'"}'
OUTPUT=$(run_pre_edit "$INPUT")
if [[ -n "$OUTPUT" ]]; then
  echo "FAIL: Expected empty output for non-existent file"
  exit 1
fi
echo "PASS"

# --- Test 3: Blacklisted extension (.png) ---
echo "Test 3: Blacklisted extension (.png)..."
touch "$TEMP_PROJECT_ROOT/test.png"
INPUT='{"tool_input": {"file_path": "test.png"}, "cwd": "'"$TEMP_PROJECT_ROOT"'"}'
OUTPUT=$(run_pre_edit "$INPUT")
if [[ -n "$OUTPUT" ]]; then
  echo "FAIL: Expected empty output for blacklisted extension"
  exit 1
fi
echo "PASS"

# --- Test 4: Small file, no feature doc ---
echo "Test 4: Small file, no feature doc..."
echo "Line 1" > "$TEMP_PROJECT_ROOT/small.txt"
INPUT='{"tool_input": {"file_path": "small.txt"}, "cwd": "'"$TEMP_PROJECT_ROOT"'"}'
OUTPUT=$(run_pre_edit "$INPUT")
if ! echo "$OUTPUT" | grep -q "Line 1"; then
  echo "FAIL: File content not found in output"
  exit 1
fi
if ! echo "$OUTPUT" | grep -q "No feature doc found for this file"; then
  echo "FAIL: Expected 'No feature doc found' message"
  exit 1
fi
echo "PASS"

# --- Test 5: Small file, feature doc via index.md ---
echo "Test 5: Small file, feature doc via index.md..."
echo "Line 1" > "$TEMP_PROJECT_ROOT/mapped.txt"
echo "mapped.txt → mapped-feature" > "$TEMP_PROJECT_ROOT/.lens/index.md"
echo "Feature content from index" > "$TEMP_PROJECT_ROOT/.lens/features/mapped-feature.md"
INPUT='{"tool_input": {"file_path": "mapped.txt"}, "cwd": "'"$TEMP_PROJECT_ROOT"'"}'
OUTPUT=$(run_pre_edit "$INPUT")
if ! echo "$OUTPUT" | grep -q "Feature content from index"; then
  echo "FAIL: Feature doc from index.md not found in output"
  echo "Output: $OUTPUT"
  exit 1
fi
echo "PASS"

# --- Test 6: Small file, feature doc via slug (case-insensitive) ---
echo "Test 6: Small file, feature doc via slug..."
echo "Line 1" > "$TEMP_PROJECT_ROOT/MySlugFile.txt"
echo "Feature content from slug" > "$TEMP_PROJECT_ROOT/.lens/features/myslugfile.md"
# Remove index.md to ensure fallback is used
rm "$TEMP_PROJECT_ROOT/.lens/index.md"
INPUT='{"tool_input": {"file_path": "MySlugFile.txt"}, "cwd": "'"$TEMP_PROJECT_ROOT"'"}'
OUTPUT=$(run_pre_edit "$INPUT")
if ! echo "$OUTPUT" | grep -q "Feature content from slug"; then
  echo "FAIL: Feature doc from slug not found in output"
  echo "Output: $OUTPUT"
  exit 1
fi
echo "PASS"

# --- Test 7: Large file truncation ---
echo "Test 7: Large file truncation..."
LARGE_FILE="$TEMP_PROJECT_ROOT/large.txt"
for i in {1..250}; do
  echo "Line $i" >> "$LARGE_FILE"
done
INPUT='{"tool_input": {"file_path": "large.txt"}, "cwd": "'"$TEMP_PROJECT_ROOT"'"}'
OUTPUT=$(run_pre_edit "$INPUT")
if ! echo "$OUTPUT" | grep -q "showing first 80 + last 80"; then
  echo "FAIL: Missing truncation notice"
  exit 1
fi
if ! echo "$OUTPUT" | grep -q "### Lines 1–80"; then
  echo "FAIL: Missing first 80 lines section"
  exit 1
fi
if ! echo "$OUTPUT" | grep -q "### Lines 171–250"; then
  echo "FAIL: Missing last 80 lines section"
  exit 1
fi
if ! echo "$OUTPUT" | grep -q "Line 1$"; then
  echo "FAIL: Line 1 not found"
  exit 1
fi
if ! echo "$OUTPUT" | grep -q "Line 80$"; then
  echo "FAIL: Line 80 not found"
  exit 1
fi
if ! echo "$OUTPUT" | grep -q "Line 171$"; then
  echo "FAIL: Line 171 not found"
  exit 1
fi
if ! echo "$OUTPUT" | grep -q "Line 250$"; then
  echo "FAIL: Line 250 not found"
  exit 1
fi
if echo "$OUTPUT" | grep -q "Line 100$"; then
  echo "FAIL: Line 100 should have been truncated"
  exit 1
fi
echo "PASS"

echo "All tests passed successfully!"
