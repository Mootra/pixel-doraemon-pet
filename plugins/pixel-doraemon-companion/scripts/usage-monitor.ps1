param(
    [Parameter(Mandatory = $true)][string]$DataRoot,
    [int]$PollMs = 60000,
    [int]$OwnerPid = 0,
    [switch]$Once,
    [string]$FixturePath
)

$ErrorActionPreference = "Stop"
$usageStatePath = Join-Path $DataRoot "usage-state.json"
$usagePidPath = Join-Path $DataRoot "usage-monitor.pid"
$refreshRequestPath = Join-Path $DataRoot "usage-refresh.request"

function Write-AtomicJson($Value, [string]$Path) {
    $tempPath = Join-Path (Split-Path -Parent $Path) ("{0}.{1}.tmp" -f ([IO.Path]::GetFileName($Path)), $PID)
    $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $tempPath -Encoding UTF8
    Move-Item -Force -LiteralPath $tempPath -Destination $Path
}

function Read-CodexRateLimits {
    $node = Get-Command node.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $node) { throw "Node.js is required to query Codex usage." }

    $helperPath = Join-Path $PSScriptRoot "read-codex-usage.mjs"
    if (-not (Test-Path -LiteralPath $helperPath)) { throw "Codex usage helper is missing." }

    $output = & $node.Source $helperPath 2>&1
    if ($LASTEXITCODE -ne 0) { throw ($output -join " ") }
    return (($output -join "`n") | ConvertFrom-Json)
}

function ConvertTo-UsageState($Response) {
    if ($null -eq $Response.result) { throw "The Codex usage response has no result." }

    $snapshot = $Response.result.rateLimits
    if ($null -ne $Response.result.rateLimitsByLimitId -and
        $Response.result.rateLimitsByLimitId.PSObject.Properties.Name -contains "codex") {
        $snapshot = $Response.result.rateLimitsByLimitId.codex
    }
    if ($null -eq $snapshot) { throw "The Codex usage response has no rate-limit snapshot." }

    $windows = @()
    foreach ($kind in @("primary", "secondary")) {
        $window = $snapshot.$kind
        if ($null -eq $window) { continue }
        $usedPercent = [Math]::Max(0, [Math]::Min(100, [int]$window.usedPercent))
        $windows += [pscustomobject][ordered]@{
            kind = $kind
            usedPercent = $usedPercent
            remainingPercent = 100 - $usedPercent
            windowDurationMins = if ($null -eq $window.windowDurationMins) { $null } else { [long]$window.windowDurationMins }
            resetsAt = if ($null -eq $window.resetsAt) { $null } else { [long]$window.resetsAt }
        }
    }

    $credits = $snapshot.credits
    return [ordered]@{
        available = $true
        timestampUtc = [DateTime]::UtcNow.ToString("o")
        source = "codex-app-server"
        planType = [string]$snapshot.planType
        windows = $windows
        credits = if ($null -eq $credits) {
            $null
        } else {
            [ordered]@{
                hasCredits = [bool]$credits.hasCredits
                unlimited = [bool]$credits.unlimited
                balance = [string]$credits.balance
            }
        }
        error = $null
    }
}

function Update-UsageState {
    try {
        $response = if ([string]::IsNullOrWhiteSpace($FixturePath)) {
            Read-CodexRateLimits
        } else {
            Get-Content -Raw -Encoding UTF8 -LiteralPath $FixturePath | ConvertFrom-Json
        }
        $state = ConvertTo-UsageState $response
    } catch {
        $state = [ordered]@{
            available = $false
            timestampUtc = [DateTime]::UtcNow.ToString("o")
            source = "codex-app-server"
            planType = $null
            windows = @()
            credits = $null
            error = $_.Exception.Message
        }
    }

    Write-AtomicJson $state $usageStatePath
    if ($Once) { $state | ConvertTo-Json -Depth 12 }
}

New-Item -ItemType Directory -Force -Path $DataRoot | Out-Null
$PID | Set-Content -LiteralPath $usagePidPath -Encoding ASCII

try {
    if ($Once) {
        Update-UsageState
        return
    }

    $effectivePollMs = [Math]::Max(15000, $PollMs)
    $nextPollAt = [DateTime]::MinValue
    while ($true) {
        if ($OwnerPid -gt 0 -and -not (Get-Process -Id $OwnerPid -ErrorAction SilentlyContinue)) { break }

        $now = [DateTime]::UtcNow
        $refreshRequested = Test-Path -LiteralPath $refreshRequestPath
        if ($refreshRequested) {
            Remove-Item -LiteralPath $refreshRequestPath -Force -ErrorAction SilentlyContinue
        }
        if ($refreshRequested -or $now -ge $nextPollAt) {
            Update-UsageState
            $nextPollAt = [DateTime]::UtcNow.AddMilliseconds($effectivePollMs)
        }
        Start-Sleep -Milliseconds 800
    }
} finally {
    Remove-Item -LiteralPath $usagePidPath -Force -ErrorAction SilentlyContinue
}
