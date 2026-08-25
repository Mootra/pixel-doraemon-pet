param(
    [switch]$Restart
)

$ErrorActionPreference = "Stop"

function Get-CodexHome {
    if (-not [string]::IsNullOrWhiteSpace($env:CODEX_HOME)) {
        return $env:CODEX_HOME
    }
    return (Join-Path $env:USERPROFILE ".codex")
}

function Get-ActivePluginRoot {
    $currentRoot = Split-Path -Parent $PSScriptRoot
    if (Test-Path -LiteralPath (Join-Path $currentRoot "hooks\pet-event.ps1")) {
        return $currentRoot
    }

    $cacheRoot = Join-Path (Get-CodexHome) "plugins\cache"
    if (Test-Path -LiteralPath $cacheRoot) {
        $candidate = Get-ChildItem -LiteralPath $cacheRoot -Directory |
            ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -Directory -ErrorAction SilentlyContinue } |
            Where-Object { $_.Name -eq "pixel-doraemon-companion" } |
            ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -Directory -ErrorAction SilentlyContinue } |
            Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName "hooks\pet-event.ps1") } |
            Sort-Object LastWriteTimeUtc -Descending |
            Select-Object -First 1
        if ($null -ne $candidate) { return $candidate.FullName }
    }

    return $currentRoot
}

$pluginRoot = Get-ActivePluginRoot
$dataRoot = Join-Path $pluginRoot ".data"
$pidPath = Join-Path $dataRoot "overlay.pid"

function Get-RunningCompanionOverlays {
    try {
        return @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
            $_.ProcessId -ne $PID -and
            $_.CommandLine -match ' -File ".*companion-overlay\.ps1"' -and
            $_.CommandLine -like '*pixel-doraemon-companion*'
        })
    } catch {
        return @()
    }
}

$runningOverlays = @(Get-RunningCompanionOverlays)
if ($Restart) {
    foreach ($overlay in $runningOverlays) {
        Stop-Process -Id $overlay.ProcessId -Force -ErrorAction SilentlyContinue
    }
    if ($runningOverlays.Count -gt 0) { Start-Sleep -Milliseconds 250 }
    Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
} elseif ($runningOverlays.Count -gt 0) {
    return
}

$env:PLUGIN_ROOT = $pluginRoot
$env:PLUGIN_DATA = $dataRoot
& (Join-Path $pluginRoot "hooks\pet-event.ps1") -Manual
