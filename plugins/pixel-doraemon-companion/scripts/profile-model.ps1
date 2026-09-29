function Resolve-CompanionProfile {
    param(
        [ValidateSet("v2", "v3")][string]$RequestedProfile = "v2",
        [bool]$WasExplicit,
        [string]$ActiveProfilePath
    )

    if ($WasExplicit -or -not (Test-Path -LiteralPath $ActiveProfilePath)) {
        return $RequestedProfile
    }

    try {
        $storedProfile = [string](Get-Content -Raw -Encoding UTF8 -LiteralPath $ActiveProfilePath | ConvertFrom-Json).profile
        if ($storedProfile -in @("v2", "v3")) {
            return $storedProfile
        }
    } catch {
        # A missing or damaged selection must not prevent the companion from starting.
    }

    return $RequestedProfile
}
