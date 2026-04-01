# project-lens

A Claude Code plugin that eliminates AI context loss on large codebases.

Uses a free OpenRouter LLM to scan your project once and generate per-feature documentation stored in RAM (`/dev/shm`). Before every file edit, the relevant feature doc + file content is automatically injected into Claude's context — no skimming, no assumptions, no wrong guesses about dependencies.

## The Problem

Claude skims large files and unfamiliar code. It pattern-matches instead of reading, misses dependencies, and makes wrong assumptions that cause refactoring cycles and wasted tokens.

## The Solution

```
You ask Claude to edit a file
        ↓
PreToolUse hook fires automatically
        ↓
Feature doc + file content injected into context
        ↓
Claude receives it — nothing to skip, it's already there
        ↓
Claude acts on real understanding, not guesses
```

Feature docs are generated once by a free OpenRouter LLM — not Claude tokens.

---

## Prerequisites

- **Linux or WSL2** (Windows native not supported — no `/dev/shm`)
- **Claude Code** CLI installed
- **`curl`** — installed on most systems
- **`jq`** — auto-installed by the plugin if missing (requires `apt-get`, `brew`, or `yum`)
- **OpenRouter account** — free at [openrouter.ai](https://openrouter.ai)

---

## Install

**Step 1 — Add the marketplace:**
```bash
claude plugin marketplace add 0Serenvale/project-lens
```

**Step 2 — Install the plugin:**
```bash
claude plugin install project-lens@project-lens
```

**Step 3 — Create config file:**
```bash
cp ~/.claude/plugins/cache/project-lens/project-lens/*/project-lens.env.example ~/.claude/project-lens.env
```

**Step 4 — Add your OpenRouter key and model:**
```bash
nano ~/.claude/project-lens.env
```

```env
OPENROUTER_API_KEY=your-key-here
OPENROUTER_MODEL=meta-llama/llama-3.3-70b-instruct:free
```

Get a free key at [openrouter.ai/keys](https://openrouter.ai/keys).

---

## First Use (run once per project)

Open your project in Claude Code, then:

```
/lens:init
```

This scans your codebase, generates `.lens/features/<feature>.md` for each detected feature, creates a project overview, and adds `.lens/` to `.gitignore` automatically.

For large projects (>80 files), it scans entry points and key directories first. Run `/lens:scan <file>` on specific files for deeper docs.

---

## Commands

| Command | What it does |
|---|---|
| `/lens:init` | First-time full project scan |
| `/lens:search <topic>` | Load feature context before starting any task |
| `/lens:scan <file>` | Rescan a specific file after changes |
| `/lens:update` | Rescan all files changed since last update |

---

## Recommended Workflow

```
Start task    →  /lens:search <feature>    load context first
Make changes  →  hook auto-injects         before every edit
Code review   →  /review
Commit        →  hook auto-triggers rescan on changed files
End session   →  /lens:update              keep docs current
```

---

## How It Works

### Session lifecycle
```
Session starts   → session-start.sh copies .lens/ → /dev/shm/project-lens/<hash>/
During session   → all reads from RAM (~0.01ms vs ~5ms disk)
Session ends     → session-end.sh syncs RAM → disk, clears RAM slot
```

### Before every edit
```
pre-edit.sh fires → finds feature doc in RAM → injects into Claude context
Files ≤200 lines  → full content injected
Files >200 lines  → first+last 80 lines + prompt to run /lens:scan
```

### Feature docs contain
- **Purpose** — what the file does and what breaks if removed
- **Exports** — every exported symbol with exact signature and side effects
- **Imports** — internal, external, framework/config — all listed explicitly
- **Called By** — what imports this file
- **Data Flow** — numbered steps tracing data end-to-end
- **Conditional Logic** — every branch named
- **Null/Undefined Risks** — every place data can be missing
- **Side Effects** — DB calls, API calls, state mutations
- **Gotchas** — non-obvious behavior, known issues, traps
- **Status** — implemented / has bugs / needs tests / needs optimization

---

## Changing Model Mid-Session

Edit `~/.claude/project-lens.env` — takes effect on the next script call, no restart needed:

```bash
nano ~/.claude/project-lens.env
# Change OPENROUTER_MODEL=google/gemma-3-27b-it:free
```

## Free Models (check [openrouter.ai/models?q=free](https://openrouter.ai/models?q=free) for current availability)

- `meta-llama/llama-3.3-70b-instruct:free`
- `google/gemma-3-27b-it:free`
- `qwen/qwen-2.5-72b-instruct:free`
- `mistralai/mistral-7b-instruct:free`

## Rate Limits

Free models have daily request limits. When the limit is hit:
- The scan stops immediately with a clear message
- Already-scanned files are preserved in RAM
- Re-running `/lens:init` resumes from where it left off (skips completed files)
- Limits reset at midnight UTC

---

## Cost

Using free models: **$0** for scanning.
Using `deepseek/deepseek-chat`: ~$0.0001 per file. A 100-file project costs ~$0.01.

---

## Platform Support

| Platform | Status |
|---|---|
| Linux | ✔ Full support — `/dev/shm` real RAM |
| WSL2 (Windows) | ✔ Full support — `/dev/shm` available |
| macOS | ✔ Works — `/tmp` fallback (disk, not RAM) |
| Windows native | ✘ Not supported — no bash, no `/dev/shm` |

---

## License

MIT — [github.com/0Serenvale/project-lens](https://github.com/0Serenvale/project-lens)
