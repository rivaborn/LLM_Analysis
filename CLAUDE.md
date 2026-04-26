# CLAUDE.md -- Project Context

## Project Overview

Architecture documentation toolkit for Unreal Engine source code. Generates per-file and subsystem-level architecture docs using the **Claude CLI** (`claude -p`), with optional LSP-powered semantic analysis via clangd.

**Target Codebase:** Unreal Engine 5.7.3 (Epic Games), `C:\Coding\Epic_Games\UnrealEngine` (fork of EpicGames/UnrealEngine, branch `release`).
**LLM Backend:** Anthropic Claude via the local `claude` CLI. Default model `haiku`, with tiered auto-upgrade to `sonnet` for complex files.
**Sister Toolkit:** `C:\Coding\LocalLLM_Analysis` is the Ollama variant of this same toolkit. The two share an identical `Common/llm_common.ps1` shim and `Common/file_helpers.ps1`; they differ in `Common/llm_core.ps1` (lean here, full Ollama API client there) and `Common/.env` (Claude CLI keys here, Ollama keys there).
**System:** Windows 11, 32 GB RAM.

## Directory Layout

The toolkit is split into a shared module folder (`Common/`) and a pipeline folder (`Analysis/`). Drop the whole `LLM_Analysis/` directory anywhere; scripts find each other via sibling-relative paths.

```
<toolkit root>/                     (e.g. C:\Coding\LLM_Analysis)
  Common/
    .env                            Pipeline configuration (Claude CLI keys, preset, UE subsections)
    llm_common.ps1                  Shim that dot-sources the two sub-modules
    llm_core.ps1                    Read-EnvFile, Cfg, Test-CancelKey (lean — no Ollama functions)
    file_helpers.ps1                Get-Preset, Get-FenceLang, Get-SHA1, Test-TrivialFile, Get-OutputBudget, Truncate-Source, Resolve-ArchFile, Get-SerenaContextDir, Load-CompressedLSP, Show-SimpleProgress
    Documentation/                  3 module docs (llm_common.md, llm_core.md, file_helpers.md)
  Analysis/
    archgen.ps1                     Per-file docs (Claude CLI; tiered model; dual-account)
    archgen_worker.ps1              Per-batch worker dispatched by archgen.ps1 via Start-Job
    arch_overview.ps1               Subsystem synthesis (Claude CLI)
    archpass2.ps1                   Context-aware Pass 2 (Claude CLI)
    archpass2_worker.ps1            Per-batch worker for archpass2
    archpass2_context.ps1           Per-file targeted context (no Claude)
    archxref.ps1                    Cross-reference index (no Claude)
    archgraph.ps1                   Mermaid call graph + subsystem diagrams (no Claude)
    serena_extract.ps1              clangd LSP wrapper
    serena_extract.py               LSP extraction backend (Python, ~1500 LOC)
    AnalysisPipeline.py             Single-mode orchestrator
    *_prompt.txt                    8 Claude prompt schemas (file_doc_prompt, _lsp, _minimal, _pass2, etc.)
    ue_preamble.txt                 Engine-knowledge preamble
    statusline.md                   Progress display template
    Documentation/                  9 per-script .md files
```

The current `LLM_Analysis/` lives at `C:\Coding\LLM_Analysis`. The target UE source lives separately at `C:\Coding\Epic_Games\UnrealEngine`.

## Invocation

Scripts are launched from the **target repo root** (the UE checkout):

```powershell
cd C:\Coding\Epic_Games\UnrealEngine
.\..\..\LLM_Analysis\Analysis\archgen.ps1 -Preset unreal
```

Or override with `-RepoRoot` / `--repo-root` to point anywhere:

```powershell
.\Analysis\archgen.ps1 -RepoRoot C:\Coding\Epic_Games\UnrealEngine -Preset unreal
```

Each PS1 finds `.env` at `..\Common\.env` relative to itself. `AnalysisPipeline.py` reads `..\Common\.env` for the subsection list and uses CWD as the repo root by default (or `--repo-root`).

## Pipeline Order

```
0 (free)   .\Analysis\serena_extract.ps1        LSP symbol data via clangd (optional, C++ only)
1          .\Analysis\archgen.ps1                Per-file docs (Claude haiku → sonnet for complex)
2 (free)   .\Analysis\archxref.ps1              Cross-reference index
3 (free)   .\Analysis\archgraph.ps1             Mermaid call graph diagrams
4          .\Analysis\arch_overview.ps1          Subsystem architecture overview (Claude sonnet)
4b (free)  .\Analysis\archpass2_context.ps1      Per-file targeted context
5          .\Analysis\archpass2.ps1              Selective Pass 2 re-analysis (Claude haiku → sonnet)
```

Or in one command via the orchestrator:

```powershell
cd C:\Coding\Epic_Games\UnrealEngine
python C:\Coding\LLM_Analysis\Analysis\AnalysisPipeline.py
```

The orchestrator walks every entry in the `#Subsections begin/end` block of `Common/.env` and runs all six steps for each, renaming `architecture/` to `N. <subsection_sanitized>/` after each one.

## Key Configuration (`Common/.env`)

### Claude CLI accounts and model
- `CLAUDE1_CONFIG_DIR`, `CLAUDE2_CONFIG_DIR` -- dual-account config dirs for rate-limit rotation. Selected via `-Claude1` (the second is default).
- `CLAUDE_MODEL` -- default model (`haiku`, `sonnet`, `opus`, etc.)
- `CLAUDE_MAX_TURNS` -- max conversation turns per call (default `1`)
- `CLAUDE_OUTPUT_FORMAT` -- `text` or `json`
- `TIERED_MODEL=1` -- auto-upgrade complex files to `HIGH_COMPLEXITY_MODEL`
- `HIGH_COMPLEXITY_MODEL=sonnet` -- model used for complex files when tiered mode is on

### Concurrency / retries
- `JOBS` -- parallel `Start-Job` count for archgen/archpass2 (overridden by per-script `-Jobs`)
- `MAX_RETRIES`, `RETRY_DELAY` -- per-file retry behaviour on transient errors
- `BUNDLE_HEADERS=1` / `MAX_BUNDLED_HEADERS=8` -- header bundling for `.cpp` analysis

### Codebase / file handling
- `PRESET=unreal` (alias of `ue4`/`ue5`)
- `INCLUDE_EXT_REGEX` / `EXCLUDE_DIRS_REGEX` -- preset overrides for file selection
- `MAX_FILE_LINES=3000` -- truncate huge UE headers (Actor.h etc.)
- `CHUNK_THRESHOLD=1500` -- subsystem chunk size for `arch_overview.ps1`
- `SKIP_TRIVIAL=1` / `MIN_TRIVIAL_LINES=20` -- skip generated/trivial files with stub docs
- `CODEBASE_DESC` -- human-readable codebase description fed to the LLM

### Subsections
- `#Subsections begin / #Subsections end` block lists subdirectories for `AnalysisPipeline.py` to walk in order. Pre-populated with 14 UE 5.x runtime subsystems (Core, CoreUObject, Engine, Renderer, RenderCore, RHI, PhysicsCore, AudioMixerCore, AIModule, GameplayAbilities, SlateCore, Slate, UMG, NetworkCore). Comment lines (e.g. `# Memory, containers, math`) are ignored.

### Cross-pipeline integration (commented out by default)
- `ARCHITECTURE_DIR` / `SERENA_CONTEXT_DIR` -- consumed by `Resolve-ArchFile` / `Get-SerenaContextDir` helpers, used by a future Debug pipeline. Not active in analysis-only runs.

## Architecture

- All worker scripts dot-source `Common/llm_common.ps1` (a 17-line shim that loads `llm_core.ps1` + `file_helpers.ps1`).
- Worker scripts find `.env` at `Join-Path $PSScriptRoot '..\Common\.env'`.
- Prompt `.txt` files load from `$PSScriptRoot` (same directory as the worker script).
- Press **Ctrl+Q** to cancel the current pipeline cleanly (handled by `Test-CancelKey` in `llm_core.ps1`).
- Text-processing scripts (`archxref.ps1`, `archgraph.ps1`, `archpass2_context.ps1`) have no LLM dependency.
- `archgen.ps1` and `archpass2.ps1` are parallel (Start-Job) — each spawns N background jobs that each invoke the corresponding `*_worker.ps1` synchronously.

## clangd / LSP (Optional)

- Generate `compile_commands.json` from inside the UE checkout via UBT:
  ```
  .\Engine\Build\BatchFiles\RunUBT.bat UnrealEditor Win64 Development -Mode=GenerateClangDatabase -engine -progress
  ```
- Run `serena_extract.ps1 -Preset unreal` to spawn clangd and produce per-file `.serena_context.txt` files
- Index cached at `<repo>/.cache/clangd/index/` for faster subsequent runs
- Output goes to `<repo>/architecture/.serena_context/<rel>.serena_context.txt`
- When this directory exists, `archgen.ps1` auto-selects the LSP-aware prompt variant (`file_doc_prompt_lsp.txt`)

## Documentation Files

Per-script docs live in `Analysis/Documentation/`:

- `archgen.md`
- `arch_overview.md`
- `archpass2.md`
- `archpass2_context.md`
- `archxref.md`
- `archgraph.md`
- `serena_extract.md` / `serena_extract_py.md`
- `AnalysisPipeline.md`

Shared module docs live in `Common/Documentation/`:

- `llm_common.md` (shim)
- `llm_core.md` (Read-EnvFile, Cfg, Test-CancelKey)
- `file_helpers.md` (presets, hashing, truncation, etc.)

## Presets

Defined in `Common/file_helpers.ps1`. Use `-Preset` flag or `PRESET` in `.env`.

| Preset                      | Description                                                       |
| --------------------------- | ----------------------------------------------------------------- |
| `unreal` / `ue4` / `ue5`    | Unreal Engine C++/C# source (Epic Games)                          |
| `quake` / `doom` / `idtech` | id Software / Quake-family                                        |
| `generals` / `cnc` / `sage` | C&C Generals / Zero Hour (SAGE) and Remastered TD/RA              |
| `godot`                     | Godot (C++/GDScript/C#)                                           |
| `unity`                     | Unity (C#/shaders)                                                |
| `source` / `valve`          | Source Engine                                                     |
| `rust`                      | Rust engines (Bevy, etc.)                                         |
| `python` / `py`             | Python codebases                                                  |
