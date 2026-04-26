# Status Line Investigation & Fix (2026-03-27)

## Problem
Status line only showed: `Opus 4.6 (1M context) | ctx: -- of 1000k`
Expected: cost, rate limit (5h session), and rate limit (7d week) fields as well.
Restarting PowerShell and Claude did not help - appeared stuck on "first version" of script.

## Environment
- Three Claude config directories:
  - `$env:USERPROFILE\.claude`
  - `$env:USERPROFILE\.clauderivalon`
  - `$env:USERPROFILE\.claudefksogbetun` (active session, via `CLAUDE_CONFIG_DIR`)
- All three had identical `settings.json` pointing to their own `statusline-command.sh`
- No `settings.local.json` or project-level settings overriding the status line

## Settings Configuration (all three dirs)
```json
{
  "statusLine": {
    "type": "command",
    "command": "sh /c/Users/folar/.claude<suffix>/statusline-command.sh"
  }
}
```

## Root Cause
The statusline script used `in` as an awk variable name:
```bash
cost=$(awk -v in="$in_tok" -v out="$out_tok" ...
```

`in` is a **reserved keyword in gawk** (the awk implementation on Windows/MSYS2). This produced:
```
awk: fatal: cannot use gawk builtin 'in' as variable name
```

This error went to **stderr**. Claude Code interprets stderr output from the statusline command as a failure and **silently falls back to its built-in default status line**, which only shows model name and context window - exactly matching the symptom.

## Why It Looked "Stuck on the First Version"
The script was always the latest version. But every version had the same awk bug, so every version produced stderr output, so Claude Code always fell back to the same default display. It appeared as if the old script was cached, but in reality the new script was running and failing silently.

## Fix
Renamed awk variable `in` to `intok` and `out` to `outtok` in all three scripts:

```bash
# Before (broken)
cost=$(awk -v in="$in_tok" -v out="$out_tok" -v cw="$cache_write" -v cr="$cache_read" \
  -v ip="$in_p" -v op="$out_p" -v cwp="$cw_p" -v crp="$cr_p" \
  'BEGIN { printf "%.4f", in*ip + out*op + cw*cwp + cr*crp }')

# After (fixed)
cost=$(awk -v intok="$in_tok" -v outtok="$out_tok" -v cw="$cache_write" -v cr="$cache_read" \
  -v ip="$in_p" -v op="$out_p" -v cwp="$cw_p" -v crp="$cr_p" \
  'BEGIN { printf "%.4f", intok*ip + outtok*op + cw*cwp + cr*crp }')
```

Files fixed:
- `C:\Users\folar\.claude\statusline-command.sh`
- `C:\Users\folar\.clauderivalon\statusline-command.sh`
- `C:\Users\folar\.claudefksogbetun\statusline-command.sh`

## Verification
```bash
# Test with sample JSON - no stderr, correct output:
echo '{"model":{"display_name":"Opus 4.6 (1M context)","id":"claude-opus-4-6"},...}' \
  | sh /c/Users/folar/.claudefksogbetun/statusline-command.sh
# Output: Opus 4.6 (1M context) | cost: $0.9195 | ctx: -- of 1000k | 5h: 12% | 7d: 3%
```

## Second Issue — Project-level override (2026-03-27)

After fixing the awk bug, the status line still showed only defaults (`Opus 4.6 (1M context) | ctx: -- of 1000k`).

### Root Cause
A **project-level** `.claude/settings.json` in the repo root had its own `statusLine` config pointing to a minimal script at `.claude/statusline-command.sh`. This script only output model name + context window (no cost or rate limits). Project-level settings override user-level settings, so the full script in `~/.claudefksogbetun/statusline-command.sh` was never executed.

### Fix
- Copied the full statusline script (with cost, 5h, 7d fields) into `.claude/statusline-command.sh`
- Changed the command in `.claude/settings.json` from `bash` to `sh` for consistency with user-level config

### Lesson
When the statusline shows defaults or a stripped-down version, check for **project-level overrides** in `.claude/settings.json` (repo root), not just the user-level config dir.

## Third Issue — Script timeout from subprocess spawning (2026-03-27)

After fixing both the awk bug and the project-level override, the status line appeared briefly then disappeared entirely (no status line at all).

### Root Cause
The script spawned ~10 separate `echo "$input" | jq` pipelines to extract each field. On Windows/MSYS2, each subprocess spawn is expensive. Claude Code has a timeout for statusline commands — if the script doesn't return in time, the status line is suppressed entirely (not even the default is shown).

### Fix
Rewrote the script to use a **single `jq` call** with `@sh` formatting to extract all fields at once via `eval`:
```bash
# Before: ~10 separate jq processes
model=$(echo "$input" | jq -r '.model.display_name // "Unknown"')
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
# ... 8 more jq calls

# After: 1 jq process
eval $(echo "$input" | jq -r '
  @sh "model=\(.model.display_name // "Unknown")",
  @sh "used=\(.context_window.used_percentage // "")",
  ...
')
```

Updated all 4 script locations:
- `.claude/statusline-command.sh` (project-level)
- `~/.claude/statusline-command.sh`
- `~/.clauderivalon/statusline-command.sh`
- `~/.claudefksogbetun/statusline-command.sh`

### Lesson
On Windows/MSYS2, minimize subprocess spawns in statusline scripts. Each pipe + process creation adds significant latency. Consolidate multiple `jq` calls into one using `@sh` output for shell variable assignment.

## Fourth Issue — Shell script files not executed reliably (2026-03-27)

Even the pure single-process jq script file (78ms, no stderr) still disappeared. A minimal inline test (`jq -r '.model.display_name'`) worked immediately, proving the statusLine mechanism itself was fine.

### Root Cause
On Windows/MSYS2, invoking `sh /path/to/script.sh` adds shell startup overhead that pushes execution past Claude Code's debounce/cancellation window. The `sh` process must start, parse the script, then launch `jq` — even with a single-command script, this adds ~150ms+ on Windows.

Inline commands skip the shell script overhead entirely — Claude Code runs `jq` directly.

### Fix
Moved the entire jq filter **inline** into `.claude/settings.json`, eliminating the script file:

```json
{
  "statusLine": {
    "type": "command",
    "command": "jq -r '(.model.display_name // \"Unknown\") as $model | ... | \"\\($model) | cost: $\\($cost) | ctx: \\($ctx) | 5h: \\($rl5h) | 7d: \\($rl7d)\"'"
  }
}
```

Key details:
- Cost formatting uses `* 10000 | round / 10000` instead of regex (`test("\\.")`) to avoid JSON/shell/jq triple-escaping issues
- Uses Claude Code's pre-computed `cost.total_cost_usd` instead of manual token calculation
- All jq string interpolations (`\(...)`) must be escaped as `\\(...)` inside JSON

### Lesson
On Windows, **inline commands beat script files** for statusline. The shell startup overhead for `sh script.sh` is significant enough to cause reliability issues. If the jq filter fits in a single line, put it directly in `settings.json`.

## Current Configuration (v5 — working)

Location: `.claude/settings.json` (project-level), inline jq command (no script file)

Output format:
```
Opus 4.6 (1M context) | cost: $0.6665 | ctx: 5% of 1000k | 5h: 1% | 7d: 21%
```

Claude Code JSON fields used:
- `model.display_name` — model name
- `context_window.context_window_size` — total context in tokens
- `context_window.used_percentage` — context usage percentage
- `cost.total_cost_usd` — pre-computed session cost
- `rate_limits.five_hour.used_percentage` — 5-hour rate limit usage
- `rate_limits.seven_day.used_percentage` — 7-day rate limit usage

## Debugging Tips
1. Always test statusline scripts manually and check stderr:
   ```bash
   echo '<json>' | sh /path/to/statusline-command.sh 2>&1
   ```
   If stderr has any output, Claude Code will likely ignore stdout and fall back to defaults.

2. If the status line disappears entirely (not even defaults), the script is likely **timing out** or being cancelled. Profile with:
   ```bash
   time echo '<json>' | sh /path/to/statusline-command.sh
   ```

3. Claude Code debounces at 300ms and **cancels in-flight executions** — a slow script may work in manual testing but fail in practice due to rapid update triggers.

4. On Windows, try an **inline command first** (`jq -r '...'` directly in settings.json) before using a script file. If inline works but the script doesn't, the issue is shell startup overhead.
