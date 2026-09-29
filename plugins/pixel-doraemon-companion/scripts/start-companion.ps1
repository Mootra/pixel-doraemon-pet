param(
    [ValidateSet("v2", "v3")][string]$Profile = "v2",
    [switch]$Restart
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "profile-model.ps1")

function Get-CodexHome {
    if (-not [string]::IsNullOrWhiteSpace($env:CODEX_HOME)) {
        return $env:CODEX_HOME
    }
    return (Join-Path $env:USERPROFILE ".codex")
}

function Get-ActivePluginRoot {
    $currentRoot = Split-Path -Parent $PSScriptRoot
    if (Test-Path -LiteralPath (Join-Path $currentRoot "hooks\pet-event.ps1")) {
        return $currentRoot
    }

    $cacheRoot = Join-Path (Get-CodexHome) "plugins\cache"
    if (Test-Path -LiteralPath $cacheRoot) {
        $candidate = Get-ChildItem -LiteralPath $cacheRoot -Directory |
            ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -Directory -ErrorAction SilentlyContinue } |
            Where-Object { $_.Name -eq "pixel-doraemon-companion" } |
            ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -Directory -ErrorAction SilentlyContinue } |
            Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName "hooks\pet-event.ps1") } |
            Sort-Object LastWriteTimeUtc -Descending |
            Select-Object -First 1
        if ($null -ne $candidate) { return $candidate.FullName }
    }

    return $currentRoot
}

$profileMap = @{
    v2 = @{ PetId = "pixel-doraemon"; InstanceName = "v2" }
    v3 = @{ PetId = "pixel-doraemon-v3"; InstanceName = "v3" }
}
$persistentRoot = Join-Path ([Environment]::GetFolderPath("LocalApplicationData")) "PixelDoraemonCompanion"
$activeProfilePath = Join-Path $persistentRoot "active-profile.json"
$Profile = Resolve-CompanionProfile `
    -RequestedProfile $Profile `
    -WasExplicit $PSBoundParameters.ContainsKey("Profile") `
    -ActiveProfilePath $activeProfilePath
$selectedProfile = $profileMap[$Profile]
$pluginRoot = Get-ActivePluginRoot
$sharedDataRoot = Join-Path $pluginRoot ".data"
$profileDataRoot = Join-Path (Join-Path $persistentRoot "profiles") $Profile
$pidPath = Join-Path $profileDataRoot "overlay.pid"

function Get-RunningCompanionOverlays {
    try {
        return @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
            $_.ProcessId -ne $PID -and
            $_.CommandLine -match 'companion-overlay\.ps1' -and
            $_.CommandLine -like '*PixelDoraemonCompanion*'
        })
    } catch {
        return @()
    }
}

New-Item -ItemType Directory -Force -Path $sharedDataRoot, $profileDataRoot | Out-Null
[ordered]@{
    profile = $Profile
    petId = $selectedProfile.PetId
    updatedAtUtc = [DateTime]::UtcNow.ToString("o")
} | ConvertTo-Json | Set-Content -LiteralPath $activeProfilePath -Encoding UTF8

$runningOverlays = @(Get-RunningCompanionOverlays)
$escapedProfileDataRoot = [Regex]::Escape($profileDataRoot)
$selectedOverlays = @($runningOverlays | Where-Object { $_.CommandLine -match $escapedProfileDataRoot })
$otherOverlays = @($runningOverlays | Where-Object { $_.CommandLine -notmatch $escapedProfileDataRoot })

foreach ($overlay in $otherOverlays) {
    Stop-Process -Id $overlay.ProcessId -Force -ErrorAction SilentlyContinue
}
if ($otherOverlays.Count -gt 0) {
    foreach ($otherProfile in @("v2", "v3") | Where-Object { $_ -ne $Profile }) {
        Remove-Item -LiteralPath (Join-Path (Join-Path (Join-Path $persistentRoot "profiles") $otherProfile) "overlay.pid") -Force -ErrorAction SilentlyContinue
    }
}

if ($Restart) {
    foreach ($overlay in $selectedOverlays) {
        Stop-Process -Id $overlay.ProcessId -Force -ErrorAction SilentlyContinue
    }
    if ($runningOverlays.Count -gt 0) { Start-Sleep -Milliseconds 250 }
    Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
} elseif ($selectedOverlays.Count -gt 0) {
    return
}

$env:PLUGIN_ROOT = $pluginRoot
$env:PLUGIN_DATA = $sharedDataRoot
$env:PIXEL_DORAEMON_PROFILE = $Profile
$env:PIXEL_DORAEMON_PET_ID = $selectedProfile.PetId
$env:PIXEL_DORAEMON_PROFILE_DATA = $profileDataRoot
& (Join-Path $pluginRoot "hooks\pet-event.ps1") -Manual
