# archpass2.ps1 -- Context-Aware Second-Pass Analysis (Claude CLI)

## Purpose

`archpass2.ps1` performs a second-pass architectural analysis of source files, enriching the first-pass documentation with cross-cutting insights. While `archgen.ps1` (Pass 1) analyzes each file in isolation, Pass 2 re-analyzes files with injected context: the architecture overview, cross-reference index, and (optionally) targeted per-file context built by `archpass2_context.ps1`.

The script scores and ranks candidate files by their architectural significance — files with more cross-references and larger codebases rank higher. It supports `-Top N` to process only the most important files and `-ScoreOnly` to preview rankings without running Claude. Like Pass 1, it is fully incremental via SHA-1 hash tracking.

The script drives the **Claude CLI** directly (not Ollama). It dispatches batches via `Start-Job -FilePath archpass2_worker.ps1`, supports dual-account rotation via `-Claude1`, and offers a `-Delta` mode that emits only NEW insights via the dedicated `file_doc_prompt_pass2_delta.txt` prompt.

## Prerequisites

| Requirement                               | Details                                                       |
| ----------------------------------------- | ------------------------------------------------------------- |
| PowerShell 5.1+ or pwsh 7+                | Uses `Set-StrictMode -Version Latest`                         |
| `claude` CLI on PATH                      | Authenticated against at least one account                    |
| `archpass2_worker.ps1`                    | Per-batch worker, must live in same folder                    |
| `../Common/llm_common.ps1`                | Shared module                                                 |
| `../Common/.env`                          | Configuration                                                 |
| `architecture/architecture.md`            | Output of `arch_overview.ps1`                                 |
| `architecture/xref_index.md`              | Output of `archxref.ps1`                                      |
| Per-file Pass 1 docs                      | Output of `archgen.ps1` in `architecture/`                    |
| (Optional) `architecture/.pass2_context/` | Targeted context from `archpass2_context.ps1`                 |
| `file_doc_prompt_pass2.txt`               | Pass-2 prompt schema in script directory                      |
| (Optional) `file_doc_prompt_pass2_delta.txt` | Delta-mode prompt (used with `-Delta`)                     |

## Usage

```powershell
.\archpass2.ps1 [-TargetDir <dir>] [-Claude1] [-Clean] [-Only <paths>] [-Jobs <n>]
                [-EnvFile <path>] [-RepoRoot <path>] [-Top <n>] [-ScoreOnly] [-Delta] [-Test]
```

### CLI Options

| Parameter    | Type   | Default          | Description                                                                                                                                                                          |
| ------------ | ------ | ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `-TargetDir` | string | `"."`            | Subdirectory to scan (relative to repo root). `"."` scans the entire repo.                                                                                                           |
| `-Claude1`   | switch | off              | Use the `CLAUDE1_CONFIG_DIR` Claude account instead of the default `CLAUDE2_CONFIG_DIR`.                                                                                             |
| `-Clean`     | switch | off              | Remove all `.pass2.md` files and Pass 2 state before processing.                                                                                                                     |
| `-Only`      | string | `""`             | Comma-separated list of specific relative file paths to process (bypasses scanning).                                                                                                 |
| `-Jobs`      | int    | `0`              | Parallel `Start-Job` count. `0` reads `JOBS` from `.env`.                                                                                                                            |
| `-EnvFile`   | string | `../Common/.env` | Alternative `.env` file.                                                                                                                                                             |
| `-RepoRoot`  | string | `""` (auto)      | Override for the target repo root. When empty, auto-detects via CWD then `git rev-parse --show-toplevel`. `AnalysisPipeline.py` forwards `--repo-root` to every worker via this arg. |
| `-Top`       | int    | `0`              | Process only the top N files ranked by significance score. `0` = process all.                                                                                                        |
| `-ScoreOnly` | switch | off              | Print the ranked file list with scores and exit without running Claude.                                                                                                              |
| `-Delta`     | switch | off              | Delta-only mode: output only NEW insights via `file_doc_prompt_pass2_delta.txt` (smaller, faster).                                                                                   |
| `-Test`      | switch | off              | Run the built-in unit test suite.                                                                                                                                                    |

## Scoring Algorithm

Each candidate file receives a score calculated as:

```
score = (incoming_xref_count * 3) + (source_line_count / 100)
```

If the file has Serena LSP context (`.serena_context.txt`), the score is halved (since Pass 1 already had rich context for that file). Files are processed in descending score order.

## How It Is Invoked

**Standalone:**
```powershell
cd C:\Coding\Epic_Games\UnrealEngine
.\..\..\LLM_Analysis\Analysis\archpass2.ps1 -Top 50
```

**Via AnalysisPipeline.py:**
Called as the sixth and final analysis step:
```
python C:\Coding\LLM_Analysis\Analysis\AnalysisPipeline.py
```

## Input Files

| Input                                              | Location                                           | Description                                              |
| -------------------------------------------------- | -------------------------------------------------- | -------------------------------------------------------- |
| Source files                                       | `<repo>/<TargetDir>/`                              | Original source code                                     |
| Pass 1 docs                                        | `<repo>/architecture/<rel>.md`                     | First-pass analysis for each file                        |
| Architecture overview                              | `<repo>/architecture/architecture.md`              | Global architecture context                              |
| Xref index                                         | `<repo>/architecture/xref_index.md`                | Cross-reference data                                     |
| Targeted context                                   | `<repo>/architecture/.pass2_context/<rel>.ctx.txt` | Preferred over global context when available             |
| `.env`                                             | `../Common/.env`                                   | Configuration                                            |
| `file_doc_prompt_pass2.txt` / `..._delta.txt`      | Script directory                                   | Prompt schemas                                           |

## Output Files

| Output        | Location                                          | Description                                   |
| ------------- | ------------------------------------------------- | --------------------------------------------- |
| Pass 2 docs   | `<repo>/architecture/<rel_path>.pass2.md`         | Enhanced analysis with cross-cutting insights |
| Hash database | `<repo>/architecture/.pass2_state/hashes.tsv`     | Incremental skip tracking                     |
| Error log     | `<repo>/architecture/.pass2_state/last_error.log` | Timestamped failures                          |

## Environment Variables / .env Keys

| Key                       | Default                  | Description                                                       |
| ------------------------- | ------------------------ | ----------------------------------------------------------------- |
| `CLAUDE_MODEL`            | `sonnet`                 | Claude CLI model                                                  |
| `CLAUDE_MAX_TURNS`        | `1`                      | Max Claude conversation turns                                     |
| `CLAUDE_OUTPUT_FORMAT`    | `text`                   | Claude CLI output format                                          |
| `CLAUDE1_CONFIG_DIR`      | (must be set)            | First Claude account; selected via `-Claude1`                     |
| `CLAUDE2_CONFIG_DIR`      | (must be set)            | Second Claude account; selected by default                        |
| `TIERED_MODEL`            | `1`                      | Auto-upgrade complex files to `HIGH_COMPLEXITY_MODEL`             |
| `HIGH_COMPLEXITY_MODEL`   | `sonnet`                 | Model used for complex files                                      |
| `JOBS`                    | `2`                      | Parallel job count (overridden by `-Jobs`)                        |
| `MAX_RETRIES`             | `2`                      | Retries on transient errors                                       |
| `RETRY_DELAY`             | `5`                      | Seconds between retries                                           |
| `INCLUDE_EXT_REGEX`       | Preset-dependent         | File extension include pattern                                    |
| `EXCLUDE_DIRS_REGEX`      | Preset-dependent         | Directory exclude pattern                                         |
| `EXTRA_EXCLUDE_REGEX`     | `""`                     | Additional exclude pattern                                        |
| `CODEBASE_DESC`           | Preset-dependent         | Codebase description                                              |
| `DEFAULT_FENCE`           | `c`                      | Default Markdown fence language                                   |
| `PROMPT_FILE_P2`          | `file_doc_prompt_pass2.txt` (in script dir) | Override the Pass 2 prompt file path           |

## Exit Codes

| Code | Meaning                                                                                    |
| ---- | ------------------------------------------------------------------------------------------ |
| `0`  | Success (or nothing to do / score-only mode)                                               |
| `1`  | Missing `architecture.md` or `xref_index.md`, target directory not found, or no candidates |
| `2`  | Missing `archpass2_worker.ps1`, missing prompt file, or missing Claude config dir          |

## Examples

**Example 1: Process the top 50 most significant files**
```powershell
cd C:\Coding\Epic_Games\UnrealEngine
.\..\..\LLM_Analysis\Analysis\archpass2.ps1 -Top 50
```

**Example 2: Preview file rankings without running Claude**
```powershell
.\Analysis\archpass2.ps1 -ScoreOnly -Top 20
```
Prints the top 20 files with their score, line count, and incoming reference count.

**Example 3: Re-analyze specific files in delta mode**
```powershell
.\Analysis\archpass2.ps1 -Delta -Only "Engine/Source/Runtime/Renderer/Private/DeferredShadingRenderer.cpp,Engine/Source/Runtime/Engine/Private/Actor.cpp"
```

## Related

- `Analysis/archpass2_worker.ps1` — per-batch worker dispatched via `Start-Job`
- `Analysis/archpass2_context.ps1` — Step 5; produces targeted context that this script consumes
- `Analysis/AnalysisPipeline.py` — orchestrator that runs this as Step 6 per subsection
- `Common/llm_common.ps1` / `llm_core.ps1` — shared infrastructure
- `Common/.env` — config keys documented above
- `Documentation/archpass2_context.md` — companion context-builder docs
