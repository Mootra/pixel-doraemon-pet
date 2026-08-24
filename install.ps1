[CmdletBinding()]
param(
    [string]$CodexHome = ""
)

$ErrorActionPreference = "Stop"
$petId = "pixel-doraemon-v3"
$selectedId = "custom:$petId"

if ([string]::IsNullOrWhiteSpace($CodexHome)) {
    $CodexHome = if (-not [string]::IsNullOrWhiteSpace($env:CODEX_HOME)) {
        $env:CODEX_HOME
    } else {
        Join-Path $env:USERPROFILE ".codex"
    }
}

function Write-Utf8FileAtomically([string]$Path, [string]$Content) {
    $directory = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Path))
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    $tempPath = Join-Path $directory (".{0}.{1}.tmp" -f [IO.Path]::GetFileName($Path), $PID)
    $hasBom = $false
    if (Test-Path -LiteralPath $Path) {
        $bytes = [IO.File]::ReadAllBytes($Path)
        $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    }
    $encoding = New-Object System.Text.UTF8Encoding($hasBom)
    try {
        [IO.File]::WriteAllText($tempPath, $Content, $encoding)
        Move-Item -Force -LiteralPath $tempPath -Destination $Path
    } finally {
        Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
    }
}

function Set-SelectedAvatar([string]$ConfigPath, [string]$AvatarId) {
    $content = if (Test-Path -LiteralPath $ConfigPath) {
        Get-Content -Raw -Encoding UTF8 -LiteralPath $ConfigPath
    } else {
        ""
    }
    if ($null -eq $content) { $content = "" }
    $newline = if ($content.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lines = @([regex]::Split($content, "\r?\n"))
    $output = New-Object System.Collections.Generic.List[string]
    $inDesktop = $false
    $sawDesktop = $false
    $wroteSelection = $false

    foreach ($line in $lines) {
        if ($line -match '^\s*\[[^]]+\]\s*$') {
            if ($inDesktop -and -not $wroteSelection) {
                [void]$output.Add(('selected-avatar-id = "{0}"' -f $AvatarId))
                $wroteSelection = $true
            }
            $inDesktop = $line -match '^\s*\[desktop\]\s*$'
            if ($inDesktop) { $sawDesktop = $true }
            [void]$output.Add($line)
            continue
        }
        if ($inDesktop -and $line -match '^\s*selected-avatar-id\s*=') {
            [void]$output.Add(('selected-avatar-id = "{0}"' -f $AvatarId))
            $wroteSelection = $true
        } else {
            [void]$output.Add($line)
        }
    }

    if ($inDesktop -and -not $wroteSelection) {
        [void]$output.Add(('selected-avatar-id = "{0}"' -f $AvatarId))
        $wroteSelection = $true
    }
    if (-not $sawDesktop) {
        if ($output.Count -gt 0 -and $output[$output.Count - 1] -ne "") { [void]$output.Add("") }
        [void]$output.Add("[desktop]")
        [void]$output.Add(('selected-avatar-id = "{0}"' -f $AvatarId))
    }

    $newContent = ($output -join $newline).TrimStart("`r", "`n").TrimEnd("`r", "`n") + $newline
    Write-Utf8FileAtomically $ConfigPath $newContent
}

$sourceDir = Join-Path $PSScriptRoot "output-v3"
$petJsonPath = Join-Path $sourceDir "pet.json"
if (-not (Test-Path -LiteralPath $petJsonPath)) {
    throw "Pet package is incomplete: $petJsonPath"
}
$pet = Get-Content -Raw -Encoding UTF8 -LiteralPath $petJsonPath | ConvertFrom-Json
if ([string]$pet.id -ne $petId) {
    throw "Unexpected pet id '$($pet.id)'; expected '$petId'."
}
$spriteName = [string]$pet.spritesheetPath
$spritePath = Join-Path $sourceDir $spriteName
if (-not (Test-Path -LiteralPath $spritePath)) {
    throw "Pet package is incomplete: $spritePath"
}

$petRoot = [IO.Path]::GetFullPath((Join-Path $CodexHome "pets"))
$targetDir = [IO.Path]::GetFullPath((Join-Path $petRoot $petId))
if ([IO.Path]::GetDirectoryName($targetDir).TrimEnd('\') -ne $petRoot.TrimEnd('\')) {
    throw "Unsafe target path: $targetDir"
}
New-Item -ItemType Directory -Force -Path $targetDir | Out-Null

$tempPet = Join-Path $targetDir (".pet.json.{0}.tmp" -f $PID)
$tempSprite = Join-Path $targetDir (".{0}.{1}.tmp" -f $spriteName, $PID)
try {
    Copy-Item -LiteralPath $petJsonPath -Destination $tempPet -Force
    Copy-Item -LiteralPath $spritePath -Destination $tempSprite -Force
    Move-Item -Force -LiteralPath $tempSprite -Destination (Join-Path $targetDir $spriteName)
    Move-Item -Force -LiteralPath $tempPet -Destination (Join-Path $targetDir "pet.json")
} finally {
    Remove-Item -LiteralPath $tempPet, $tempSprite -Force -ErrorAction SilentlyContinue
}

$configPath = Join-Path $CodexHome "config.toml"
Set-SelectedAvatar $configPath $selectedId

Write-Host "Installed Pixel Doraemon V3 to $targetDir"
Write-Host "Selected $selectedId in $configPath"
Write-Host "Restart Codex to load the pet."
