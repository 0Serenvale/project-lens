---
name: remote-scan
description: Clones a remote GitHub repository to a temporary directory and extracts specific implementation details or architecture patterns without scanning the entire project. Uses file chunking to prevent LLM skimming.
argument-hint: "<github_url> <target_concept>"
user-invocable: true
---

# /lens:remote

Scan specific mechanics or architecture from an external GitHub repository.

## Usage

```
/lens:remote https://github.com/tauri-apps/tauri "keyboard shortcut handling"
/lens:remote https://github.com/vercel/next.js "app router cache mechanics"
```

## Steps

1. Extract the `<github_url>` and `<target_concept>` from `$ARGUMENTS`.
2. Check that `CLAUDE_PLUGIN_OPTION_openrouter_key` is set.
3. Run the remote scan script:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/remote.sh "<github_url>" "<target_concept>"
   ```
4. Display the extracted context briefing to the user.

## Why this is better than reading the code directly
This uses the OpenRouter LLM to aggressively chunk and read large files. It does not skip or skim. It forces the LLM to read up to 450 lines at a time and summarize the implementation details, saving your main Claude context window.
