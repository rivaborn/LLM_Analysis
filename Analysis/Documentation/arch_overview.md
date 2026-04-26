# arch_overview.ps1 -- Architecture Overview Generator (Claude CLI)

## Purpose

`arch_overview.ps1` synthesizes the per-file Markdown documents produced by `archgen.ps1` into a high-level architecture overview. It reads the `# heading` and `## Purpose` sections from each per-file doc, groups them by subsystem directory, and asks the **Claude CLI** to produce a unified architecture document covering subsystem responsibilities, key files, and cross-subsystem dependencies.

The script supports two modes: **single-pass** (when the total summary data fits within Claude's context window) and **chunked** (default for larger codebases). In chunked mode it auto-discovers subsystem directories, generates a per-subsystem overview for each chunk, then runs a second synthesis pass to merge them into a final `architecture.md`. If synthesis fails, it falls back to concatenating the subsystem overviews.

Like `archgen.ps1`, it supports dual-account rotation via `-Claude1` and an optional tiered-model upgrade for the synthesis pass via `TIERED_MODEL`.

## Prerequisites

| Requirement                | Details                                                              |
| -------------------------- | -------------------------------------------------------------------- |
| PowerShell 5.1+ or pwsh 7+ | Uses `Set-StrictMode -Version Latest`                                |
| `claude` CLI on PATH       | Anthropic command-line client; authenticated against at least one account |
| `../Common/llm_common.ps1` | Shared module (`Read-EnvFile`, `Cfg`)                                |
| `../Common/.env`           | Configuration                                                        |
| Per-file docs              | Output of `archgen.ps1` must exist in `<repo>/architecture/`         |

## Usage

```powershell
.\arch_overview.ps1 [-TargetDir <dir>] [-Chunked] [-Single] [-Clean] [-Claude1] [-Full]
                    [-EnvFile <path>] [-RepoRoot <path>] [-Test]
```

### CLI Options

| Parameter    | Type   | Default          | Description                                                                                                                                                                          |
| ------------ | ------ | ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `-TargetDir` | string | `"all"`          | Subsystem directory to summarize. `"all"` or `"."` processes the entire `architecture/` tree. A specific path (e.g. `Engine/Source/Runtime/Core`) limits scope.                       |
| `-Chunked`   | switch | off              | Force chunked mode (per-subsystem chunks then synthesis pass).                                                                                                                       |
| `-Single`    | switch | off              | Force single-pass mode even if summary data exceeds the chunk threshold.                                                                                                             |
| `-Clean`     | switch | off              | Remove all `*architecture.md` and `*diagram_data.md` files before generating.                                                                                                        |
| `-Claude1`   | switch | off              | Use the `CLAUDE1_CONFIG_DIR` Claude account instead of the default `CLAUDE2_CONFIG_DIR`.                                                                                             |
| `-Full`      | switch | off              | Force full regeneration (skip incremental).                                                                                                                                          |
| `-EnvFile`   | string | `../Common/.env` | Alternative `.env` configuration file.                                                                                                                                               |
| `-RepoRoot`  | string | `""` (auto)      | Override for the target repo root. When empty, auto-detects via CWD then `git rev-parse --show-toplevel`. `AnalysisPipeline.py` forwards `--repo-root` to every worker via this arg. |
| `-Test`      | switch | off              | Run the built-in unit test suite.                                                                                                                                                    |

## How It Is Invoked

**Standalone:**
```powershell
cd C:\Coding\Epic_Games\UnrealEngine
.\..\..\LLM_Analysis\Analysis\arch_overview.ps1
```

**Via AnalysisPipeline.py:**
Called as the fourth analysis step (after `archgen.ps1`, `archxref.ps1`, `archgraph.ps1`):
```
python C:\Coding\LLM_Analysis\Analysis\AnalysisPipeline.py
```

## Input Files

| Input                         | Location                      | Description                                                                          |
| ----------------------------- | ----------------------------- | ------------------------------------------------------------------------------------ |
| Per-file docs                 | `<repo>/architecture/**/*.md` | Markdown docs from `archgen.ps1` (excludes state dirs, pass2 docs, meta files)       |
| `.env`                        | `../Common/.env`              | Configuration                                                                        |

## Output Files

| Output                  | Location                                             | Description                                                                         |
| ----------------------- | ---------------------------------------------------- | ----------------------------------------------------------------------------------- |
| Architecture overview   | `<repo>/architecture/architecture.md`                | Final synthesized overview (or `<prefix>_architecture.md` when `-TargetDir` is set) |
| Per-subsystem overviews | `<repo>/architecture/<subsystem>_architecture.md`    | Individual subsystem overviews (chunked mode only)                                  |
| Diagram data            | `<repo>/architecture/diagram_data.md`                | File Purpose / Core Responsibilities / External Dependencies extracted per file     |
| Error log               | `<repo>/architecture/.overview_state/last_claude_error.log` | Timestamped error entries                                                    |

## Environment Variables / .env Keys

| Key                       | Default                         | Description                                                                |
| ------------------------- | ------------------------------- | -------------------------------------------------------------------------- |
| `CLAUDE_MODEL`            | `sonnet`                        | Claude CLI model                                                           |
| `CLAUDE_MAX_TURNS`        | `1`                             | Max Claude conversation turns per call                                     |
| `CLAUDE_OUTPUT_FORMAT`    | `text`                          | Claude CLI output format                                                   |
| `CLAUDE1_CONFIG_DIR`      | (must be set)                   | First Claude account config dir; selected via `-Claude1`                   |
| `CLAUDE2_CONFIG_DIR`      | (must be set)                   | Second Claude account config dir; selected by default                      |
| `TIERED_MODEL`            | `1`                             | When `1`, switches the synthesis model to `HIGH_COMPLEXITY_MODEL`          |
| `HIGH_COMPLEXITY_MODEL`   | `sonnet`                        | Model used for synthesis when tiered mode is enabled                       |
| `CODEBASE_DESC`           | `"game engine / game codebase"` | Codebase description for LLM context                                       |
| `CHUNK_THRESHOLD`         | `1500`                          | Summary line count above which chunked mode is used                        |

## Exit Codes

| Code | Meaning                                                                                             |
| ---- | --------------------------------------------------------------------------------------------------- |
| `0`  | Success                                                                                             |
| `1`  | No per-file docs found (run `archgen.ps1` first), or LLM synthesis failed in single-pass mode      |
| `2`  | Missing Claude config dir                                                                           |

## Examples

**Example 1: Generate overview for the full codebase**
```powershell
cd C:\Coding\Epic_Games\UnrealEngine
.\..\..\LLM_Analysis\Analysis\arch_overview.ps1
```

**Example 2: Force single-pass for a small subsystem**
```powershell
.\Analysis\arch_overview.ps1 -TargetDir Engine/Source/Runtime/Core -Single
```

**Example 3: Clean and regenerate using the alternate Claude account**
```powershell
.\Analysis\arch_overview.ps1 -Clean -Claude1
```

## Related

- `Analysis/archgen.ps1` — per-file doc generator (Step 1; produces input for this script)
- `Analysis/AnalysisPipeline.py` — orchestrator that runs this as Step 4 per subsection
- `Common/llm_common.ps1` / `llm_core.ps1` — shared infrastructure
- `Common/.env` — config keys documented above
- `Documentation/AnalysisPipeline.md` — orchestrator docs
