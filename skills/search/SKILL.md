---
name: search
description: Search .lens feature docs by topic before starting any task. Returns the relevant feature doc so you have full context before touching code. Use this before every task involving an unfamiliar feature.
argument-hint: <topic>
user-invocable: true
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
2. Run the search script — this uses OpenRouter (free LLM) to search and summarize, zero Claude tokens:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/search.sh "$ARGUMENTS" "$(pwd)"
   ```
3. Display the output to the user
4. If the output contains `⚠ UNCERTAIN` markers — flag those to the user explicitly
5. If "Last Scanned" in any doc is more than 7 days ago — warn: "This doc may be stale. Run /lens:scan <file> to refresh."

## If no doc found

The script will output available features. Tell the user:
"No doc found for '[topic]'. Want me to scan the relevant files now?"
If yes: find the files with Grep and run `/lens:scan` on them.

## Important

Never start editing code related to a feature without first running this search.
The search script does the heavy lifting via OpenRouter — your job is to read the output it returns.
