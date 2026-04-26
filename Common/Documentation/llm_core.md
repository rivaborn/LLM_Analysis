# llm_core.ps1

Environment infrastructure for the LLM_Analysis toolkit. Dot-sourced by `llm_common.ps1`.

## What it is

Not a standalone script — a PowerShell module. It defines three functions that worker scripts use to parse `.env` files, look up config values, and detect a clean cancellation request. It has no params block and no exit codes; everything is exposed as functions.

This is a **lean** variant compared to the sister `LocalLLM_Analysis/Common/llm_core.ps1`. That toolkit drives Ollama and exposes `Invoke-LocalLLM`, `Get-LLMModel`, and `Get-LLMEndpoint`. This toolkit drives the **Claude CLI** directly from each worker script (`& claude -p --model ...`), so those Ollama-specific helpers are intentionally omitted here.

## Functions

| Function           | Purpose                                                                |
| ------------------ | ---------------------------------------------------------------------- |
| `Test-CancelKey`   | Poll keyboard for Ctrl+Q and exit cleanly if pressed                   |
| `Read-EnvFile`     | Parse a `.env` file into a `[hashtable]`                               |
| `Cfg`              | Look up a key in the script-scoped `$script:cfg` hashtable with a default |

---

## Test-CancelKey

Poll the console for Ctrl+Q. If pressed, prints a yellow message and `exit 130` (the conventional exit code for SIGINT-style user cancellation). Returns silently if input is redirected (non-interactive) or if no key is queued.

**Parameters:** none.
**Returns:** `$null` (early-returns on no-input or non-interactive).
**Side effects:** consumes keys from the console buffer; calls `exit 130` if Ctrl+Q is found.

Worker scripts should call this between Claude CLI invocations inside long loops:

```powershell
foreach ($file in $files) {
    Test-CancelKey
    & claude -p --model haiku --max-turns 1 --output-format text $prompt
    ...
}
```

Pressing Ctrl+Q inside such a loop terminates the script cleanly between iterations rather than mid-Claude-call.

---

## Read-EnvFile

Parse a `.env` file. One pass; preserves no order.

**Parameters:**

| Parameter | Type   | Default | Effect                          |
| --------- | ------ | ------- | ------------------------------- |
| `$path`   | string | (none)  | Filesystem path to the env file |

**Behavior:**

- Skips blank lines and lines whose first non-space char is `#`.
- Matches `KEY=VALUE` (anything before the first `=` is the key, anything after is the value).
- Trims surrounding double or single quotes from the value (one set only).
- Replaces literal `$HOME` and a leading `~` with `$env:USERPROFILE` so paths like `~/repo` and `$HOME/repo` resolve on Windows.
- Returns an empty hashtable if the file doesn't exist (no error).

**Returns:** `[hashtable]` keyed by env var name.

```powershell
$script:cfg = Read-EnvFile (Join-Path $PSScriptRoot '..\Common\.env')
```

The result is conventionally assigned to `$script:cfg` so that `Cfg` can find it.

---

## Cfg

Look up a key in `$script:cfg` (the hashtable produced by `Read-EnvFile`) with a default. Empty strings count as unset.

**Parameters:**

| Parameter   | Type   | Default | Effect                                          |
| ----------- | ------ | ------- | ----------------------------------------------- |
| `$key`      | string | (none)  | Config key name to look up                      |
| `$default`  | string | `''`    | Value returned when the key is missing or empty |

**Returns:** the config value, or `$default` if the key is absent / blank.

**Requires:** `$script:cfg` to be set in the calling script (typically via `$script:cfg = Read-EnvFile $EnvFile`).

```powershell
$model     = Cfg 'CLAUDE_MODEL'         'sonnet'
$maxTurns  = Cfg 'CLAUDE_MAX_TURNS'     '1'
$outputFmt = Cfg 'CLAUDE_OUTPUT_FORMAT' 'text'
$preset    = Cfg 'PRESET'               ''
```

---

## Why no `Invoke-LocalLLM` here?

This toolkit drives the Claude CLI directly. Each worker script invokes `claude -p` with an `--append-system-prompt-file` and pipes the user prompt via stdin. The retry/rate-limit/timeout logic lives in the worker scripts (e.g. `archgen_worker.ps1`, `archpass2_worker.ps1`) rather than in a shared helper, because those concerns are tightly coupled to Claude's specific output formats and error messages.

If the toolkit ever switches to a local Ollama backend (or adds a dual-backend mode), the relevant helpers (`Invoke-LocalLLM`, `Get-LLMModel`, `Get-LLMEndpoint`) can be ported in from `LocalLLM_Analysis/Common/llm_core.ps1` — they are already battle-tested there.

## Related

- `Common/llm_common.ps1` — shim that loads this module
- `Common/file_helpers.ps1` — companion module (presets, hashing, fence-language mapping, trivial-file detection, truncation, LSP context loading, progress display)
- `Common/.env` — every config key documented above is read from here via `Read-EnvFile` + `Cfg`
- `Documentation/llm_common.md` — overview of the shim
- `Documentation/file_helpers.md` — companion module
