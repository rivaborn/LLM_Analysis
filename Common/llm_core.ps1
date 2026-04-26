# ============================================================
# llm_core.ps1 -- Environment infrastructure (lean, Claude-CLI variant)
#
# Location: LLM_Analysis/Common/llm_core.ps1
# Loaded transitively via llm_common.ps1.
#
# This toolkit drives the Claude CLI directly from each worker
# script (`& claude -p --model ...`), so this module deliberately
# does NOT include the Ollama-specific helpers that exist in the
# sister LocalLLM_Analysis toolkit (Invoke-LocalLLM, Get-LLMModel,
# Get-LLMEndpoint). Worker scripts keep their own Claude invocation
# logic.
#
# Provided functions:
#   Test-CancelKey   - Poll for Ctrl+Q (quiet exit)
#   Read-EnvFile     - Parse .env key=value files
#   Cfg              - Config key lookup with default
# ============================================================

function Test-CancelKey {
    try {
        if ([Console]::IsInputRedirected) { return }
    } catch {
        return
    }
    while ([Console]::KeyAvailable) {
        $k = [Console]::ReadKey($true)
        if ($k.Key -eq [ConsoleKey]::Q -and
            ($k.Modifiers -band [ConsoleModifiers]::Control)) {
            Write-Host ''
            Write-Host '[Ctrl+Q] User cancelled. Exiting cleanly...' -ForegroundColor Yellow
            exit 130
        }
    }
}

function Read-EnvFile($path) {
    $vars = @{}
    if (Test-Path $path) {
        Get-Content $path | ForEach-Object {
            $line = $_.Trim()
            if ($line -match '^#' -or $line -eq '') { return }
            if ($line -match '^([^=]+)=(.*)$') {
                $key = $Matches[1].Trim()
                $val = $Matches[2].Trim().Trim('"').Trim("'")
                $val = $val -replace [regex]::Escape('$HOME'), $env:USERPROFILE
                $val = $val -replace '^~', $env:USERPROFILE
                $vars[$key] = $val
            }
        }
    }
    return $vars
}

function Cfg($key, $default = '') {
    if ($script:cfg -and $script:cfg.ContainsKey($key) -and $script:cfg[$key] -ne '') { return $script:cfg[$key] }
    return $default
}
