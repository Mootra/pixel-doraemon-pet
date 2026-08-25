param(
    [Parameter(Mandatory = $true)][string]$ExePath
)

$ErrorActionPreference = "Stop"
$resolved = (Resolve-Path -LiteralPath $ExePath).Path
$bytes = [IO.File]::ReadAllBytes($resolved)
if ($bytes.Length -lt 256) { throw "Launcher is too small to be a valid PE file." }

$peOffset = [BitConverter]::ToInt32($bytes, 0x3C)
if ([Text.Encoding]::ASCII.GetString($bytes, $peOffset, 4) -ne "PE`0`0") {
    throw "Launcher does not have a valid PE signature."
}
$optionalHeader = $peOffset + 24
$subsystem = [BitConverter]::ToUInt16($bytes, $optionalHeader + 68)
if ($subsystem -ne 2) {
    throw "Launcher subsystem is $subsystem; expected 2 (Windows GUI)."
}

Add-Type -AssemblyName System.Drawing
$icon = [System.Drawing.Icon]::ExtractAssociatedIcon($resolved)
if ($null -eq $icon -or $icon.Width -lt 16 -or $icon.Height -lt 16) {
    throw "Launcher does not expose a usable embedded icon."
}
$size = "{0}x{1}" -f $icon.Width, $icon.Height
$icon.Dispose()

"PASS GUI launcher: subsystem=Windows GUI, embedded icon=$size"
