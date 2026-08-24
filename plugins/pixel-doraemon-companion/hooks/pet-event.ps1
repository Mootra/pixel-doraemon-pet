param(
    [switch]$NoLaunch,
    [switch]$Manual
)

$ErrorActionPreference = "Stop"

function Get-PluginPath {
    if ($env:PLUGIN_ROOT) { return $env:PLUGIN_ROOT }
    if ($env:CLAUDE_PLUGIN_ROOT) { return $env:CLAUDE_PLUGIN_ROOT }
    return (Split-Path -Parent $PSScriptRoot)
}

function Get-DataPath([string]$PluginRoot) {
    if ($env:PLUGIN_DATA) { return $env:PLUGIN_DATA }
    if ($env:CLAUDE_PLUGIN_DATA) { return $env:CLAUDE_PLUGIN_DATA }
    return (Join-Path $PluginRoot ".data")
}

function Get-WeightedAction($Rules) {
    if (-not $Rules -or $Rules.Count -eq 0) { return "idle" }
    $total = 0.0
    foreach ($rule in $Rules) { $total += [double]$rule.weight }
    if ($total -le 0) { return [string]$Rules[0].action }

    $needle = (Get-Random -Minimum 0.0 -Maximum $total)
    $cursor = 0.0
    foreach ($rule in $Rules) {
        $cursor += [double]$rule.weight
        if ($needle -le $cursor) { return [string]$rule.action }
    }
    return [string]$Rules[-1].action
}

function Test-ToolFailure($Payload) {
    if ($null -ne $Payload.tool_response) {
        if ($Payload.tool_response.PSObject.Properties.Name -contains "success") {
            return -not [bool]$Payload.tool_response.success
        }
        if ($Payload.tool_response.PSObject.Properties.Name -contains "is_error") {
            return [bool]$Payload.tool_response.is_error
        }
    }
    $serialized = $Payload | ConvertTo-Json -Depth 20 -Compress
    return $serialized -match '"(success|ok)":false|"is_error":true|"exit_code":[1-9][0-9]*'
}

function Start-Companion([string]$PluginRoot, [string]$DataRoot) {
    $pidPath = Join-Path $DataRoot "overlay.pid"
    if (Test-Path $pidPath) {
        $existingPid = Get-Content -LiteralPath $pidPath -Encoding ASCII -ErrorAction SilentlyContinue
        if ($existingPid -and (Get-Process -Id $existingPid -ErrorAction SilentlyContinue)) { return }
    }

    $overlayPath = Join-Path $PluginRoot "scripts\companion-overlay.ps1"
    $arguments = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-STA",
        "-File", ('"{0}"' -f $overlayPath),
        "-PluginRoot", ('"{0}"' -f $PluginRoot),
        "-DataRoot", ('"{0}"' -f $DataRoot)
    )
    Start-Process -FilePath "powershell.exe" -ArgumentList $arguments -WindowStyle Hidden | Out-Null
}

$pluginRoot = Get-PluginPath
$dataRoot = Get-DataPath $pluginRoot
New-Item -ItemType Directory -Force -Path $dataRoot | Out-Null

$defaultConfigPath = Join-Path $pluginRoot "config\default-config.json"
$userConfigPath = Join-Path $dataRoot "config.json"
if (-not (Test-Path $userConfigPath)) {
    Copy-Item -LiteralPath $defaultConfigPath -Destination $userConfigPath
}
$config = Get-Content -Raw -Encoding UTF8 -LiteralPath $userConfigPath | ConvertFrom-Json

$stdin = if ($Manual) { "" } else { [Console]::In.ReadToEnd() }
if ($Manual -or [string]::IsNullOrWhiteSpace($stdin)) {
    $payload = [pscustomobject]@{ hook_event_name = "SessionStart"; session_id = "manual" }
} else {
    $payload = $stdin | ConvertFrom-Json
}

$eventName = [string]$payload.hook_event_name
$ruleName = $eventName
if ($eventName -eq "PostToolUse") {
    $ruleName = if (Test-ToolFailure $payload) { "PostToolUseFailure" } else { "PostToolUseSuccess" }
}

$rules = $config.eventRules.$ruleName
$action = Get-WeightedAction $rules
$hold = if ($null -ne $config.holdMs.$ruleName) { [int]$config.holdMs.$ruleName } else { 1800 }
$toolName = if ($null -ne $payload.tool_name) { [string]$payload.tool_name } else { $null }

$state = [ordered]@{
    sequence = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    timestampUtc = [DateTime]::UtcNow.ToString("o")
    action = $action
    event = $ruleName
    holdMs = $hold
    sessionId = [string]$payload.session_id
    toolName = $toolName
}

$statePath = Join-Path $dataRoot "pet-state.json"
$tempPath = Join-Path $dataRoot ("pet-state-{0}.tmp" -f $PID)
$state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $tempPath -Encoding UTF8
Move-Item -Force -LiteralPath $tempPath -Destination $statePath

if (-not $NoLaunch) {
    Start-Companion $pluginRoot $dataRoot
}
