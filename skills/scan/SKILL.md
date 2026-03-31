---
name: scan
description: Scan a specific file or directory with OpenRouter and update its .lens feature doc. Use after adding new features, after major refactors, or when a feature doc feels outdated.
argument-hint: <file_or_directory>
user-invocable: true
disable-model-invocation: false
allowed-tools: Bash, Read, Glob
---

# /lens:scan

Rescan a specific file or directory and update its feature documentation.

## Usage

```
/lens:scan src/components/search/
/lens:scan src/collections/league/Matches.ts
```

## Steps

1. Resolve the path from `$ARGUMENTS` — if relative, resolve from current working directory
2. If it's a directory: find all code files inside it
3. If it's a single file: scan just that file
4. For each file, run:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/scan.sh <file_path> <project_root>
   ```
5. Read the updated `.lens/features/<feature>.md` and show the user a summary of what changed
6. Update `.lens/index.md` with any new file→feature mappings

## When to use

- After adding a new collection, component, or API route
- After a major refactor that changed how a feature works
- When you notice a feature doc is stale (run `/lens:search <topic>` and check Last Scanned date)
- After a code review that identified undocumented behavior
