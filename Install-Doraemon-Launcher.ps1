[CmdletBinding()]
param(
    [string]$InstallRoot = "",
    [switch]$NoDesktopShortcut,
    [switch]$NoStartMenuShortcut
)

$ErrorActionPreference = "Stop"
$installer = Join-Path $PSScriptRoot "plugins\pixel-doraemon-companion\scripts\install-launcher.ps1"
& $installer -InstallRoot $InstallRoot -NoDesktopShortcut:$NoDesktopShortcut -NoStartMenuShortcut:$NoStartMenuShortcut
