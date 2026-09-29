$ErrorActionPreference = "Stop"

$pluginRoot = Split-Path -Parent $PSScriptRoot
$overlayPath = Join-Path $pluginRoot "scripts\companion-overlay.ps1"
$startPath = Join-Path $pluginRoot "scripts\start-companion.ps1"
$profileModelPath = Join-Path $pluginRoot "scripts\profile-model.ps1"
$defaultConfigPath = Join-Path $pluginRoot "config\default-config.json"
$bundledSpritePaths = @{
    v2 = Join-Path $pluginRoot "assets\spritesheet-v2.png"
    v3 = Join-Path $pluginRoot "assets\spritesheet-v3.png"
}
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("pixel-doraemon-profile-isolation-{0}" -f [Guid]::NewGuid().ToString("N"))
$originalCodexHome = $env:CODEX_HOME
$startScript = Get-Content -Raw -Encoding UTF8 -LiteralPath $startPath

foreach ($marker in @('Resolve-CompanionProfile', '$PSBoundParameters.ContainsKey("Profile")', 'active-profile.json')) {
    if ($startScript -notmatch [regex]::Escape($marker)) {
        throw "The launcher must preserve the last explicitly selected profile when Profile is omitted: $marker"
    }
}

. $profileModelPath
$savedProfilePath = Join-Path $testRoot "active-profile.json"
New-Item -ItemType Directory -Force -Path $testRoot | Out-Null
[ordered]@{ profile = "v3" } | ConvertTo-Json | Set-Content -LiteralPath $savedProfilePath -Encoding UTF8
if ((Resolve-CompanionProfile -RequestedProfile "v2" -WasExplicit $false -ActiveProfilePath $savedProfilePath) -ne "v3") {
    throw "An omitted Profile must preserve the saved v3 selection."
}
if ((Resolve-CompanionProfile -RequestedProfile "v2" -WasExplicit $true -ActiveProfilePath $savedProfilePath) -ne "v2") {
    throw "An explicit v2 selection must override the saved v3 selection."
}
[ordered]@{ profile = "broken" } | ConvertTo-Json | Set-Content -LiteralPath $savedProfilePath -Encoding UTF8
if ((Resolve-CompanionProfile -RequestedProfile "v2" -WasExplicit $false -ActiveProfilePath $savedProfilePath) -ne "v2") {
    throw "An invalid saved profile must fall back safely."
}

try {
    $codexHome = Join-Path $testRoot "codex-home"
    $sharedDataRoot = Join-Path $testRoot "shared"
    New-Item -ItemType Directory -Force -Path $sharedDataRoot | Out-Null

    foreach ($profile in @(
        @{ Name = "v2"; PetId = "pixel-doraemon" },
        @{ Name = "v3"; PetId = "pixel-doraemon-v3" }
    )) {
        $petRoot = Join-Path (Join-Path $codexHome "pets") $profile.PetId
        $profileDataRoot = Join-Path (Join-Path $testRoot "profiles") $profile.Name
        New-Item -ItemType Directory -Force -Path $petRoot, $profileDataRoot | Out-Null
        Copy-Item -LiteralPath $bundledSpritePaths[$profile.Name] -Destination (Join-Path $petRoot "spritesheet.png")
        [ordered]@{
            id = $profile.PetId
            spritesheetPath = "spritesheet.png"
            spriteVersionNumber = 2
        } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $petRoot "pet.json") -Encoding UTF8
        Copy-Item -LiteralPath $defaultConfigPath -Destination (Join-Path $profileDataRoot "config.json")

        $env:CODEX_HOME = $codexHome
        $raw = & powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File $overlayPath `
            -PluginRoot $pluginRoot `
            -DataRoot $profileDataRoot `
            -SharedDataRoot $sharedDataRoot `
            -AssetPetId $profile.PetId `
            -InstanceName $profile.Name `
            -ValidateOnly
        $result = $raw | ConvertFrom-Json
        $expectedSprite = Join-Path $petRoot "spritesheet.png"
        if ([string]$result.assetPetId -ne $profile.PetId) {
            throw "Profile $($profile.Name) resolved $($result.assetPetId), expected $($profile.PetId)."
        }
        if ([IO.Path]::GetFullPath([string]$result.spritePath) -ne [IO.Path]::GetFullPath($expectedSprite)) {
            throw "Profile $($profile.Name) resolved the wrong spritesheet."
        }

        Remove-Item -LiteralPath $petRoot -Recurse -Force
        $fallbackRaw = & powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File $overlayPath `
            -PluginRoot $pluginRoot `
            -DataRoot $profileDataRoot `
            -SharedDataRoot $sharedDataRoot `
            -AssetPetId $profile.PetId `
            -InstanceName $profile.Name `
            -ValidateOnly
        $fallback = $fallbackRaw | ConvertFrom-Json
        if ([IO.Path]::GetFullPath([string]$fallback.spritePath) -ne [IO.Path]::GetFullPath($bundledSpritePaths[$profile.Name])) {
            throw "Profile $($profile.Name) resolved the wrong bundled fallback spritesheet."
        }
    }

    "PASS v2/v3 profile isolation"
} finally {
    $env:CODEX_HOME = $originalCodexHome
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
