#!/bin/bash
# lib/ram.sh — Shared bootstrap for all project-lens scripts.
# Sourced by every script — sets LENS_RAM, LENS_DISK, OPENROUTER_API_KEY, OPENROUTER_MODEL.
# Also resolves CLAUDE_PLUGIN_ROOT if not set by the hook environment.
#
# Usage: source "/path/to/scripts/lib/ram.sh" "$PROJECT_ROOT"

PROJECT_ROOT="${1:-$(pwd)}"

# ─── Resolve CLAUDE_PLUGIN_ROOT ──────────────────────────────────────────────
# Hooks set this automatically. Skills/manual runs may not.
# Fall back to the directory containing this file (../../ from lib/ram.sh).
if [[ -z "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  CLAUDE_PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
  export CLAUDE_PLUGIN_ROOT
fi

# ─── Dependency check ────────────────────────────────────────────────────────
_ensure_dep() {
  local cmd="$1"
  if command -v "$cmd" &>/dev/null; then return 0; fi
  echo "[PROJECT LENS] Installing missing dependency: $cmd..." >&2
  if command -v apt-get &>/dev/null; then
    sudo apt-get install -y "$cmd" 2>/dev/null || apt-get install -y "$cmd" 2>/dev/null || true
  elif command -v brew &>/dev/null; then
    brew install "$cmd" 2>/dev/null || true
  elif command -v yum &>/dev/null; then
    sudo yum install -y "$cmd" 2>/dev/null || true
  fi
  if ! command -v "$cmd" &>/dev/null; then
    echo "[PROJECT LENS] ERROR: '$cmd' required but could not be installed." >&2
    echo "[PROJECT LENS] Install manually: https://command-not-found.com/$cmd" >&2
    exit 1
  fi
}

_ensure_dep jq
_ensure_dep curl

# ─── Load config file (runtime — no restart needed) ──────────────────────────
LENS_CONFIG="${HOME}/.claude/project-lens.env"
if [[ -f "$LENS_CONFIG" ]]; then
  # shellcheck source=/dev/null
  source "$LENS_CONFIG"
fi

# Resolve final values: config file → shell env → plugin userConfig → default
OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-${CLAUDE_PLUGIN_OPTION_openrouter_key:-}}"
OPENROUTER_MODEL="${OPENROUTER_MODEL:-${CLAUDE_PLUGIN_OPTION_model:-deepseek/deepseek-chat}}"

# ─── Stable project hash → RAM slot ──────────────────────────────────────────
if command -v md5sum &>/dev/null; then
  PROJECT_HASH=$(echo -n "$PROJECT_ROOT" | md5sum | cut -c1-12)
elif command -v md5 &>/dev/null; then
  PROJECT_HASH=$(echo -n "$PROJECT_ROOT" | md5 | cut -c1-12)
else
  PROJECT_HASH=$(echo -n "$PROJECT_ROOT" | tr '/' '_' | tr -cd 'a-zA-Z0-9_' | tail -c 12)
fi

# /dev/shm = real RAM on Linux. /tmp fallback on macOS.
if [[ -d "/dev/shm" ]]; then
  RAM_BASE="/dev/shm/project-lens"
else
  RAM_BASE="/tmp/project-lens"
fi

LENS_RAM="$RAM_BASE/$PROJECT_HASH"
LENS_DISK="$PROJECT_ROOT/.lens"
