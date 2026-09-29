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
$v2ExePath = Join-Path $InstallRoot "Pixel Doraemon Companion.exe"
$v3ExePath = Join-Path $InstallRoot "Pixel Doraemon Companion V3.exe"

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
    ("/out:{0}" -f $v2ExePath),
    $sourcePath
)
& $compiler $compilerArgs
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $v2ExePath)) {
    throw "Failed to build the GUI launcher."
}
Copy-Item -LiteralPath $v2ExePath -Destination $v3ExePath -Force

Copy-Item -LiteralPath $iconPath -Destination (Join-Path $InstallRoot "pixel-doraemon.ico") -Force
$v2ShortcutName = (-join @([char]0x542F, [char]0x52A8, [char]0x54C6, [char]0x5566, [char]0x0041, [char]0x68A6, [char]0x4F19, [char]0x4F34)) + ".lnk"
$v3ShortcutName = (-join @([char]0x542F, [char]0x52A8, [char]0x54C6, [char]0x5566, [char]0x0041, [char]0x68A6, [char]0x0020, [char]0x0056, [char]0x0033, [char]0x4F19, [char]0x4F34)) + ".lnk"
$shell = New-Object -ComObject WScript.Shell

function New-LauncherShortcut([string]$ShortcutPath, [string]$TargetPath, [string]$Description) {
    $parent = [IO.Path]::GetDirectoryName($ShortcutPath)
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $shortcut = $shell.CreateShortcut($ShortcutPath)
    $shortcut.TargetPath = $TargetPath
    $shortcut.WorkingDirectory = $InstallRoot
    $shortcut.IconLocation = "$TargetPath,0"
    $shortcut.Description = $Description
    $shortcut.WindowStyle = 1
    $shortcut.Save()
}

$descriptionV2 = (-join @([char]0x542F, [char]0x52A8, [char]0x54C6, [char]0x5566, [char]0x0041, [char]0x68A6, [char]0x0020, [char]0x0056, [char]0x0032, [char]0x4F19, [char]0x4F34, [char]0x3002))
$descriptionV3 = (-join @([char]0x542F, [char]0x52A8, [char]0x54C6, [char]0x5566, [char]0x0041, [char]0x68A6, [char]0x0020, [char]0x0056, [char]0x0033, [char]0x4F19, [char]0x4F34, [char]0x3002))
$desktopShortcutV2 = $null
$desktopShortcutV3 = $null
if (-not $NoDesktopShortcut) {
    $desktopShortcutV2 = Join-Path ([Environment]::GetFolderPath("Desktop")) $v2ShortcutName
    $desktopShortcutV3 = Join-Path ([Environment]::GetFolderPath("Desktop")) $v3ShortcutName
    New-LauncherShortcut $desktopShortcutV2 $v2ExePath $descriptionV2
    New-LauncherShortcut $desktopShortcutV3 $v3ExePath $descriptionV3
}

$startMenuShortcutV2 = $null
$startMenuShortcutV3 = $null
if (-not $NoStartMenuShortcut) {
    $startMenuDir = Join-Path ([Environment]::GetFolderPath("Programs")) ((-join @([char]0x54C6, [char]0x5566, [char]0x0041, [char]0x68A6, [char]0x4F19, [char]0x4F34)))
    $startMenuShortcutV2 = Join-Path $startMenuDir $v2ShortcutName
    $startMenuShortcutV3 = Join-Path $startMenuDir $v3ShortcutName
    New-LauncherShortcut $startMenuShortcutV2 $v2ExePath $descriptionV2
    New-LauncherShortcut $startMenuShortcutV3 $v3ExePath $descriptionV3
}

[pscustomobject]@{
    ok = $true
    v2Executable = $v2ExePath
    v3Executable = $v3ExePath
    desktopShortcutV2 = $desktopShortcutV2
    desktopShortcutV3 = $desktopShortcutV3
    startMenuShortcutV2 = $startMenuShortcutV2
    startMenuShortcutV3 = $startMenuShortcutV3
    icon = (Join-Path $InstallRoot "pixel-doraemon.ico")
} | ConvertTo-Json -Depth 3
