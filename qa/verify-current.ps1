$ErrorActionPreference = "Stop"

$qaRoot = $PSScriptRoot
$currentRoot = Join-Path $qaRoot "current"
$manifestPath = Join-Path $currentRoot "source.json"
$manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $manifestPath | ConvertFrom-Json

function Assert-FileHash([string]$Path, [string]$ExpectedHash, [string]$Label) {
    $resolved = (Resolve-Path -LiteralPath $Path).Path
    $actualHash = (Get-FileHash -LiteralPath $resolved -Algorithm SHA256).Hash
    if ($actualHash -ne $ExpectedHash) {
        throw "$Label hash mismatch. Expected $ExpectedHash but found $actualHash at $resolved"
    }
    return $actualHash
}

$sourcePath = [IO.Path]::GetFullPath((Join-Path $currentRoot ([string]$manifest.source)))
$sourceHash = Assert-FileHash $sourcePath ([string]$manifest.sourceSha256) "Published spritesheet"
$contactHash = Assert-FileHash (Join-Path $currentRoot ([string]$manifest.contactSheet)) ([string]$manifest.contactSheetSha256) "Current contact sheet"
$directionHash = Assert-FileHash (Join-Path $currentRoot ([string]$manifest.lookDirections)) ([string]$manifest.lookDirectionsSha256) "Current look-direction sheet"

$codexRoot = if ($env:CODEX_HOME) {
    $env:CODEX_HOME
} else {
    Join-Path ([Environment]::GetFolderPath("UserProfile")) ".codex"
}
$installedPath = Join-Path $codexRoot ("pets\{0}\spritesheet.png" -f $manifest.petId)
$installedMatches = $null
if (Test-Path -LiteralPath $installedPath) {
    $installedMatches = (Get-FileHash -LiteralPath $installedPath -Algorithm SHA256).Hash -eq $sourceHash
    if (-not $installedMatches) {
        throw "Installed pet differs from output-v3: $installedPath"
    }
}

[pscustomobject]@{
    ok = $true
    petId = $manifest.petId
    classification = $manifest.classification
    source = $sourcePath
    sourceSha256 = $sourceHash
    contactSheetSha256 = $contactHash
    lookDirectionsSha256 = $directionHash
    installedPath = if (Test-Path -LiteralPath $installedPath) { $installedPath } else { $null }
    installedMatchesSource = $installedMatches
} | ConvertTo-Json -Depth 3
