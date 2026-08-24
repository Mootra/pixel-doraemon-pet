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
    $cacheRoot = Join-Path (Get-CodexHome) "plugins\cache\personal\pixel-doraemon-companion"
    if (Test-Path -LiteralPath $cacheRoot) {
        $candidate = Get-ChildItem -LiteralPath $cacheRoot -Directory |
            Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName "hooks\pet-event.ps1") } |
            Sort-Object LastWriteTimeUtc -Descending |
            Select-Object -First 1
        if ($null -ne $candidate) { return $candidate.FullName }
    }

    return (Split-Path -Parent $PSScriptRoot)
}

$pluginRoot = Get-ActivePluginRoot
$dataRoot = Join-Path $pluginRoot ".data"
$pidPath = Join-Path $dataRoot "overlay.pid"

if ($Restart -and (Test-Path -LiteralPath $pidPath)) {
    $overlayPid = Get-Content -LiteralPath $pidPath -Encoding ASCII -ErrorAction SilentlyContinue
    if ($overlayPid) {
        Stop-Process -Id $overlayPid -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 250
    }
    Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
}

$env:PLUGIN_ROOT = $pluginRoot
$env:PLUGIN_DATA = $dataRoot
& (Join-Path $pluginRoot "hooks\pet-event.ps1") -Manual
