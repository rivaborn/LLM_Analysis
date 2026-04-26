# CLAUDE.md — Project Context for Claude Code

## Project Overview

Architecture documentation toolkit for Unreal Engine 5.7.3 source code. Generates per-file and subsystem-level architecture docs using Claude CLI, with LSP-powered semantic analysis via clangd.

**Repository:** `C:\Coding\Epic_Games\UnrealEngine` (fork of EpicGames/UnrealEngine, branch `release`)
**UE Version:** 5.7.3
**System:** Windows 11, 32 GB RAM

## Pipeline Order

```
0.  serena_extract.ps1       Free (direct clangd, no Claude)
0b. archgen_dirs.ps1         Few Claude calls (sonnet, per-directory)
1.  archgen.ps1              Per-file docs (haiku, sonnet for complex files)
2.  archxref.ps1             Free (text processing)
3.  archgraph.ps1            Free (text processing)
4.  arch_overview.ps1        Subsystem synthesis (sonnet, incremental)
4b. archpass2_context.ps1    Free (text processing)
5.  archpass2.ps1            Selective re-analysis (haiku, sonnet for complex)
```

## Key Configuration

- `.env` has `CLAUDE_MODEL=haiku` with `TIERED_MODEL=1` (auto-upgrades complex files to sonnet)
- `CLAUDE1_CONFIG_DIR` and `CLAUDE2_CONFIG_DIR` for dual-account rate-limit rotation
- `-Clean` on archgen.ps1 preserves `.serena_context/`, `.dir_context/`, `.dir_headers/`

## Known Issues and Bugs

### archgen_worker.ps1 — Files not written to disk (FIXED)
Root cause: PowerShell 5.1 `if/else` expression unwraps single-element arrays to scalars. The line `$relList = if ($isBatch) { $rel -split '\|' } else { @($rel) }` returned a string instead of an array for individual (non-batch) files. Then `$relList[0]` indexed the first character of the string (e.g., `"E"` from `"Engine/..."`) instead of returning the whole path. Fix: wrap the entire `if/else` in `@()` — `$relList = @(if ($isBatch) { ... } else { ... })`. Batch files worked because `$rel -split '\|'` returns a multi-element array that survives unwrapping.

### PowerShell em dash encoding
Em dashes (`—`) in PowerShell scripts get mojibaked to `â€"` on some systems. Replace with regular dashes (`-`) in all `.ps1` files.

### PowerShell strict mode and .Count
Under `Set-StrictMode -Version Latest`, calling `.Count` on a non-array fails. Always wrap `Get-PerFileDocs` and similar calls in `@()` to ensure array return.

### archpass2_context.ps1 — regex in double-quoted strings
PowerShell 5.1 chokes on `$([regex]::Escape($key))` inside double-quoted strings in certain contexts. Use a separate variable instead: `$escaped = [regex]::Escape($key)`.

### serena_extract.py — scale-up worker missing compress arg
Fixed: the scale-up worker creation (line ~1020) was missing `compress=args.compress`. Both initial and scale-up worker creation must pass all arguments.

### -Clean deletes .serena_context/
Fixed: `-Clean` now preserves `.serena_context/`, `.dir_context/`, and `.dir_headers/`. These are expensive to regenerate (hours of clangd extraction).

### serena_extract.py -- PCH disk bloat (preamble-*.pch)
Fixed: clangd `--pch-storage=disk` wrote orphaned `preamble-*.pch` files to temp, accumulating 50+ GB. The script now snapshots existing PCH at startup and cleans up session files on shutdown + `atexit`. Cleanup only runs at exit (not mid-run) to avoid degrading throughput -- active clangd instances reuse PCH files across parses.

### serena_extract.py -- I/O contention with many workers
Auto-scaler can spawn too many workers (observed: 7 workers at `-Jobs 3` = 21 threads). Disk I/O contention drops throughput from 0.6/s to 0.4/s. Cap workers explicitly: `-Workers 2 -Jobs 2` for 32 GB systems.

### archgen.ps1 switch parameters
Changed from `[switch]` to `[string]` for the v2/v3 opt-in flags (`$ElideSource`, `$NoBatch`, `$NoPreamble`, `$MaxTokens`, `$JsonOutput`, `$Classify`) due to a PowerShell binding error. Check with `-ne ''` instead of boolean test.

### archgen.ps1 -- progress display not updating (FIXED)
Reading `counter.json` (written by workers via mutex + `Set-Content`) from the parent process was unreliable -- file contention caused silent read failures inside `catch {}`. Fixed: progress now counts lines in `hashes.tsv` (append-only, read with `StreamReader`) and reads `counter.json` only for fail/retries (best-effort). Display uses `[Console]::Write()` with `\r` for single-line in-place updates. ETA shown in `0h54m33s` format. The `[math]::Floor()` results must be cast to `[int]` for PowerShell's `:D2` format specifier.

### arch_overview.ps1 -- chunking fails on deep single-child paths (FIXED)
When `Get-Subsystems` encountered a directory with only 1 child (e.g., `Engine` -> `Source` -> `Runtime` -> `Engine` -> `Private`), it stopped splitting and treated the entire oversized subtree as one chunk. Fix: single-child directories are now descended through without incrementing depth, so the recursion reaches the actual multi-child directory (e.g., `Private` with Animation, Audio, PhysicsEngine, etc.).

## Workers vs Jobs (serena_extract)

- **Workers** = number of clangd processes
- **Jobs** = `-j` threads per clangd process
- 3 workers x 4 jobs = 12 threads, too much for 32 GB
- Sweet spot for 32 GB: `-Workers 2 -Jobs 2`

## clangd Index

- Built once, cached at `.cache/clangd/index/` (1.5 GB, 112K idx files)
- Takes ~8.5 hours to build from scratch with `-j=4`
- Post-indexing steady state: ~4 GB RAM per clangd instance
- Parse time per UE file: 3-8 seconds (bottleneck is include chain resolution, not file size)

## Token Optimizations

28 optimizations documented across 4 files:
- `Optimization.md` — v1: 8 implemented (skip trivial, shared headers, LSP trimming, targeted P2 context, tiered model, batch templates, compressed prompt, adaptive budget)
- `Optimizations v2.md` — v2: 6 implemented (batch small files, preamble, schema pruning, delta P2, source elision, pattern cache)
- `Optimizations v3.md` — v3: 7 implemented (max-tokens, dir-first analysis, LSP compression, JSON output, shared dir headers, incremental overview, classification)
- `Optimizations v4.md` — v4: 1 implemented (prompt caching), 5 documented (diff-based, on-demand, cluster, sampling, templates)

Baseline ~250M tokens -> after v1-v3: ~12M tokens (95% reduction)

## Documentation Files

- `SETUP.md` — Full setup guide (20 sections)
- `Instructions.md` — CLI reference for every script (14 sections)
- `Quickstart.md` — Condensed reference
- `SerenaFinal.md` — Complete technical reference (16 sections, 30 lessons learned)
- `FileReference.md` — Index of all files
- `Optimization.md`, `Optimizations v2.md`, `Optimizations v3.md`, `Optimizations v4.md` — Token optimization strategies

## File Naming Convention

Scripts use PowerShell (`.ps1`) with bash equivalents (`.sh`). All scripts read `.env` for configuration. Worker scripts (`*_worker.ps1`) are dispatched via `Start-Job` and should never be run directly.

## Subsystem Analysis Workflow

The user analyzes one subsystem at a time, then renames the `architecture/` folder (e.g., `architecture_CoreUObject/`). The `.serena_context/` directory should be preserved across subsystem analyses since it covers the entire codebase.
