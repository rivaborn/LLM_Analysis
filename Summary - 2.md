# Archgen + Serena + Unreal Engine: Session Summary

## Overview

This document summarizes the complete setup, troubleshooting, findings, and solutions from integrating Serena (an LSP-based semantic code analysis MCP server) with the archgen PowerShell toolchain for architecture documentation of Unreal Engine 5.7.3 source code. It also covers generating a `.env` config for analyzing the Quake 2 Rerelease DLL codebase.

---

## 1. Archgen Toolchain Recap

The archgen toolchain is a set of PowerShell scripts that use Claude CLI to generate per-file architecture documentation for large game engine codebases. The pipeline runs in this order:

1. **`archgen.ps1` (Pass 1):** Walks every source file, bundles local `#include` headers for context, sends each to Claude CLI, and generates a structured `.md` doc per file. Runs in parallel with configurable job count. Tracks progress, retries on transient failures, and maintains a SHA1 hash database for resumability. Supports `--preset` for common engines.

2. **`archxref.ps1`:** Parses all pass 1 docs and builds a cross-reference index — function-to-file mappings, call graph edges, global state ownership, header dependency counts, and subsystem interfaces. Pure text processing, no Claude calls. Completes in seconds.

3. **`archgraph.ps1`:** Extracts function call edges from pass 1 docs and generates Mermaid diagrams — function-level call graphs grouped by subsystem, and subsystem dependency diagrams with cross-boundary call counts. No Claude calls.

4. **`arch_overview.ps1`:** Synthesizes all pass 1 docs into a subsystem-level architecture overview. Automatically chunks by directory for large codebases. Recursively splits oversized subsystems.

5. **`archpass2.ps1` (Pass 2):** Re-analyzes source files with the architecture overview and cross-reference index injected as context. Produces enriched `.pass2.md` docs with architectural role, cross-references, design patterns, data flow, and learning notes. Supports `--only` for targeted analysis.

### Prompt Files

- **`file_doc_prompt.txt`:** Standard per-file analysis prompt — file purpose, responsibilities, key types, key functions with signatures, global state, external dependencies, control flow.
- **`file_doc_prompt_learn.txt`:** Learning-oriented variant — adds "Why This File Exists", prerequisites, design patterns, historical context, and study questions.
- **`file_doc_prompt_pass2.txt`:** Pass 2 enrichment prompt — architectural role, cross-references (incoming/outgoing), design patterns and rationale, data flow, learning notes, potential issues.

---

## 2. Quake 2 Rerelease DLL Configuration

### Codebase Profile

- **Repo:** https://github.com/id-Software/quake2-rerelease-dll
- **Language:** C++17 (compiles under C++17 and C++20)
- **Structure:** Combined codebase merging baseq2, CTF, Rogue (Ground Zero), and Xatrix (The Reckoning) into a unified game DLL
- **Key features:** New server-game API (game_export_t/game_import_t), client game module (cgame), instanced items, split-screen co-op, bot support, nav editor integration, N64 campaign support
- **Size:** Moderate (~150 source files under `rerelease/`)

### Generated .env File

Key configuration decisions:

| Setting | Value | Rationale |
|---------|-------|-----------|
| `PRESET` | `quake` | Gives correct include/exclude patterns for id Software codebases |
| `CLAUDE_MODEL` | `haiku` | Sufficient for straightforward C++ game logic; fast for parallel jobs |
| `JOBS` | `8` | Matches existing parallelism tuning |
| `CODEBASE_DESC` | Custom | Calls out combined expansion packs, KEX API, C++17, split-screen/bots, and file naming conventions (`m_*.cpp`, `p_*.cpp`, `g_*.cpp`) |
| `EXCLUDE_DIRS_REGEX` | Added `fmt` | Excludes bundled fmtlib source from analysis |
| `BUNDLE_HEADERS` | `1` | Enabled with max 8 bundled headers |
| `CHUNK_THRESHOLD` | `1500` | Should fit single overview pass but threshold set as safety net |

### Usage

```powershell
# From the quake2-rerelease-dll repo root, with .env in place:
.\archgen.ps1 -TargetDir rerelease -Preset quake
```

---

## 3. Serena Integration Plan

### What is Serena

Serena (https://github.com/oraios/serena) is a coding agent toolkit that provides semantic code retrieval and editing through Language Server Protocol (LSP) integration. It supports 30+ languages including C/C++ via clangd. It runs as an MCP (Model Context Protocol) server that integrates with Claude Code.

### Value Proposition for Archgen

Serena's LSP integration with clangd provides ground-truth symbol definitions, call hierarchies, and cross-file reference data — significantly more accurate than the text-mined cross-references from `archxref.ps1`. The integration strategy:

- **Pass 1:** No changes. Header bundling works well enough for individual file analysis.
- **New step (serena_extract.ps1):** Query Serena for each file's symbols and cross-references, producing `.serena_context.txt` files.
- **archxref.ps1:** Unchanged. Still provides valuable global summary.
- **Pass 2:** Enhanced — inject Serena's LSP data as a fourth context source alongside the architecture overview, xref index, and pass 1 doc.

### Serena Extraction Script

A new `serena_extract.ps1` script was designed to:

- Run sequentially (not parallel) since each call uses Claude Code with multi-turn Serena tool use
- Use `--max-turns 10` for multi-step tool orchestration (get_symbols_overview → find_referencing_symbols → find_symbol)
- Use sonnet model (not haiku) for reliable tool-use planning
- Produce resumable `.serena_context.txt` files (skip if already exists)
- Gracefully degrade — pass 2 works fine without Serena data for files where extraction wasn't run

---

## 4. Unreal Engine 5.7.3 Setup

### Repository Details

- **Repo:** https://github.com/rivaborn/UnrealEngine (fork of EpicGames/UnrealEngine)
- **Branch:** `release`
- **Version:** UE 5.7.3
- **Location:** `C:\Coding\Epic_Games\UnrealEngine`

### 4.1 Setup.bat Hung on Prerequisites

**Problem:** `Setup.bat` hung for hours on "Installing prerequisites..."

**Root cause:** The prerequisites installer opened a silent dialog (UAC or .NET/VC++ runtime prompt) behind the terminal window, waiting for user input.

**Solution:** Skip prerequisites and run the dependency downloader directly. In UE 5.7.3, the `GitDependencies` executable is in a platform-specific subfolder (not at the top level as in older UE versions):

```powershell
# UE 5.7.3 path (NOT .\Engine\Binaries\DotNET\GitDependencies.exe)
.\Engine\Binaries\DotNET\GitDependencies\win-x64\GitDependencies.exe
```

**Finding:** The old path `.\Engine\Binaries\DotNET\GitDependencies.exe` does not exist in UE 5.7.3. The binary layout changed to self-contained .NET with platform subfolders (`win-x64`, `linux-x64`, `osx-arm64`, `osx-x64`).

Prerequisites (Visual C++ redistributables, .NET Framework 4.6.2+, DirectX Runtime) are typically already present if VS2022 with the C++ workload is installed.

### 4.2 Generating compile_commands.json

**Requirement:** A `compile_commands.json` at the repo root is essential for clangd/Serena to provide semantic code analysis.

**Key insight:** Since `rivaborn/UnrealEngine` is the engine source (not a game project), the command differs from game-project analysis — no `-project=` or `-game` flags. The target is the engine editor build target.

**Step 1: Install Clang**

The first attempt failed with:

```
Clang x64 must be installed in order to build this target.
```

**Solution:** Install via Visual Studio Installer → Individual Components:
- C++ Clang Compiler for Windows
- C++ Clang-cl for v143 build tools (x64/x86)

**Step 2: Generate the database**

```powershell
# UE 5.x uses "UnrealEditor" (not "UE4Editor")
.\Engine\Build\BatchFiles\RunUBT.bat `
    UnrealEditor Win64 Development `
    -Mode=GenerateClangDatabase `
    -engine -progress
```

**Result:** Successfully generated a 23 MB `compile_commands.json` with ~43,000 C++ translation units. The file contains proper UBT-generated entries with clang-cl commands referencing `.rsp` response files that contain full include paths, defines, and compiler flags.

### 4.3 compile_commands.json Format Details

The generated database uses response files (`@"...rsp"`) rather than inline flags:

```json
{
    "file": "C:/Coding/Epic_Games/UnrealEngine/Engine/Intermediate/Build/Win64/x64/UnrealEditorGCD/Development/AIGraph/Module.AIGraph.gen.cpp",
    "command": "\"C:/Program Files/Microsoft Visual Studio/18/Community/VC/Tools/Llvm/x64/bin/clang-cl.exe\" @\"../Intermediate/Build/Win64/x64/UnrealEditorGCD/Development/AIGraph/Module.AIGraph.gen.cpp.obj.rsp\"",
    "directory": "C:/Coding/Epic_Games/UnrealEngine/Engine/Source",
    "output": "..."
}
```

The `.rsp` files were verified to exist and contain proper `-I` include paths, `-D` defines, target architecture flags, and C++ standard settings.

---

## 5. Serena Installation and Troubleshooting

### 5.1 Install uv

```powershell
powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
```

### 5.2 Project Configuration

**Global config:** `$HOME\.serena\serena_config.yml`

**Critical finding: projects format.** The name/path dict format caused a fatal `CommentedMap` TypeError in Serena's config parser:

```yaml
# BROKEN — Serena's parser passes the dict to Path() which rejects CommentedMap
projects:
  - name: UnrealEngine
    path: "C:\\Coding\\Epic_Games\\UnrealEngine"

# ALSO BROKEN — same error with plain path strings
projects:
  - "C:\\Coding\\Epic_Games\\UnrealEngine"
```

**Root cause:** A bug in Serena's `serena_config.py` line 828/831 where `ruamel.yaml`'s `CommentedMap` objects are passed directly to `pathlib.Path()` without converting to string. This bug exists in both the upstream `oraios/serena` repo and the `rivaborn/serena` fork. It is NOT a Python version issue — it reproduces on both Python 3.14 and 3.12.

**Status:** Unresolved as of this session. Serena starts but the config parser crashes before it can read project paths. This needs a code fix in Serena's `from_config_file()` method to call `str(path)` before passing to `Path()`.

**Workaround that works:** Pass the project path directly via CLI `--project` flag, bypassing the config file's projects list. The crash occurs when Serena reads the config file's projects section, but the `--project` CLI argument is processed separately.

**Per-project config:** `C:\Coding\Epic_Games\UnrealEngine\.serena\project.yml`

```yaml
name: UnrealEngine
languages:
  - cpp

language_servers:
  cpp:
    arguments:
      - "-j=4"
      - "--background-index"
      - "--pch-storage=disk"

ignored_paths:
  - ThirdParty
  - Intermediate
  - Binaries
  - Build
  - DerivedDataCache
  - Saved
  - GeneratedFiles
  - AutomationTool
  - .git

read_only: true
```

### 5.3 Claude Code MCP Registration

**Problem:** The standard `claude mcp add` command failed because `--from` was parsed as a Claude flag, not passed to `uvx`:

```powershell
# BROKEN
claude mcp add serena -- uvx --from "git+https://github.com/rivaborn/serena" ...
# error: unknown option '--from'
```

**Solution:** Use the JSON registration form:

```powershell
claude mcp add-json "serena" '{\"command\":\"uvx\",\"args\":[\"--python\",\"3.12\",\"--from\",\"git+https://github.com/oraios/serena\",\"serena\",\"start-mcp-server\",\"--context\",\"claude-code\",\"--project\",\"C:\\Coding\\Epic_Games\\UnrealEngine\"]}'
```

### 5.4 Python Version

**Finding:** The system Python is 3.14 (pre-release). While initially suspected as the cause of the `CommentedMap` error, testing with Python 3.12 via `uvx --python 3.12` showed the same error — confirming it's a Serena bug, not a Python compatibility issue.

**Recommendation:** Use `--python 3.12` anyway for stability, since 3.14 is pre-release and may have other incompatibilities.

```powershell
uv python install 3.12
```

### 5.5 Windows clangd Platform-ID Bug

**Known issue:** Serena issue #250 — `runtime_dependencies.json` uses `"windows-x64"` but the code checks for `"win-x64"`, causing clangd auto-download to fail on Windows.

**Fix:** Either patch the JSON file or install clangd manually via VS2022 components or `winget install LLVM.LLVM`. In this session, clangd was installed via the VS2022 Clang components, so the auto-download bug was bypassed.

---

## 6. clangd Indexing Challenges with Unreal Engine

### 6.1 Background Indexing Crashes

**Problem:** With `Index.Background: Build` (the default), clangd queued all 43,000 translation units for parallel background indexing, consuming all available RAM and CPU, crashing the system.

**Immediate fix (applied by Claude Code):** A `.clangd` config file at the UE repo root with:

```yaml
Index:
  Background: Skip
CompileFlags:
  Remove:
    - -W*
Diagnostics:
  UnusedIncludes: None
  MissingIncludes: None
  ClangTidy: false
```

This made Serena usable but degraded — only regex pattern search worked (`search_for_pattern`), not semantic tools (`find_symbol`, `find_referencing_symbols`).

### 6.2 Impact of Disabled Background Indexing

With `Index.Background: Skip`:

| Tool | Status | Notes |
|------|--------|-------|
| `search_for_pattern` | Works | Regex-based, doesn't need LSP |
| `find_symbol` | Partially works | Only for files clangd has opened in current session |
| `get_symbols_overview` | Partially works | Same limitation |
| `find_referencing_symbols` | Severely degraded | Can only find references in already-parsed files, not across all 43K TUs |
| `list_dir`, `find_file` | Works | Filesystem-based |

The `find_referencing_symbols` degradation is the critical loss — it was the primary reason for integrating Serena.

### 6.3 Stable Overnight Indexing Solution

**Goal:** Let clangd fully index UE overnight with background indexing enabled, without crashing.

**System:** 32 GB RAM

**Configuration for stable indexing:**

**`.clangd` at repo root:**

```yaml
Index:
  Background: Build
  StandardLibrary: No

CompileFlags:
  Remove:
    - -W*
    - -fdiagnostics*

Diagnostics:
  UnusedIncludes: None
  MissingIncludes: None
  ClangTidy: false
  Suppress: ["*"]

Completion:
  AllScopes: false
```

**`.serena/project.yml` with clangd arguments:**

```yaml
language_servers:
  cpp:
    arguments:
      - "-j=4"
      - "--background-index"
      - "--pch-storage=disk"
```

**Key flags explained:**

| Flag | Purpose | RAM Impact |
|------|---------|------------|
| `-j=4` | Limits background indexing to 4 parallel threads instead of all cores | Caps clangd at ~8–12 GB instead of 25+ GB |
| `--pch-storage=disk` | Stores precompiled header data on disk instead of RAM | Significant memory savings at cost of disk I/O |
| `--background-index` | Explicitly enables full background indexing | Required — overrides any `.clangd` Skip setting |
| `Diagnostics: Suppress: ["*"]` | Suppresses all diagnostics | Prevents expensive full-file analysis on every file |
| `StandardLibrary: No` | Skips standard library indexing | Saves memory and time |

**Monitoring command:**

```powershell
while ($true) {
    $p = Get-Process clangd -ErrorAction SilentlyContinue
    if ($p) {
        $mem = [math]::Round($p.WorkingSet64 / 1GB, 2)
        $cpu = $p.CPU
        Write-Host "$(Get-Date -Format 'HH:mm:ss') | clangd RAM: ${mem} GB | CPU time: ${cpu}s"
    } else {
        Write-Host "$(Get-Date -Format 'HH:mm:ss') | clangd not running"
    }
    Start-Sleep 60
}
```

**Fallback:** If clangd exceeds 25 GB RAM at `-j=4`, reduce to `-j=2`.

**Expected result:** After overnight indexing, a cached index at `.cache/clangd/` (several hundred MB to a few GB). Subsequent Serena sessions load from cache in minutes.

---

## 7. Complete Workflow — Final Pipeline

### For Quake 2 Rerelease (small codebase, no Serena needed)

```powershell
cd <quake2-rerelease-dll repo root>
# Copy .env.q2rerelease.ps1 as .env
.\archgen.ps1 -TargetDir rerelease -Preset quake -Jobs 8
.\archxref.ps1
.\arch_overview.ps1 -Preset quake
.\archpass2.ps1 -Preset quake -Jobs 8
```

### For Unreal Engine (with Serena, after overnight indexing)

```powershell
cd C:\Coding\Epic_Games\UnrealEngine

# 1. Pass 1: per-file docs (parallel, haiku, no Serena needed)
.\archgen.ps1 -Preset unreal -Jobs 8

# 2. Cross-reference index (no Claude calls, instant)
.\archxref.ps1

# 3. Architecture overview (chunked for UE)
.\arch_overview.ps1 -Preset unreal

# 4. Serena LSP extraction (sequential, sonnet, multi-turn)
#    Only effective after clangd has completed background indexing
.\serena_extract.ps1

# 5. Pass 2: context-aware re-analysis with LSP data injected
.\archpass2.ps1 -Preset unreal -Jobs 8
```

Steps 1–3 are the existing pipeline unchanged. Step 4 is new and requires Serena with a fully indexed clangd. Step 5 is enhanced to consume `.serena_context.txt` files but works without them (graceful fallback).

---

## 8. Outstanding Issues

| Issue | Status | Impact | Notes |
|-------|--------|--------|-------|
| Serena `CommentedMap` config bug | Unresolved | Low | Workaround: pass `--project` via CLI instead of config file |
| Serena Windows clangd platform-ID bug (#250) | Fixed upstream (#253) | None | Bypassed by installing clangd via VS2022 |
| clangd background indexing RAM usage | Mitigated | Medium | Using `-j=4` and `--pch-storage=disk`; overnight run pending |
| `serena_extract.ps1` not yet tested end-to-end | Pending | Medium | Depends on successful clangd indexing |
| `archpass2_worker.ps1` Serena context injection | Not yet implemented | Low | Small code change to load `.serena_context.txt` and add to payload |
| Rate limits during Serena extraction | Expected | Medium | Multi-turn sonnet calls for ~800+ files will hit Pro limits; use dual-account rotation |

---

## 9. Key Lessons Learned

1. **UE 5.7.3 file layout changed:** `GitDependencies.exe` moved to `Engine\Binaries\DotNET\GitDependencies\win-x64\` (platform-specific subfolders for self-contained .NET).

2. **Engine-only GenerateClangDatabase:** No `-project` or `-game` flags. Use `UnrealEditor Win64 Development` as positional target arguments.

3. **clangd + UE scale:** 43K translation units is at the extreme edge of what clangd handles. Background indexing without throttling will OOM a 32 GB system. `-j=4` with `--pch-storage=disk` is the practical configuration.

4. **Serena's sweet spot:** Codebases up to ~5K–10K files where full background indexing is quick. For UE-scale codebases, the text-mined `archxref.ps1` provides adequate cross-reference data, and Serena's value is primarily for targeted subsystem deep-dives.

5. **Python 3.14 is risky:** Pre-release Python breaks third-party libraries in subtle ways. Always pin to 3.12 for production tooling via `uvx --python 3.12`.

6. **`claude mcp add` flag parsing:** The `--` separator doesn't reliably prevent Claude Code from parsing flags meant for the subprocess. Use `claude mcp add-json` with escaped JSON for complex MCP registrations.

7. **Setup.bat prerequisites:** On systems with VS2022 + C++ workload already installed, the prerequisites are redundant. Skip directly to `GitDependencies.exe` if `Setup.bat` hangs.
