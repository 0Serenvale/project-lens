---
name: init
description: Initialize project-lens on a new or existing project. Scans all code files with a cheap OpenRouter LLM and generates per-feature documentation in .lens/. Run this once when starting work on any project.
argument-hint: [project_root]
user-invocable: true
disable-model-invocation: false
allowed-tools: Bash, Read, Write, Glob
---

# /lens:init

Run the full project scan and generate `.lens/` documentation.

## Steps

1. Confirm the project root with the user (default: current working directory `$CWD`)
2. Check that `CLAUDE_PLUGIN_OPTION_openrouter_key` is set — if not, tell the user:
   ```
   Run: claude plugin config project-lens openrouter_key YOUR_KEY
   ```
3. Run the init script:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/init.sh <project_root>
   ```
4. Once complete, read `$PROJECT_ROOT/.lens/overview.md` and summarize what was found for the user
5. List all feature docs created in `.lens/features/`
6. Ask the user: "Should I add `.lens/` to `.gitignore`?" — if yes, append it

## What gets created

```
.lens/
  overview.md          ← project architecture summary
  index.md             ← file → feature mapping
  features/
    <feature>.md       ← one doc per detected feature
```

## After init

Tell the user: "From now on, every time you ask me to edit a file, I will automatically receive the full file content and its feature doc before touching anything. No more skipping."
