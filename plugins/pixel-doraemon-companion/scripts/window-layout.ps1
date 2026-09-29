function Get-WindowTopPreservingSpriteAnchor(
    [double]$CurrentWindowTop,
    [bool]$WasBubbleVisible,
    [bool]$WillBubbleBeVisible,
    [double]$BubblePanelHeight
) {
    $currentSpriteTop = $CurrentWindowTop + $(if ($WasBubbleVisible) { $BubblePanelHeight } else { 0 })
    return $currentSpriteTop - $(if ($WillBubbleBeVisible) { $BubblePanelHeight } else { 0 })
}
