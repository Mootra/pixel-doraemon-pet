[CmdletBinding()]
param(
    [string]$InstallRoot = "",
    [switch]$NoDesktopShortcut,
    [switch]$NoStartMenuShortcut
)

$ErrorActionPreference = "Stop"
$pluginRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $pluginRoot "launcher\PixelDoraemonCompanion.cs"
$iconPath = Join-Path $pluginRoot "assets\pixel-doraemon.ico"

if ([string]::IsNullOrWhiteSpace($InstallRoot)) {
    $InstallRoot = Join-Path $env:LOCALAPPDATA "PixelDoraemonCompanion"
}
$InstallRoot = [IO.Path]::GetFullPath($InstallRoot)
$exePath = Join-Path $InstallRoot "Pixel Doraemon Companion.exe"

$compilerCandidates = @(
    (Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"),
    (Join-Path $env:WINDIR "Microsoft.NET\Framework\v4.0.30319\csc.exe")
)
$compiler = $compilerCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if ([string]::IsNullOrWhiteSpace($compiler)) {
    throw ".NET Framework C# compiler was not found."
}
if (-not (Test-Path -LiteralPath $sourcePath)) { throw "Missing launcher source: $sourcePath" }
if (-not (Test-Path -LiteralPath $iconPath)) { throw "Missing launcher icon: $iconPath" }

New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null
$compilerArgs = @(
    "/nologo",
    "/target:winexe",
    "/optimize+",
    "/platform:anycpu",
    ("/win32icon:{0}" -f $iconPath),
    "/reference:System.dll",
    "/reference:System.Core.dll",
    "/reference:System.Windows.Forms.dll",
    ("/out:{0}" -f $exePath),
    $sourcePath
)
& $compiler $compilerArgs
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $exePath)) {
    throw "Failed to build the GUI launcher."
}

Copy-Item -LiteralPath $iconPath -Destination (Join-Path $InstallRoot "pixel-doraemon.ico") -Force
$shortcutName = (-join @([char]0x542F, [char]0x52A8, [char]0x54C6, [char]0x5566)) + " Companion.lnk"
$shell = New-Object -ComObject WScript.Shell

function New-LauncherShortcut([string]$ShortcutPath) {
    $parent = [IO.Path]::GetDirectoryName($ShortcutPath)
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $shortcut = $shell.CreateShortcut($ShortcutPath)
    $shortcut.TargetPath = $exePath
    $shortcut.WorkingDirectory = $InstallRoot
    $shortcut.IconLocation = "$exePath,0"
    $shortcut.Description = "Launch Pixel Doraemon Companion without a console window."
    $shortcut.WindowStyle = 1
    $shortcut.Save()
}

$desktopShortcut = $null
if (-not $NoDesktopShortcut) {
    $desktopShortcut = Join-Path ([Environment]::GetFolderPath("Desktop")) $shortcutName
    New-LauncherShortcut $desktopShortcut
}

$startMenuShortcut = $null
if (-not $NoStartMenuShortcut) {
    $startMenuDir = Join-Path ([Environment]::GetFolderPath("Programs")) "Pixel Doraemon Companion"
    $startMenuShortcut = Join-Path $startMenuDir $shortcutName
    New-LauncherShortcut $startMenuShortcut
}

[pscustomobject]@{
    ok = $true
    executable = $exePath
    desktopShortcut = $desktopShortcut
    startMenuShortcut = $startMenuShortcut
    icon = (Join-Path $InstallRoot "pixel-doraemon.ico")
} | ConvertTo-Json -Depth 3
