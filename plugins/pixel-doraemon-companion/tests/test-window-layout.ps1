$ErrorActionPreference = "Stop"
. (Join-Path (Split-Path -Parent $PSScriptRoot) "scripts\window-layout.ps1")

$panelHeight = 141.0
$originalPetTop = 500.0
$shownWindowTop = Get-WindowTopPreservingSpriteAnchor $originalPetTop $false $true $panelHeight
$shownPetTop = $shownWindowTop + $panelHeight
if ($shownPetTop -ne $originalPetTop) {
    throw "Showing the bubble moved the pet from $originalPetTop to $shownPetTop."
}

$hiddenWindowTop = Get-WindowTopPreservingSpriteAnchor $shownWindowTop $true $false $panelHeight
if ($hiddenWindowTop -ne $originalPetTop) {
    throw "Hiding the bubble moved the pet from $originalPetTop to $hiddenWindowTop."
}

$unchangedWindowTop = Get-WindowTopPreservingSpriteAnchor 275.0 $true $true $panelHeight
if ($unchangedWindowTop -ne 275.0) {
    throw "Keeping the bubble visible unexpectedly moved the window."
}

"PASS bubble reflow preserves the pet screen position"
