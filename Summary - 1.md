# Serena + Unreal Engine — Troubleshooting Summary

## Problem

Running Claude Code with the Serena MCP server pointed at the Unreal Engine source tree caused the machine to crash (RAM/CPU exhaustion).

## Root Cause

Serena uses **clangd** (via SolidLSP) as its C++ language server. On startup, clangd is launched with `--background-index`, which immediately queues every compilation unit in `compile_commands.json` for parallel indexing.

The UE `compile_commands.json` contains approximately **43,000+ compilation units** across a **129 GB** source tree. Clangd parallelizes indexing across all CPU cores and loads every indexed file into RAM — exhausting both on any typical machine.

## Environment

| Item | Detail |
|---|---|
| Codebase | `C:\Coding\Epic_Games\UnrealEngine` |
| Codebase size | 129 GB |
| Top-level source dirs | 9 (`Engine/Source/`: Developer, Editor, Programs, Runtime, ThirdParty, …) |
| `compile_commands.json` | ~218,000 lines / ~43,000 entries |
| Clangd version | 22.1.0 (system-installed via WinGet) |
| Serena install | `uvx --from git+https://github.com/oraios/serena serena start-mcp-server` |
| Language backend | LSP (clangd) |

## Configuration Files

### `.serena/project.yml` (pre-existing, already had good exclusions)

Key settings already in place:
- `languages: [cpp]`
- `compile_commands_dir: .`
- `ignore_all_files_in_gitignore: true`
- `ignored_paths`: ThirdParty, Intermediate, Binaries, Build, DerivedDataCache, Saved, GeneratedFiles, AutomationTool, .git

### `.clangd` (created during troubleshooting)

Located at `C:\Coding\Epic_Games\UnrealEngine\.clangd`. Clangd reads this file natively at startup.

Current state:

```yaml
Index:
  Background: Build       # Background indexing enabled, but with diagnostics suppressed
  StandardLibrary: No     # Don't index standard library headers

CompileFlags:
  Remove:
    - -W*                 # Strip warning flags (UE headers generate massive noise)
    - -fdiagnostics*      # Strip diagnostic formatting flags

Diagnostics:
  UnusedIncludes: None
  MissingIncludes: None
  ClangTidy: false
  Suppress: ["*"]         # Suppress all diagnostics — analysis only, no linting

Completion:
  AllScopes: false        # Limit completion scope to reduce memory usage
```

## What Each Setting Does

| Setting | Effect |
|---|---|
| `Index.Background: Build` | Indexes in background but with all diagnostics suppressed, reducing CPU load |
| `Index.StandardLibrary: No` | Prevents clangd from indexing UE's bundled stdlib/platform headers |
| `CompileFlags.Remove: [-W*, -fdiagnostics*]` | Strips warning/diagnostic flags from compile commands — reduces per-file work |
| `Diagnostics.Suppress: ["*"]` | No error squiggles or diagnostics computed — analysis queries only |
| `Completion.AllScopes: false` | Restricts symbol completion to local scope, lowers RAM usage |

## How Serena Launches Clangd

Serena's SolidLSP library (`clangd_language_server.py`) launches clangd as:

```
clangd --background-index [--compile-commands-dir=<path if relative dirs detected>]
```

There is no way to pass additional clangd flags through `ls_specific_settings` in `project.yml` — the `.clangd` config file is the correct mechanism for controlling clangd behavior.

## Remaining Considerations

- If crashes persist, change `Background: Build` → `Background: Skip` to disable background indexing entirely. Serena will still index files on-demand as you query them.
- For focused analysis of a specific subsystem (e.g., only the Renderer or the Physics module), consider pointing Serena at a subdirectory rather than the UE root.
- The `compile_commands.json` at the UE root is required for cross-file reference resolution. Do not delete it.
