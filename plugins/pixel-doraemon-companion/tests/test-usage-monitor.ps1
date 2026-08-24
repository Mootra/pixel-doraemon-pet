$ErrorActionPreference = "Stop"
$pluginRoot = Split-Path -Parent $PSScriptRoot
$monitorPath = Join-Path $pluginRoot "scripts\usage-monitor.ps1"
$fixturePath = Join-Path $PSScriptRoot "fixtures\rate-limits-two-windows.json"
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$testRoot = Join-Path $tempRoot ("pixel-doraemon-usage-test-{0}" -f [Guid]::NewGuid().ToString("N"))

try {
    New-Item -ItemType Directory -Force -Path $testRoot | Out-Null
    & $monitorPath -DataRoot $testRoot -FixturePath $fixturePath -Once | Out-Null
    $state = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $testRoot "usage-state.json") | ConvertFrom-Json

    if (-not [bool]$state.available) { throw "Expected usage state to be available." }
    if ($state.windows.Count -ne 2) { throw "Expected two usage windows." }
    if ([int]$state.windows[0].remainingPercent -ne 75) { throw "Expected 75% remaining in the 5h window." }
    if ([int]$state.windows[1].remainingPercent -ne 40) { throw "Expected 40% remaining in the 7d window." }
    if ([string]$state.source -ne "codex-app-server") { throw "Unexpected usage source." }

    Write-Output "PASS usage monitor fixture: 5h=75%, 7d=40%"
} finally {
    $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
    if ($resolvedTestRoot.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -and
        [IO.Path]::GetFileName($resolvedTestRoot).StartsWith("pixel-doraemon-usage-test-")) {
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
