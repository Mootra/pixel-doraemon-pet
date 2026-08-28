$ErrorActionPreference = "Stop"
$pluginRoot = Split-Path -Parent $PSScriptRoot
$config = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $pluginRoot "config\default-config.json") | ConvertFrom-Json
$overlay = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $pluginRoot "scripts\companion-overlay.ps1")

if (-not [bool]$config.focus.enabled) { throw "Focus tracking must be enabled by default." }
if ([int]$config.focus.idleThresholdSeconds -lt 15) { throw "Focus idle threshold is implausibly low." }
if ([int]$config.focus.pomodoroMinutes -ne 30) { throw "Expected a 30-minute default focus round." }
if ([int]$config.usage.displayDurationMs -ne 12000 -or [int]$config.usage.bubblePageDurationMs -ne 4000) {
    throw "Expected a 12-second bubble visit split into 4-second pages."
}
if ([int]$config.progress.celebrationDurationMs -ne 8000) { throw "Expected an 8-second celebration bubble." }
if ([int]$config.progress.maximumHistory -lt 10) { throw "Progress history must retain a useful number of events." }
if (@($config.progress.focusMilestones).Count -lt 1 -or @($config.progress.keyboardMilestones).Count -lt 1) {
    throw "Focus and keyboard milestones must both be configured."
}
foreach ($marker in @("GetActivityIdleMilliseconds", "StartInputCounter", "MouseHookCallback", "ConsumeKeyboardPresses", "Update-FocusTracking", "Update-BubblePageRotation", "Show-FocusDashboard", "focusIdleThresholdSeconds", "focus-state.json", "progress-state.json", "Initialize-ProgressState", "Check-ProgressMilestones", "Add-ProgressEvent", "totalKeyboardPresses", "totalFocusSeconds")) {
    if ($overlay -notmatch [regex]::Escape($marker)) { throw "Focus tracker marker is missing: $marker" }
}
if ($overlay -match [regex]::Escape('ConsumeKeyboardPresses($targetProcessName)')) {
    throw "Keyboard presses must be consumed globally, not only for focus targets."
}
if ($overlay -notmatch [regex]::Escape("private static long keyboardPresses;")) {
    throw "A global keyboard counter is required."
}
if ($overlay -notmatch [regex]::Escape('"keyboard-repeat"') -or $overlay -notmatch [regex]::Escape('$threshold -eq 10000')) {
    throw "Keyboard celebrations must repeat at every 10,000 presses."
}
if ($overlay -match [regex]::Escape("GetLastInputInfo") -or $overlay -match [regex]::Escape("GetForegroundProcessName")) {
    throw "Focus activation must use explicit keyboard and mouse-click events, not generic input or foreground state."
}

"PASS activity timer, durable growth milestones, all-app keyboard count privacy boundary, carousel, and 90-second click-or-key safeguards"
