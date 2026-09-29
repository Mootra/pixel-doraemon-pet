$ErrorActionPreference = "Stop"
$pluginRoot = Split-Path -Parent $PSScriptRoot
$config = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $pluginRoot "config\default-config.json") | ConvertFrom-Json
$overlay = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $pluginRoot "scripts\companion-overlay.ps1")
. (Join-Path $pluginRoot "scripts\focus-model.ps1")

if (-not [bool]$config.focus.enabled) { throw "Focus tracking must be enabled by default." }
if ([int]$config.focus.idleThresholdSeconds -ne 60) { throw "Expected a 60-second current-session timeout." }
if ([int]$config.focus.pomodoroMinutes -ne 30) { throw "Expected a 30-minute default focus round." }
if (-not [bool]$config.bubble.enabled) { throw "The companion bubble must be enabled independently by default." }
if ([int]$config.bubble.displayDurationMs -ne 12000 -or [int]$config.bubble.bubblePageDurationMs -ne 4000) {
    throw "Expected a 12-second bubble visit split into 4-second pages."
}
if (-not [bool]$config.celebrations.enabled -or [int]$config.celebrations.durationMs -ne 8000) { throw "Expected an independent 8-second celebration bubble." }
if ([int]$config.progress.maximumHistory -lt 10) { throw "Progress history must retain a useful number of events." }
if (@($config.progress.focusMilestones).Count -lt 1 -or @($config.progress.keyboardMilestones).Count -lt 1) {
    throw "Focus and keyboard milestones must both be configured."
}
foreach ($marker in @("GetActivityIdleMilliseconds", "StartInputCounter", "MouseHookCallback", "ConsumeKeyboardPresses", "Update-FocusTracking", "Update-BubblePageRotation", "Show-FocusDashboard", "focusIdleThresholdSeconds", "currentFocusSessionSeconds", "focusRoundElapsedSeconds", "legacyFocusStatePath", "Get-LegacyFocusStatePath", "focus-state.json", "progress-state.json", "Initialize-ProgressState", "Check-ProgressMilestones", "Add-ProgressEvent", "totalKeyboardPresses", "totalFocusSeconds", "Format-FocusDuration", "{0}:{1:00}:{2:00}", "usagePrimaryRemaining")) {
    if ($overlay -notmatch [regex]::Escape($marker)) { throw "Focus tracker marker is missing: $marker" }
}
if ($overlay -notmatch '(?m)^\s*\$usageDetailText\.Text = .*\$script:focusActiveSeconds.*\$script:totalFocusSeconds.*$') {
    throw "The focus bubble detail must show today's focus and lifetime focus totals."
}
if ($overlay -match '\$stateLabel\s*=') {
    throw "The focus bubble detail must not include a running or paused status label."
}

$inactive = Get-NextFocusCounters $false 1 120 120 1800
if ($inactive.currentSessionSeconds -ne 0 -or $inactive.focusRoundElapsedSeconds -ne 0) {
    throw "An idle timeout must reset both the continuous session and current round."
}
$completed = Get-NextFocusCounters $true 2 1799 1799 1800
if ($completed.currentSessionSeconds -ne 1801 -or $completed.focusRoundElapsedSeconds -ne 1 -or $completed.completedRounds -ne 1) {
    throw "Completing a round must preserve the continuous session and wrap only round progress."
}
$roundPrefix = [string][char]0x7B2C
$roundSuffix = [string][char]0x8F6E
$roundLabel = Format-FocusRoundLabel $roundPrefix 3 $roundSuffix
if ($roundLabel -ne ("{0} 3 {1}" -f $roundPrefix, $roundSuffix) -or $roundLabel -like "*{0}*") {
    throw "Focus round labels must interpolate the round number."
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

"PASS activity timer, durable growth milestones, all-app keyboard count privacy boundary, carousel, and 60-second click-or-key safeguards"
