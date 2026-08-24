$ErrorActionPreference = "Stop"
. (Join-Path (Split-Path -Parent $PSScriptRoot) "scripts\look-direction.ps1")

function Assert-Equal($Actual, $Expected, [string]$Message) {
    if ($Actual -ne $Expected) {
        throw "$Message (expected=$Expected actual=$Actual)"
    }
}

Assert-Equal (Get-LookFrameForAngle -Degrees (Get-LookAngleDegrees -Dx 0 -Dy -100)) 0 "up should map to frame 0"
Assert-Equal (Get-LookFrameForAngle -Degrees (Get-LookAngleDegrees -Dx 100 -Dy 0)) 4 "right should map to frame 4"
Assert-Equal (Get-LookFrameForAngle -Degrees (Get-LookAngleDegrees -Dx 0 -Dy 100)) 8 "down should map to frame 8"
Assert-Equal (Get-LookFrameForAngle -Degrees (Get-LookAngleDegrees -Dx -100 -Dy 0)) 12 "left should map to frame 12"
Assert-Equal (Get-LookFrameForAngle -Degrees 359.0) 0 "wraparound should stay near up"

Assert-Equal (Get-LookFrameForAngle -Degrees 13.0 -CurrentFrame 0 -HysteresisDegrees 3.5) 0 "hysteresis should hold near a sector edge"
Assert-Equal (Get-LookFrameForAngle -Degrees 16.0 -CurrentFrame 0 -HysteresisDegrees 3.5) 1 "hysteresis should release after the extended edge"

Assert-Equal (Get-NextLookFrame -CurrentFrame 0 -TargetFrame 15) 15 "shortest path should cross the wrap counter-clockwise"
Assert-Equal (Get-NextLookFrame -CurrentFrame 15 -TargetFrame 0) 0 "shortest path should cross the wrap clockwise"
Assert-Equal (Get-NextLookFrame -CurrentFrame 0 -TargetFrame 8) 1 "opposite tie should advance clockwise deterministically"

"PASS look direction mapping, hysteresis, wraparound, and shortest-path stepping"
