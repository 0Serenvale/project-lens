---
name: update
description: Update all stale .lens feature docs after a work session. Run this after code review or after a batch of commits to keep docs current. Part of the standard workflow: code review → commit → update.
user-invocable: true
---

# /lens:update

Rescan all files changed since the last lens update.

## Steps

1. Find files changed since the last lens update:
   ```bash
   # Get files changed in last N commits or since .lens was last modified
   git diff --name-only HEAD~5 HEAD 2>/dev/null | \
     grep -E '\.(ts|tsx|js|jsx|py|go|rs|php|rb|java|vue|svelte)$'
   ```
2. Cross-reference with `.lens/index.md` to find which feature docs need updating
3. For each changed file, run:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/scan.sh <file> <project_root>
   ```
4. Report: "Updated X feature docs: [list]"
5. If any file has no feature doc yet, create one

## Standard workflow reminder

After every significant task, the workflow is:
1. Code review (`/review` or manual)
2. Commit changes
3. `/lens:update` — keep docs current
4. Update memory if architectural decisions changed

This ensures the next session starts with accurate context.
