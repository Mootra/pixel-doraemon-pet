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

$petRoot = [IO.Path]::GetFullPath((Join-Path $CodexHome "pets"))
$targetDir = [IO.Path]::GetFullPath((Join-Path $petRoot $petId))
if ([IO.Path]::GetDirectoryName($targetDir).TrimEnd('\') -ne $petRoot.TrimEnd('\')) {
    throw "Unsafe target path: $targetDir"
}
if (Test-Path -LiteralPath $targetDir) {
    Remove-Item -LiteralPath $targetDir -Recurse -Force
}

$configPath = Join-Path $CodexHome "config.toml"
if (Test-Path -LiteralPath $configPath) {
    $content = Get-Content -Raw -Encoding UTF8 -LiteralPath $configPath
    if ($null -eq $content) { $content = "" }
    $newline = if ($content.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lines = @([regex]::Split($content, "\r?\n"))
    $output = New-Object System.Collections.Generic.List[string]
    $inDesktop = $false
    foreach ($line in $lines) {
        if ($line -match '^\s*\[[^]]+\]\s*$') {
            $inDesktop = $line -match '^\s*\[desktop\]\s*$'
            [void]$output.Add($line)
            continue
        }
        if ($inDesktop -and $line -match ('^\s*selected-avatar-id\s*=\s*"{0}"\s*$' -f [regex]::Escape($selectedId))) {
            continue
        }
        [void]$output.Add($line)
    }
    $newContent = ($output -join $newline).TrimEnd("`r", "`n") + $newline
    Write-Utf8FileAtomically $configPath $newContent
}

Write-Host "Removed Pixel Doraemon V3 from $targetDir"
Write-Host "Restart Codex to refresh the pet list."
