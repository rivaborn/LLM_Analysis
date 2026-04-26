# archgen.ps1 -- Per-File Architecture Doc Generator (Claude CLI)

## Purpose

`archgen.ps1` is the foundational analysis step. It scans a codebase for source files matching configurable extension/directory patterns, optionally bundles related headers, and dispatches each file (or small batch) to the local **Claude CLI** (`claude -p`). The CLI returns a structured Markdown architecture document — purpose, key functions, data structures, global state, dependencies, control flow.

The script is **incremental** (SHA-1 hash database in `architecture/.archgen_state/hashes.tsv`), **parallel** (jobs dispatched to `archgen_worker.ps1` via `Start-Job`), and supports several optimisation modes documented inline (header bundling, batched small files, prompt variants for LSP-enriched runs, two-phase classification, tiered model auto-upgrade for complex files).

The script drives the Claude CLI directly — **not** Ollama. It supports dual-account rotation via `-Claude1` / `-Claude2` (the second is the default).

## Prerequisites

| Requirement                       | Details                                                                                                  |
| --------------------------------- | -------------------------------------------------------------------------------------------------------- |
| PowerShell 5.1+ or pwsh 7+        | Script uses `Set-StrictMode -Version Latest`                                                             |
| `claude` CLI on PATH              | Anthropic's command-line client; authenticated against at least one account                              |
| `archgen_worker.ps1`              | Per-batch worker, must live in same folder; called via `Start-Job -FilePath`                             |
| `../Common/llm_common.ps1`        | Shared module providing `Read-EnvFile`, `Cfg`, `Get-Preset`, `Get-FenceLang`, `Get-SHA1`, `Test-TrivialFile`, etc. |
| `../Common/.env`                  | Configuration: Claude model, account dirs, preset, file filters                                          |
| `*_prompt.txt` files              | Prompt schemas in same folder (`file_doc_prompt.txt`, `file_doc_prompt_lsp.txt`, `file_doc_prompt_minimal.txt`, etc.) |
| `ue_preamble.txt`                 | Engine-knowledge preamble loaded automatically when `USE_PREAMBLE=1`                                     |
| (Optional) `architecture/.serena_context/` | LSP symbol files from `serena_extract.ps1` — when present, the LSP prompt variant is auto-selected |

## Usage

```powershell
.\archgen.ps1 [-TargetDir <path>] [-Preset <name>] [-Claude1] [-Clean] [-NoHeaders]
              [-Jobs <n>] [-EnvFile <path>] [-RepoRoot <path>]
              [-ElideSource <flag>] [-NoBatch <flag>] [-NoPreamble <flag>]
              [-MaxTokens <flag>] [-JsonOutput <flag>] [-CompressLSP <flag>]
              [-Classify <flag>] [-Test]
```

### CLI Options

| Parameter      | Type   | Default          | Description                                                                                                                                                                          |
| -------------- | ------ | ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `-TargetDir`   | string | `"."`            | Subdirectory (relative to repo root) to scan. `"."` scans the entire repo.                                                                                                           |
| `-Preset`      | string | `""`             | Named preset (`unreal`, `quake`, `generals`, etc.). Overrides `PRESET` in `.env`. Controls include/exclude regex, codebase description, default fence language.                       |
| `-Claude1`     | switch | off              | Use the `CLAUDE1_CONFIG_DIR` Claude account instead of the default `CLAUDE2_CONFIG_DIR`. Useful for rate-limit rotation.                                                              |
| `-Clean`       | switch | off              | Remove all generated docs and state (preserves `.serena_context`, `.dir_context`, `.dir_headers`), then regenerate.                                                                  |
| `-NoHeaders`   | switch | off              | Disable header bundling (forces `BUNDLE_HEADERS=0` for this run).                                                                                                                    |
| `-Jobs`        | int    | `0`              | Parallel `Start-Job` count. `0` reads `JOBS` from `.env` (default 2). The worker scripts run independently, each shelling out to `claude`.                                          |
| `-EnvFile`     | string | `../Common/.env` | Path to an alternative `.env` configuration file.                                                                                                                                    |
| `-RepoRoot`    | string | `""` (auto)      | Override for the target repo root. When empty, auto-detects via CWD then `git rev-parse --show-toplevel`. `AnalysisPipeline.py` forwards `--repo-root` to every worker via this arg. |
| `-ElideSource` | string | `""`             | When non-empty, sets `ELIDE_SOURCE=1` to elide source code from prompts (LSP-only context).                                                                                          |
| `-NoBatch`     | string | `""`             | When non-empty, disables batched-small-file mode.                                                                                                                                    |
| `-NoPreamble`  | string | `""`             | When non-empty, skips loading `ue_preamble.txt`.                                                                                                                                     |
| `-MaxTokens`   | string | `""`             | When non-empty, enables `--max-tokens` cap on the Claude CLI call (computed from output budget).                                                                                     |
| `-JsonOutput`  | string | `""`             | When non-empty, switches Claude CLI output format to JSON.                                                                                                                           |
| `-CompressLSP` | string | `""`             | Reserved flag for compressing LSP context.                                                                                                                                           |
| `-Classify`    | string | `""`             | When non-empty, runs the two-phase classification pre-pass (`classify_prompt.txt`).                                                                                                  |
| `-Test`        | switch | off              | Run the built-in unit test suite (loads `archgen_worker.ps1` functions for testing if present).                                                                                      |

## How It Is Invoked

**Standalone:**
```powershell
cd C:\Coding\Epic_Games\UnrealEngine
.\Analysis\archgen.ps1 -Preset unreal
```

**Via AnalysisPipeline.py:**
The orchestrator calls this as the first step of every subsection:
```
python C:\Coding\LLM_Analysis\Analysis\AnalysisPipeline.py
```
which runs `archgen.ps1 -RepoRoot <repo> -TargetDir <subsection> -Preset unreal` per subsection from the `#Subsections begin/end` block in `Common/.env`.

## Input Files

| Input                                                  | Location                              | Description                                                                                          |
| ------------------------------------------------------ | ------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| Source files                                           | `<repo_root>/<TargetDir>/`            | All files matching `INCLUDE_EXT_REGEX` and not matching `EXCLUDE_DIRS_REGEX` / `EXTRA_EXCLUDE_REGEX` |
| `.env`                                                 | `../Common/.env`                      | Configuration (Claude model, accounts, preset, file filters)                                         |
| Prompt files                                           | Script directory                      | `file_doc_prompt.txt` (default), `file_doc_prompt_lsp.txt` (auto-selected if Serena context exists), `file_doc_prompt_minimal.txt` (small files), `classify_prompt.txt` (with `-Classify`) |
| `ue_preamble.txt`                                      | Script directory                      | Engine-knowledge preamble (loaded when `USE_PREAMBLE=1`)                                             |
| `architecture/.serena_context/<rel>.serena_context.txt`| Repo root                             | Optional LSP symbol data per file                                                                    |

## Output Files

| Output        | Location                                                 | Description                                                                                       |
| ------------- | -------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| Per-file docs | `<repo_root>/architecture/<rel_path>.md`                 | One Markdown doc per source file                                                                  |
| Hash database | `<repo_root>/architecture/.archgen_state/hashes.tsv`     | Tab-separated `SHA1\trelpath` for incremental skip                                                 |
| Counter       | `<repo_root>/architecture/.archgen_state/counters.tsv`   | Per-account / per-model usage counters                                                            |
| Error log     | `<repo_root>/architecture/.archgen_state/last_error.log` | Timestamped failures                                                                              |
| Trivial stubs | `<repo_root>/architecture/<rel_path>.md`                 | 4-line placeholder for trivial/generated files (when `SKIP_TRIVIAL=1`)                            |

## Environment Variables / .env Keys

| Key                       | Default                  | Description                                                                                       |
| ------------------------- | ------------------------ | ------------------------------------------------------------------------------------------------- |
| `CLAUDE_MODEL`            | `sonnet`                 | Default Claude CLI model (e.g. `haiku`, `sonnet`, `opus`)                                         |
| `CLAUDE_MAX_TURNS`        | `1`                      | Max conversation turns per Claude CLI call                                                        |
| `CLAUDE_OUTPUT_FORMAT`    | `text`                   | Claude CLI output format                                                                          |
| `CLAUDE1_CONFIG_DIR`      | (must be set)            | Path to first Claude CLI config dir; selected via `-Claude1`                                      |
| `CLAUDE2_CONFIG_DIR`      | (must be set)            | Path to second Claude CLI config dir; selected by default                                         |
| `JOBS`                    | `2`                      | Parallel job count (overridden by `-Jobs`)                                                        |
| `MAX_RETRIES`             | `2`                      | Retries per file on transient errors                                                              |
| `RETRY_DELAY`             | `5`                      | Seconds between retries                                                                           |
| `BUNDLE_HEADERS`          | `1`                      | Bundle related headers into the prompt for `.cpp` analysis                                        |
| `MAX_BUNDLED_HEADERS`     | `5`                      | Cap on bundled headers per request                                                                |
| `MAX_FILE_LINES`          | `4000`                   | Truncate source files beyond this line count before sending to LLM                                |
| `SKIP_TRIVIAL`            | `1`                      | Whether to skip trivial files                                                                     |
| `MIN_TRIVIAL_LINES`       | `20`                     | Files below this line count are considered trivial                                                |
| `TIERED_MODEL`            | `1`                      | Auto-upgrade complex files to `HIGH_COMPLEXITY_MODEL`                                             |
| `HIGH_COMPLEXITY_MODEL`   | `sonnet`                 | Model used for complex files when tiered logic is enabled                                         |
| `BATCH_SMALL_FILES`       | `1`                      | Batch small files into one Claude CLI call                                                        |
| `BATCH_MAX_LINES`         | `100`                    | Files at or below this line count are batchable                                                   |
| `BATCH_SIZE`              | `4`                      | Files per batch                                                                                   |
| `USE_PREAMBLE`            | `1`                      | Inject `ue_preamble.txt` into every prompt                                                        |
| `PRESET`                  | `""`                     | Named preset (overridden by `-Preset` flag)                                                       |
| `INCLUDE_EXT_REGEX`       | Preset-dependent         | Regex for file extensions to include                                                              |
| `EXCLUDE_DIRS_REGEX`      | Preset-dependent         | Regex for directories/paths to exclude                                                            |
| `EXTRA_EXCLUDE_REGEX`     | `""`                     | Additional exclude regex                                                                          |
| `CODEBASE_DESC`           | Preset-dependent         | Human-readable codebase description                                                               |
| `DEFAULT_FENCE`           | Preset-dependent         | Default Markdown fence language                                                                   |

## Exit Codes

| Code | Meaning                                                                                          |
| ---- | ------------------------------------------------------------------------------------------------ |
| `0`  | Success (all files processed or nothing to do)                                                   |
| `1`  | No matching source files found, or target directory not found                                    |
| `2`  | Missing prompt file, missing `archgen_worker.ps1`, or missing `CLAUDE_CONFIG_DIR`                |

## Examples

**Example 1: Generate docs for the full UE source tree**
```powershell
cd C:\Coding\Epic_Games\UnrealEngine
.\..\..\LLM_Analysis\Analysis\archgen.ps1 -Preset unreal -Jobs 4
```

**Example 2: Target a specific subsystem and use the second Claude account**
```powershell
.\Analysis\archgen.ps1 -TargetDir Engine/Source/Runtime/Renderer -Preset unreal -Claude1
```

**Example 3: Clean rebuild with no header bundling, no batching**
```powershell
.\Analysis\archgen.ps1 -Clean -NoHeaders -NoBatch 1 -Preset unreal
```

**Example 4: Run unit tests**
```powershell
.\Analysis\archgen.ps1 -Test
```

## Related

- `Analysis/archgen_worker.ps1` — per-batch worker dispatched via `Start-Job`
- `Analysis/AnalysisPipeline.py` — orchestrator that runs this as Step 1 per subsection
- `Common/llm_common.ps1` / `llm_core.ps1` / `file_helpers.ps1` — shared infrastructure
- `Common/.env` — every config key documented above
- `Documentation/AnalysisPipeline.md` — orchestrator docs
