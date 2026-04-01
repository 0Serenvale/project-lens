#!/bin/bash
# lib/ram.sh — Shared RAM path resolution for all project-lens scripts.
# Source this file to get LENS_RAM and LENS_DISK variables.
#
# Usage: source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/ram.sh" "$PROJECT_ROOT"

PROJECT_ROOT="${1:-$(pwd)}"

# ─── Load config file (runtime, no restart needed) ───────────────────────────
# ~/.claude/project-lens.env is read on every script call.
# Edit it mid-session to change model or key instantly.
LENS_CONFIG="${HOME}/.claude/project-lens.env"
if [[ -f "$LENS_CONFIG" ]]; then
  # Parse config without sourcing (security: avoid eval)
  while IFS='=' read -r key value || [[ -n "$key" ]]; do
    # Skip comments and empty lines
    [[ "$key" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$key" ]] && continue

    # Trim whitespace using Bash built-ins
    key="${key#"${key%%[![:space:]]*}"}"
    key="${key%"${key##*[![:space:]]}"}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"

    # Only allow specific keys
    case "$key" in
      OPENROUTER_API_KEY|OPENROUTER_MODEL)
        export "$key"="$value"
        ;;
    esac
  done < "$LENS_CONFIG"
fi

# Resolve final values: config file → env var → plugin userConfig → default
OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-${CLAUDE_PLUGIN_OPTION_openrouter_key:-}}"
OPENROUTER_MODEL="${OPENROUTER_MODEL:-${CLAUDE_PLUGIN_OPTION_model:-deepseek/deepseek-chat}}"

# ─── Stable hash of the project path — identifies this project's RAM slot ────
# Uses md5sum if available, falls back to simple checksum
if command -v md5sum &>/dev/null; then
  PROJECT_HASH=$(echo -n "$PROJECT_ROOT" | md5sum | cut -c1-12)
elif command -v md5 &>/dev/null; then
  PROJECT_HASH=$(echo -n "$PROJECT_ROOT" | md5 | cut -c1-12)
else
  # Fallback: encode path as safe string
  PROJECT_HASH=$(echo -n "$PROJECT_ROOT" | tr '/' '_' | tr -cd 'a-zA-Z0-9_' | tail -c 12)
fi

# RAM directory — /dev/shm is tmpfs (RAM) on Linux
# Falls back to /tmp on systems without /dev/shm (macOS)
if [[ -d "/dev/shm" ]]; then
  RAM_BASE="/dev/shm/project-lens"
else
  RAM_BASE="/tmp/project-lens"
fi

# Per-project RAM slot
LENS_RAM="$RAM_BASE/$PROJECT_HASH"

# Disk source — where .lens/ lives in the project
LENS_DISK="$PROJECT_ROOT/.lens"
