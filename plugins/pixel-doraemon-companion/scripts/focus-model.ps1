function Get-NextFocusCounters {
    param(
        [bool]$IsActive,
        [int]$ElapsedSeconds,
        [int]$CurrentSessionSeconds,
        [int]$FocusRoundElapsedSeconds,
        [int]$PomodoroSeconds
    )

    if (-not $IsActive) {
        return [pscustomobject]@{
            currentSessionSeconds = 0
            focusRoundElapsedSeconds = 0
            completedRounds = 0
        }
    }

    $safeElapsedSeconds = [Math]::Max(0, $ElapsedSeconds)
    $safePomodoroSeconds = [Math]::Max(1, $PomodoroSeconds)
    $nextSessionSeconds = [Math]::Max(0, $CurrentSessionSeconds) + $safeElapsedSeconds
    $nextRoundSeconds = [Math]::Max(0, $FocusRoundElapsedSeconds) + $safeElapsedSeconds
    $completedRounds = [int][Math]::Floor($nextRoundSeconds / $safePomodoroSeconds)

    [pscustomobject]@{
        currentSessionSeconds = $nextSessionSeconds
        focusRoundElapsedSeconds = $nextRoundSeconds % $safePomodoroSeconds
        completedRounds = $completedRounds
    }
}

function Format-FocusRoundLabel {
    param(
        [string]$Prefix,
        [int]$Round,
        [string]$Suffix
    )

    return "{0} {1} {2}" -f $Prefix, $Round, $Suffix
}
