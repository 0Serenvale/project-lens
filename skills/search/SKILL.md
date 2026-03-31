---
name: search
description: Search .lens feature docs by topic before starting any task. Returns the relevant feature doc so you have full context before touching code. Use this before every task involving an unfamiliar feature.
argument-hint: <topic>
user-invocable: true
disable-model-invocation: false
allowed-tools: Bash, Read, Glob, Grep
---

# /lens:search

Find and load the relevant feature documentation before starting work.

## Usage

```
/lens:search search
/lens:search authentication
/lens:search match statistics
/lens:search documents upload
```

## Steps

1. Get the topic from `$ARGUMENTS`
2. Check if `.lens/features/` exists in the current project — if not, tell the user to run `/lens:init` first
3. Search for matching feature docs:
   ```bash
   # Search by filename
   ls .lens/features/ | grep -i "$ARGUMENTS"

   # Search by content
   grep -ril "$ARGUMENTS" .lens/features/
   ```
4. If multiple matches: list them and ask the user which one, or load all if fewer than 3
5. Read and display the full content of the matching feature doc(s)
6. Also check `.lens/overview.md` — if the topic appears in the architecture section, show that excerpt too
7. Summarize: "Here's what I know about [topic] before touching anything."

## If no doc found

If no `.lens` doc exists for the topic:
1. Tell the user: "No feature doc found for '[topic]'. Running a quick scan..."
2. Try to find relevant files with Grep:
   ```bash
   grep -rl "<topic>" src/ --include="*.ts" --include="*.tsx" | head -5
   ```
3. Run scan.sh on the top matches
4. Load the freshly generated doc

## Important

Never start editing code related to a feature without first loading its lens doc.
If the doc says "Last Scanned" is more than 7 days ago, warn the user it may be stale and offer to rescan.
