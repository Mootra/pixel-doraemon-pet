function Get-LookAngleDegrees {
    param(
        [Parameter(Mandatory = $true)][double]$Dx,
        [Parameter(Mandatory = $true)][double]$Dy
    )

    $degrees = [Math]::Atan2($Dx, -$Dy) * 180.0 / [Math]::PI
    if ($degrees -lt 0) { $degrees += 360.0 }
    return $degrees
}

function Get-LookFrameForAngle {
    param(
        [Parameter(Mandatory = $true)][double]$Degrees,
        [int]$CurrentFrame = -1,
        [double]$HysteresisDegrees = 0.0
    )

    $normalized = (($Degrees % 360.0) + 360.0) % 360.0
    if ($CurrentFrame -ge 0 -and $CurrentFrame -lt 16) {
        $currentCenter = $CurrentFrame * 22.5
        $delta = (($normalized - $currentCenter + 540.0) % 360.0) - 180.0
        if ([Math]::Abs($delta) -le (11.25 + [Math]::Max(0.0, $HysteresisDegrees))) {
            return $CurrentFrame
        }
    }

    return [int]([Math]::Floor(($normalized + 11.25) / 22.5) % 16)
}

function Get-NextLookFrame {
    param(
        [Parameter(Mandatory = $true)][int]$CurrentFrame,
        [Parameter(Mandatory = $true)][int]$TargetFrame
    )

    if ($CurrentFrame -lt 0) { return $TargetFrame }
    if ($CurrentFrame -eq $TargetFrame) { return $CurrentFrame }

    $clockwiseSteps = ($TargetFrame - $CurrentFrame + 16) % 16
    $counterClockwiseSteps = ($CurrentFrame - $TargetFrame + 16) % 16
    if ($clockwiseSteps -le $counterClockwiseSteps) {
        return ($CurrentFrame + 1) % 16
    }
    return ($CurrentFrame + 15) % 16
}
