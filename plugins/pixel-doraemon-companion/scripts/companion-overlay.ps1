param(
    [Parameter(Mandatory = $true)][string]$PluginRoot,
    [Parameter(Mandatory = $true)][string]$DataRoot,
    [switch]$ValidateOnly,
    [string]$PreviewPath
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$frameWidth = 192
$frameHeight = 208
$rowMap = @{
    "idle" = 0
    "running-right" = 1
    "running-left" = 2
    "waving" = 3
    "jumping" = 4
    "failed" = 5
    "waiting" = 6
    "running" = 7
    "review" = 8
}
$frameCounts = @{
    "idle" = 6
    "running-right" = 8
    "running-left" = 8
    "waving" = 4
    "jumping" = 5
    "failed" = 8
    "waiting" = 6
    "running" = 6
    "review" = 6
    "look" = 16
}

$configPath = Join-Path $DataRoot "config.json"
$defaultConfigPath = Join-Path $PluginRoot "config\default-config.json"
$statePath = Join-Path $DataRoot "pet-state.json"
$pidPath = Join-Path $DataRoot "overlay.pid"
$usageStatePath = Join-Path $DataRoot "usage-state.json"
$usagePidPath = Join-Path $DataRoot "usage-monitor.pid"
$usageRefreshRequestPath = Join-Path $DataRoot "usage-refresh.request"
$lookDirectionPath = Join-Path $PluginRoot "scripts\look-direction.ps1"
. $lookDirectionPath

$script:defaultConfig = Get-Content -Raw -Encoding UTF8 -LiteralPath $defaultConfigPath | ConvertFrom-Json
$script:config = Get-Content -Raw -Encoding UTF8 -LiteralPath $configPath | ConvertFrom-Json

function Get-ConfigValue($UserSection, $DefaultSection, [string]$Name) {
    if ($null -ne $UserSection -and $UserSection.PSObject.Properties.Name -contains $Name) {
        return $UserSection.$Name
    }
    if ($null -ne $DefaultSection -and $DefaultSection.PSObject.Properties.Name -contains $Name) {
        return $DefaultSection.$Name
    }
    return $null
}

function ConvertFrom-UnicodeCodePoints([int[]]$CodePoints) {
    return -join @($CodePoints | ForEach-Object { [char]$_ })
}

function Get-SpriteCandidatePaths {
    $candidates = New-Object System.Collections.Generic.List[string]
    $preferInstalled = [bool](Get-ConfigValue $script:config.asset $script:defaultConfig.asset "preferInstalledCodexPet")
    if ($preferInstalled) {
        $petId = [string](Get-ConfigValue $script:config.asset $script:defaultConfig.asset "petId")
        $codexRoot = if ($env:CODEX_HOME) {
            $env:CODEX_HOME
        } else {
            Join-Path ([Environment]::GetFolderPath("UserProfile")) ".codex"
        }
        $petRoot = Join-Path (Join-Path $codexRoot "pets") $petId
        $manifestPath = Join-Path $petRoot "pet.json"
        if (Test-Path -LiteralPath $manifestPath) {
            try {
                $manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $manifestPath | ConvertFrom-Json
                $declaredPath = Join-Path $petRoot ([string]$manifest.spritesheetPath)
                if ([IO.Path]::GetExtension($declaredPath) -ieq ".png") {
                    [void]$candidates.Add($declaredPath)
                }
                # WPF on Windows does not decode WebP consistently, so prefer the
                # installed PNG sibling used by the custom-pet development package.
                [void]$candidates.Add((Join-Path $petRoot "spritesheet.png"))
            } catch {
                # Fall through to the bundled asset if the installed manifest is incomplete.
            }
        }
    }

    $bundledRelative = [string](Get-ConfigValue $script:config.asset $script:defaultConfig.asset "bundledPath")
    if ([string]::IsNullOrWhiteSpace($bundledRelative)) { $bundledRelative = "assets\spritesheet.png" }
    [void]$candidates.Add((Join-Path $PluginRoot $bundledRelative))
    return $candidates | Select-Object -Unique
}

function New-ValidatedSpriteBitmap([string]$Path) {
    $resolved = (Resolve-Path -LiteralPath $Path).Path
    $candidate = New-Object System.Windows.Media.Imaging.BitmapImage
    $candidate.BeginInit()
    $candidate.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $candidate.UriSource = New-Object System.Uri($resolved)
    $candidate.EndInit()
    $candidate.Freeze()
    if ($candidate.PixelWidth -ne ($frameWidth * 8) -or $candidate.PixelHeight -ne ($frameHeight * 11)) {
        throw "Sprite atlas must be 1536x2288, got $($candidate.PixelWidth)x$($candidate.PixelHeight): $resolved"
    }
    return $candidate
}

function Load-SpriteBitmap {
    $failures = @()
    foreach ($candidatePath in Get-SpriteCandidatePaths) {
        if (-not (Test-Path -LiteralPath $candidatePath)) { continue }
        try {
            $script:bitmap = New-ValidatedSpriteBitmap $candidatePath
            $item = Get-Item -LiteralPath $candidatePath
            $script:spritePath = $item.FullName
            $script:spriteStamp = "{0}:{1}" -f $item.Length, $item.LastWriteTimeUtc.Ticks
            return
        } catch {
            $failures += $_.Exception.Message
        }
    }
    throw "No valid Pixel Doraemon v2 PNG atlas was found. $($failures -join '; ')"
}

$scale = [double](Get-ConfigValue $script:config.window $script:defaultConfig.window "scale")
$usageEnabled = [bool](Get-ConfigValue $script:config.usage $script:defaultConfig.usage "enabled")
Load-SpriteBitmap

if ($ValidateOnly) {
    [pscustomobject]@{
        ok = $true
        spritePath = $script:spritePath
        spriteCandidates = @(Get-SpriteCandidatePaths)
        width = $script:bitmap.PixelWidth
        height = $script:bitmap.PixelHeight
        frameWidth = $frameWidth
        frameHeight = $frameHeight
        rows = 11
        columns = 8
        usageEnabled = $usageEnabled
        usageMonitorPath = (Join-Path $PluginRoot "scripts\usage-monitor.ps1")
    } | ConvertTo-Json -Depth 4
    return
}

$window = New-Object System.Windows.Window
$window.WindowStyle = [System.Windows.WindowStyle]::None
$window.ResizeMode = [System.Windows.ResizeMode]::NoResize
$window.AllowsTransparency = $true
$window.Background = [System.Windows.Media.Brushes]::Transparent
$window.ShowInTaskbar = $false
$window.Topmost = [bool](Get-ConfigValue $script:config.window $script:defaultConfig.window "topmost")
$spriteDisplayWidth = [Math]::Round($frameWidth * $scale)
$spriteDisplayHeight = [Math]::Round($frameHeight * $scale)
$usageBubbleWidth = if ($usageEnabled) { [Math]::Max(210, [Math]::Round(260 * $scale)) } else { 0 }
$usageBubbleHeight = if ($usageEnabled) { [Math]::Max(84, [Math]::Round(102 * $scale)) } else { 0 }
$usagePanelHeight = if ($usageEnabled) { $usageBubbleHeight + 39 } else { 0 }
$window.Width = if ($usageEnabled) {
    [Math]::Max($spriteDisplayWidth, $usageBubbleWidth + 10)
} else {
    $spriteDisplayWidth
}
$window.Height = $spriteDisplayHeight + $usagePanelHeight

$root = New-Object System.Windows.Controls.Grid
$root.SnapsToDevicePixels = $true
$usageRow = New-Object System.Windows.Controls.RowDefinition
$usageRow.Height = New-Object System.Windows.GridLength($usagePanelHeight)
$spriteRow = New-Object System.Windows.Controls.RowDefinition
$spriteRow.Height = New-Object System.Windows.GridLength($spriteDisplayHeight)
[void]$root.RowDefinitions.Add($usageRow)
[void]$root.RowDefinitions.Add($spriteRow)

$brushConverter = New-Object System.Windows.Media.BrushConverter
$doraOutlineBrush = $brushConverter.ConvertFromString("#FF153B6B")
$doraBlueBrush = $brushConverter.ConvertFromString("#FF0051FC")
$doraRedBrush = $brushConverter.ConvertFromString("#FFD90603")
$doraYellowBrush = $brushConverter.ConvertFromString("#FFFBC400")
$usageMutedBrush = $brushConverter.ConvertFromString("#FF64748B")

$usageCanvas = New-Object System.Windows.Controls.Canvas
$usageCanvas.Width = $window.Width
$usageCanvas.Height = $usagePanelHeight
$usageCanvas.Visibility = if ($usageEnabled) {
    [System.Windows.Visibility]::Visible
} else {
    [System.Windows.Visibility]::Collapsed
}

$tailLarge = New-Object System.Windows.Shapes.Ellipse
$tailLarge.Width = 25
$tailLarge.Height = 17
$tailLarge.Fill = [System.Windows.Media.Brushes]::White
$tailLarge.Stroke = $doraOutlineBrush
$tailLarge.StrokeThickness = 3
[System.Windows.Controls.Canvas]::SetLeft($tailLarge, $window.Width - ($spriteDisplayWidth * 0.58))
[System.Windows.Controls.Canvas]::SetTop($tailLarge, $usageBubbleHeight + 5)
[void]$usageCanvas.Children.Add($tailLarge)

$tailSmall = New-Object System.Windows.Shapes.Ellipse
$tailSmall.Width = 13
$tailSmall.Height = 9
$tailSmall.Fill = [System.Windows.Media.Brushes]::White
$tailSmall.Stroke = $doraOutlineBrush
$tailSmall.StrokeThickness = 2.5
[System.Windows.Controls.Canvas]::SetLeft($tailSmall, $window.Width - ($spriteDisplayWidth * 0.48))
[System.Windows.Controls.Canvas]::SetTop($tailSmall, $usageBubbleHeight + 26)
[void]$usageCanvas.Children.Add($tailSmall)

$usageBubble = New-Object System.Windows.Controls.Border
$usageBubble.Width = $usageBubbleWidth
$usageBubble.Height = $usageBubbleHeight
$usageBubble.CornerRadius = New-Object System.Windows.CornerRadius([Math]::Round($usageBubbleHeight / 2))
$usageBubble.Padding = New-Object System.Windows.Thickness(14, 4, 14, 4)
$usageBubble.Background = [System.Windows.Media.Brushes]::White
$usageBubble.BorderBrush = $doraOutlineBrush
$usageBubble.BorderThickness = New-Object System.Windows.Thickness(4)
$usageBubble.SnapsToDevicePixels = $true
$usageBubble.Effect = New-Object System.Windows.Media.Effects.DropShadowEffect -Property @{
    BlurRadius = 0
    Color = [System.Windows.Media.Colors]::Black
    Direction = 315
    Opacity = 0.22
    ShadowDepth = 3
}
[System.Windows.Controls.Canvas]::SetLeft($usageBubble, 4)
[System.Windows.Controls.Canvas]::SetTop($usageBubble, 2)

$usageContent = New-Object System.Windows.Controls.Grid
foreach ($height in @(16, 35, 15)) {
    $row = New-Object System.Windows.Controls.RowDefinition
    $row.Height = New-Object System.Windows.GridLength($height)
    [void]$usageContent.RowDefinitions.Add($row)
}

$usageHeader = New-Object System.Windows.Controls.StackPanel
$usageHeader.Orientation = [System.Windows.Controls.Orientation]::Horizontal
$usageHeader.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
$usageHeader.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

$usageHeaderDot = New-Object System.Windows.Shapes.Ellipse
$usageHeaderDot.Width = 7
$usageHeaderDot.Height = 7
$usageHeaderDot.Fill = $doraRedBrush
$usageHeaderDot.Margin = New-Object System.Windows.Thickness(0, 0, 6, 0)
[void]$usageHeader.Children.Add($usageHeaderDot)

$usageTitleText = New-Object System.Windows.Controls.TextBlock
$usageTitleText.Text = "CODEX " + (ConvertFrom-UnicodeCodePoints @(0x5269, 0x4F59, 0x989D, 0x5EA6))
$usageTitleText.Foreground = $doraOutlineBrush
$usageTitleText.FontFamily = New-Object System.Windows.Media.FontFamily -ArgumentList "Microsoft YaHei UI"
$usageTitleText.FontSize = 11.5
$usageTitleText.FontWeight = [System.Windows.FontWeights]::Bold
$usageTitleText.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
[void]$usageHeader.Children.Add($usageTitleText)
[System.Windows.Controls.Grid]::SetRow($usageHeader, 0)
[void]$usageContent.Children.Add($usageHeader)

$usageValueText = New-Object System.Windows.Controls.TextBlock
$usageValueText.Text = "--"
$usageValueText.Foreground = $doraBlueBrush
$usageValueText.FontFamily = New-Object System.Windows.Media.FontFamily -ArgumentList "Segoe UI"
$usageValueText.FontSize = 30
$usageValueText.FontWeight = [System.Windows.FontWeights]::Bold
$usageValueText.TextAlignment = [System.Windows.TextAlignment]::Center
$usageValueText.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
[System.Windows.Controls.Grid]::SetRow($usageValueText, 1)
[void]$usageContent.Children.Add($usageValueText)

$usageDetailText = New-Object System.Windows.Controls.TextBlock
$usageDetailText.Text = (ConvertFrom-UnicodeCodePoints @(0x6B63, 0x5728, 0x8BFB, 0x53D6)) + " Codex " + (ConvertFrom-UnicodeCodePoints @(0x7528, 0x91CF))
$usageDetailText.Foreground = $usageMutedBrush
$usageDetailText.FontFamily = New-Object System.Windows.Media.FontFamily -ArgumentList "Microsoft YaHei UI"
$usageDetailText.FontSize = 10
$usageDetailText.FontWeight = [System.Windows.FontWeights]::SemiBold
$usageDetailText.TextAlignment = [System.Windows.TextAlignment]::Center
$usageDetailText.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
$usageDetailText.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
[System.Windows.Controls.Grid]::SetRow($usageDetailText, 2)
[void]$usageContent.Children.Add($usageDetailText)

$usageBubble.Child = $usageContent
[void]$usageCanvas.Children.Add($usageBubble)
[System.Windows.Controls.Grid]::SetRow($usageCanvas, 0)
[void]$root.Children.Add($usageCanvas)

$image = New-Object System.Windows.Controls.Image
$image.Width = $spriteDisplayWidth
$image.Height = $spriteDisplayHeight
$image.Stretch = [System.Windows.Media.Stretch]::Fill
$image.SnapsToDevicePixels = $true
$image.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right
[System.Windows.Controls.Grid]::SetRow($image, 1)
[void]$root.Children.Add($image)
$window.Content = $root

$workArea = [System.Windows.SystemParameters]::WorkArea
$window.Left = $workArea.Right - $window.Width - 28
$window.Top = $workArea.Bottom - $window.Height - 40

$script:baseAction = "idle"
$script:temporaryAction = $null
$script:temporaryUntil = [DateTime]::MinValue
$script:stateExpiresAt = [DateTime]::MinValue
$script:lastSequence = -1L
$script:frameIndex = 0
$script:lastFrameAt = [DateTime]::UtcNow
$script:paused = $false
$script:lastSpritePollAt = [DateTime]::MinValue
$script:lookFrame = -1
$script:lookActive = $false
$script:lastLookStepAt = [DateTime]::MinValue
$script:lastUsageStamp = $null
$script:lastUsageMonitorCheck = [DateTime]::MinValue

function Test-UsageMonitorRunning {
    if (-not (Test-Path -LiteralPath $usagePidPath)) { return $false }
    $monitorPid = Get-Content -LiteralPath $usagePidPath -Encoding ASCII -ErrorAction SilentlyContinue
    if (-not $monitorPid) { return $false }
    try {
        $process = Get-CimInstance Win32_Process -Filter ("ProcessId = {0}" -f [int]$monitorPid) -ErrorAction Stop
        return ($null -ne $process -and $process.CommandLine -like "*usage-monitor.ps1*")
    } catch {
        return $false
    }
}

function Start-UsageMonitor {
    if (-not $usageEnabled -or (Test-UsageMonitorRunning)) { return }
    $monitorPath = Join-Path $PluginRoot "scripts\usage-monitor.ps1"
    if (-not (Test-Path -LiteralPath $monitorPath)) { return }

    $pollMs = [int](Get-ConfigValue $script:config.usage $script:defaultConfig.usage "pollMs")
    $arguments = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", ('"{0}"' -f $monitorPath),
        "-DataRoot", ('"{0}"' -f $DataRoot),
        "-PollMs", $pollMs,
        "-OwnerPid", $PID
    )
    Start-Process -FilePath "powershell.exe" -ArgumentList $arguments -WindowStyle Hidden | Out-Null
}

function Get-UsageDurationLabel($Minutes) {
    if ($null -eq $Minutes) { return "window" }
    $value = [long]$Minutes
    if ($value -ge 1440 -and $value % 1440 -eq 0) { return ("{0}d" -f ($value / 1440)) }
    if ($value -ge 60 -and $value % 60 -eq 0) { return ("{0}h" -f ($value / 60)) }
    return ("{0}m" -f $value)
}

function Get-UsageResetLabel($EpochSeconds) {
    if ($null -eq $EpochSeconds) { return $null }
    try {
        return [DateTimeOffset]::FromUnixTimeSeconds([long]$EpochSeconds).ToLocalTime().ToString("MMM d HH:mm")
    } catch {
        return $null
    }
}

function Set-UsageUnavailable([string]$Reason) {
    $usageValueText.Text = "--"
    $usageValueText.Foreground = $usageMutedBrush
    $usageDetailText.Text = ConvertFrom-UnicodeCodePoints @(0x989D, 0x5EA6, 0x6682, 0x4E0D, 0x53EF, 0x7528)
    $usageBubble.ToolTip = if ([string]::IsNullOrWhiteSpace($Reason)) {
        "Codex remaining usage is temporarily unavailable."
    } else {
        "Codex remaining usage is temporarily unavailable.`n$Reason"
    }
}

function Update-UsageDisplay {
    if (-not $usageEnabled -or -not (Test-Path -LiteralPath $usageStatePath)) { return }
    try {
        $item = Get-Item -LiteralPath $usageStatePath
        $stamp = "{0}:{1}" -f $item.Length, $item.LastWriteTimeUtc.Ticks
        if ($stamp -eq $script:lastUsageStamp) { return }
        $state = Get-Content -Raw -Encoding UTF8 -LiteralPath $usageStatePath | ConvertFrom-Json
        $script:lastUsageStamp = $stamp

        if (-not [bool]$state.available) {
            Set-UsageUnavailable ([string]$state.error)
            return
        }

        $labelParts = New-Object System.Collections.Generic.List[string]
        $detailParts = New-Object System.Collections.Generic.List[string]
        $remainingValues = New-Object System.Collections.Generic.List[int]
        $showResetTime = [bool](Get-ConfigValue $script:config.usage $script:defaultConfig.usage "showResetTime")
        foreach ($usageWindow in @($state.windows)) {
            $duration = Get-UsageDurationLabel $usageWindow.windowDurationMins
            $remaining = [int]$usageWindow.remainingPercent
            [void]$remainingValues.Add($remaining)
            [void]$labelParts.Add(("{0} {1}%" -f $duration, $remaining))

            $detail = "{0} window: {1}% remaining" -f $duration, $remaining
            if ($showResetTime) {
                $reset = Get-UsageResetLabel $usageWindow.resetsAt
                if ($reset) { $detail += ", resets $reset" }
            }
            [void]$detailParts.Add($detail)
        }

        if ($labelParts.Count -eq 0 -and $null -ne $state.credits -and [bool]$state.credits.unlimited) {
            [void]$labelParts.Add("unlimited")
            [void]$detailParts.Add("Current Codex usage is unlimited")
        }
        if ($labelParts.Count -eq 0) {
            Set-UsageUnavailable "The current account returned no displayable usage window."
            return
        }

        $tooltip = New-Object System.Collections.Generic.List[string]
        [void]$tooltip.Add("Codex remaining usage")
        foreach ($detail in $detailParts) { [void]$tooltip.Add($detail) }
        if ($null -ne $state.credits -and [bool]$state.credits.hasCredits -and -not [bool]$state.credits.unlimited) {
            [void]$tooltip.Add(("Available credits: {0}" -f $state.credits.balance))
        }
        [void]$tooltip.Add(("Updated: {0}" -f ([DateTime]$state.timestampUtc).ToLocalTime().ToString("HH:mm:ss")))
        $usageBubble.ToolTip = $tooltip -join "`n"

        $minimumRemaining = if ($remainingValues.Count -gt 0) {
            ($remainingValues | Measure-Object -Minimum).Minimum
        } else {
            100
        }
        if ($remainingValues.Count -gt 0) {
            $usageValueText.Text = "{0}%" -f $minimumRemaining
            $usageDetailText.Text = $labelParts -join ("  " + [char]0x00B7 + "  ")
        } else {
            $usageValueText.Text = [char]0x221E
            $usageDetailText.Text = ConvertFrom-UnicodeCodePoints @(0x5F53, 0x524D, 0x8D26, 0x6237, 0x4E0D, 0x9650, 0x91CF)
        }
        $color = if ($minimumRemaining -le 20) {
            "#FFD90603"
        } elseif ($minimumRemaining -le 50) {
            "#FFC88600"
        } else {
            "#FF0051FC"
        }
        $usageValueText.Foreground = $brushConverter.ConvertFromString($color)
    } catch {
        Set-UsageUnavailable $_.Exception.Message
    }
}

function Set-Frame([string]$Action, [int]$Frame) {
    if ($Action -eq "look") {
        $row = if ($Frame -lt 8) { 9 } else { 10 }
        $column = $Frame % 8
    } else {
        $row = [int]$rowMap[$Action]
        $column = $Frame % [int]$frameCounts[$Action]
    }

    $rect = New-Object System.Windows.Int32Rect(
        ($column * $frameWidth),
        ($row * $frameHeight),
        $frameWidth,
        $frameHeight
    )
    $crop = New-Object System.Windows.Media.Imaging.CroppedBitmap($script:bitmap, $rect)
    $crop.Freeze()
    $image.Source = $crop
}

function Start-TemporaryAction([string]$Action) {
    $script:temporaryAction = $Action
    $script:temporaryUntil = [DateTime]::UtcNow.AddMilliseconds([int]$script:config.holdMs.Click)
    $script:frameIndex = 0
    $script:lastFrameAt = [DateTime]::UtcNow
}

function Get-CursorPointInDip {
    $cursor = [System.Windows.Forms.Cursor]::Position
    $point = New-Object System.Windows.Point([double]$cursor.X, [double]$cursor.Y)
    $source = [System.Windows.PresentationSource]::FromVisual($window)
    if ($null -ne $source -and $null -ne $source.CompositionTarget) {
        return $source.CompositionTarget.TransformFromDevice.Transform($point)
    }
    return $point
}

function Get-LookGeometry {
    $cursor = Get-CursorPointInDip
    $originXRatio = [double](Get-ConfigValue $script:config.window $script:defaultConfig.window "cursorLookOriginX")
    $originYRatio = [double](Get-ConfigValue $script:config.window $script:defaultConfig.window "cursorLookOriginY")
    $spriteLeft = $window.Left + ($window.Width - $spriteDisplayWidth)
    $spriteTop = $window.Top + $usagePanelHeight
    $originX = $spriteLeft + ($spriteDisplayWidth * $originXRatio)
    $originY = $spriteTop + ($spriteDisplayHeight * $originYRatio)
    $dx = $cursor.X - $originX
    $dy = $cursor.Y - $originY

    return [pscustomobject]@{
        Dx = $dx
        Dy = $dy
        Distance = [Math]::Sqrt(($dx * $dx) + ($dy * $dy))
        Degrees = Get-LookAngleDegrees -Dx $dx -Dy $dy
    }
}

function Get-StableLookFrame {
    $geometry = Get-LookGeometry
    $now = [DateTime]::UtcNow
    $enterDistance = [double](Get-ConfigValue $script:config.window $script:defaultConfig.window "cursorLookEnterDistance") * $scale
    $exitDistance = [double](Get-ConfigValue $script:config.window $script:defaultConfig.window "cursorLookExitDistance") * $scale

    if (-not $script:lookActive) {
        if ($geometry.Distance -lt $enterDistance) { return -1 }
        $script:lookActive = $true
    } elseif ($geometry.Distance -lt $exitDistance) {
        $script:lookActive = $false
        $script:lookFrame = -1
        $script:lastLookStepAt = [DateTime]::MinValue
        return -1
    }

    $hysteresis = [double](Get-ConfigValue $script:config.window $script:defaultConfig.window "cursorLookHysteresisDegrees")
    $target = Get-LookFrameForAngle -Degrees $geometry.Degrees -CurrentFrame $script:lookFrame -HysteresisDegrees $hysteresis
    if ($script:lookFrame -lt 0) {
        $script:lookFrame = $target
        $script:lastLookStepAt = $now
        return $script:lookFrame
    }

    $stepMs = [int](Get-ConfigValue $script:config.window $script:defaultConfig.window "cursorLookStepMs")
    if ($target -ne $script:lookFrame -and ($now - $script:lastLookStepAt).TotalMilliseconds -ge $stepMs) {
        $script:lookFrame = Get-NextLookFrame -CurrentFrame $script:lookFrame -TargetFrame $target
        $script:lastLookStepAt = $now
    }
    return $script:lookFrame
}

function Get-FrameDuration([string]$Action, [int]$Frame) {
    $durations = $null
    if ($null -ne $script:config.frameDurationsMs) { $durations = $script:config.frameDurationsMs.$Action }
    if ($null -eq $durations -and $null -ne $script:defaultConfig.frameDurationsMs) {
        $durations = $script:defaultConfig.frameDurationsMs.$Action
    }
    if ($null -ne $durations -and $durations.Count -gt 0) {
        return [int]$durations[$Frame % $durations.Count]
    }

    $fallback = $null
    if ($null -ne $script:config.frameDurationMs) { $fallback = $script:config.frameDurationMs.$Action }
    if ($null -eq $fallback -and $null -ne $script:defaultConfig.frameDurationMs) {
        $fallback = $script:defaultConfig.frameDurationMs.$Action
    }
    return [int]$fallback
}

function Test-And-ReloadSprite {
    $now = [DateTime]::UtcNow
    $pollMs = [int](Get-ConfigValue $script:config.asset $script:defaultConfig.asset "reloadPollMs")
    if (($now - $script:lastSpritePollAt).TotalMilliseconds -lt $pollMs) { return }
    $script:lastSpritePollAt = $now

    foreach ($candidatePath in Get-SpriteCandidatePaths) {
        if (-not (Test-Path -LiteralPath $candidatePath)) { continue }
        $item = Get-Item -LiteralPath $candidatePath
        $stamp = "{0}:{1}" -f $item.Length, $item.LastWriteTimeUtc.Ticks
        if ($item.FullName -ne $script:spritePath -or $stamp -ne $script:spriteStamp) {
            Load-SpriteBitmap
        }
        return
    }
}

Add-Type -AssemblyName System.Windows.Forms

$window.Add_MouseLeftButtonDown({
    param($sender, $eventArgs)
    if ($eventArgs.ClickCount -ge 2) {
        Start-TemporaryAction "jumping"
        return
    }
    $leftBefore = $window.Left
    $topBefore = $window.Top
    try { $window.DragMove() } catch {}
    if ([Math]::Abs($window.Left - $leftBefore) -lt 3 -and [Math]::Abs($window.Top - $topBefore) -lt 3) {
        Start-TemporaryAction "waving"
    }
})

$menuStyle = [System.Windows.Markup.XamlReader]::Parse(@'
<Style xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
       xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
       TargetType="{x:Type ContextMenu}">
  <Setter Property="Background" Value="Transparent" />
  <Setter Property="BorderThickness" Value="0" />
  <Setter Property="Padding" Value="0" />
  <Setter Property="HasDropShadow" Value="False" />
  <Setter Property="Template">
    <Setter.Value>
      <ControlTemplate TargetType="{x:Type ContextMenu}">
        <Border Background="#FFFDFEFF"
                BorderBrush="#FF153B6B"
                BorderThickness="3"
                CornerRadius="17"
                Padding="7">
          <Border.Effect>
            <DropShadowEffect Color="#FF153B6B"
                              BlurRadius="12"
                              ShadowDepth="3"
                              Opacity="0.24" />
          </Border.Effect>
          <StackPanel IsItemsHost="True"
                      KeyboardNavigation.DirectionalNavigation="Cycle" />
        </Border>
      </ControlTemplate>
    </Setter.Value>
  </Setter>
</Style>
'@)

$menuItemStyle = [System.Windows.Markup.XamlReader]::Parse(@'
<Style xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
       xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
       TargetType="{x:Type MenuItem}">
  <Setter Property="Foreground" Value="#FF153B6B" />
  <Setter Property="Background" Value="Transparent" />
  <Setter Property="FontFamily" Value="Microsoft YaHei UI" />
  <Setter Property="FontSize" Value="14" />
  <Setter Property="FontWeight" Value="SemiBold" />
  <Setter Property="MinWidth" Value="244" />
  <Setter Property="Padding" Value="13,7" />
  <Setter Property="Margin" Value="1,1" />
  <Setter Property="Template">
    <Setter.Value>
      <ControlTemplate TargetType="{x:Type MenuItem}">
        <Border x:Name="ItemBorder"
                Background="{TemplateBinding Background}"
                CornerRadius="9"
                Padding="{TemplateBinding Padding}"
                Margin="{TemplateBinding Margin}"
                SnapsToDevicePixels="True">
          <ContentPresenter ContentSource="Header"
                            RecognizesAccessKey="True"
                            HorizontalAlignment="Left"
                            VerticalAlignment="Center" />
        </Border>
        <ControlTemplate.Triggers>
          <Trigger Property="IsHighlighted" Value="True">
            <Setter TargetName="ItemBorder" Property="Background" Value="#FFEAF4FF" />
            <Setter Property="Foreground" Value="#FF0051FC" />
          </Trigger>
          <Trigger Property="IsEnabled" Value="False">
            <Setter Property="Opacity" Value="0.46" />
          </Trigger>
        </ControlTemplate.Triggers>
      </ControlTemplate>
    </Setter.Value>
  </Setter>
</Style>
'@)

$menuSeparatorTemplate = [System.Windows.Markup.XamlReader]::Parse(@'
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                 xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
                 TargetType="{x:Type Separator}">
  <Border Height="1" Background="#FFD7E6F5" Margin="11,5" />
</ControlTemplate>
'@)

$menu = New-Object System.Windows.Controls.ContextMenu
$menu.Style = $menuStyle

$menuHeaderPanel = New-Object System.Windows.Controls.StackPanel
$menuHeaderPanel.Orientation = [System.Windows.Controls.Orientation]::Horizontal
$menuHeaderDot = New-Object System.Windows.Shapes.Ellipse
$menuHeaderDot.Width = 8
$menuHeaderDot.Height = 8
$menuHeaderDot.Fill = $doraRedBrush
$menuHeaderDot.Margin = New-Object System.Windows.Thickness(0, 0, 7, 0)
[void]$menuHeaderPanel.Children.Add($menuHeaderDot)
$menuHeaderText = New-Object System.Windows.Controls.TextBlock
$menuHeaderText.Text = (ConvertFrom-UnicodeCodePoints @(0x54C6, 0x5566, 0x0041, 0x68A6)) + " COMPANION"
$menuHeaderText.Foreground = $doraOutlineBrush
$menuHeaderText.FontFamily = New-Object System.Windows.Media.FontFamily -ArgumentList "Microsoft YaHei UI"
$menuHeaderText.FontSize = 12
$menuHeaderText.FontWeight = [System.Windows.FontWeights]::Bold
[void]$menuHeaderPanel.Children.Add($menuHeaderText)
$menuHeaderItem = New-Object System.Windows.Controls.MenuItem
$menuHeaderItem.Style = $menuItemStyle
$menuHeaderItem.Header = $menuHeaderPanel
$menuHeaderItem.Focusable = $false
$menuHeaderItem.IsHitTestVisible = $false
[void]$menu.Items.Add($menuHeaderItem)

$menuHeaderSeparator = New-Object System.Windows.Controls.Separator
$menuHeaderSeparator.Template = $menuSeparatorTemplate
[void]$menu.Items.Add($menuHeaderSeparator)

foreach ($itemSpec in @(
    @{ Header = (ConvertFrom-UnicodeCodePoints @(0x6325, 0x624B)); Action = "waving" },
    @{ Header = (ConvertFrom-UnicodeCodePoints @(0x7AF9, 0x873B, 0x8713)); Action = "jumping" },
    @{ Header = (ConvertFrom-UnicodeCodePoints @(0x4EFB, 0x610F, 0x95E8)); Action = "running" },
    @{ Header = (ConvertFrom-UnicodeCodePoints @(0x94F6, 0x6CB3, 0x6BC1, 0x706D, 0x70B8, 0x5F39)); Action = "failed" }
)) {
    $item = New-Object System.Windows.Controls.MenuItem
    $item.Style = $menuItemStyle
    $item.Header = $itemSpec.Header
    $action = $itemSpec.Action
    $item.Add_Click({ Start-TemporaryAction $action }.GetNewClosure())
    [void]$menu.Items.Add($item)
}

$actionSeparator = New-Object System.Windows.Controls.Separator
$actionSeparator.Template = $menuSeparatorTemplate
[void]$menu.Items.Add($actionSeparator)

$pauseItem = New-Object System.Windows.Controls.MenuItem
$pauseItem.Style = $menuItemStyle
$pauseItem.Header = ConvertFrom-UnicodeCodePoints @(0x6682, 0x505C, 0x52A8, 0x753B)
$pauseItem.Add_Click({
    $script:paused = -not $script:paused
    $pauseItem.Header = if ($script:paused) {
        ConvertFrom-UnicodeCodePoints @(0x7EE7, 0x7EED, 0x52A8, 0x753B)
    } else {
        ConvertFrom-UnicodeCodePoints @(0x6682, 0x505C, 0x52A8, 0x753B)
    }
})
[void]$menu.Items.Add($pauseItem)

$reloadItem = New-Object System.Windows.Controls.MenuItem
$reloadItem.Style = $menuItemStyle
$reloadItem.Header = ConvertFrom-UnicodeCodePoints @(0x91CD, 0x65B0, 0x52A0, 0x8F7D, 0x5BA0, 0x7269, 0x56FE, 0x96C6)
$reloadItem.Add_Click({
    Load-SpriteBitmap
    $script:frameIndex = 0
    $script:lastFrameAt = [DateTime]::UtcNow
    Set-Frame "idle" 0
})
[void]$menu.Items.Add($reloadItem)

if ($usageEnabled) {
    $refreshUsageItem = New-Object System.Windows.Controls.MenuItem
    $refreshUsageItem.Style = $menuItemStyle
    $refreshUsageItem.Header = (ConvertFrom-UnicodeCodePoints @(0x7ACB, 0x5373, 0x5237, 0x65B0)) + " Codex " + (ConvertFrom-UnicodeCodePoints @(0x989D, 0x5EA6))
    $refreshUsageItem.Add_Click({
        [DateTime]::UtcNow.ToString("o") | Set-Content -LiteralPath $usageRefreshRequestPath -Encoding ASCII
        $usageDetailText.Text = ConvertFrom-UnicodeCodePoints @(0x6B63, 0x5728, 0x5237, 0x65B0, 0x989D, 0x5EA6)
    })
    [void]$menu.Items.Add($refreshUsageItem)
}

$openConfigItem = New-Object System.Windows.Controls.MenuItem
$openConfigItem.Style = $menuItemStyle
$openConfigItem.Header = (ConvertFrom-UnicodeCodePoints @(0x6253, 0x5F00)) + " Companion " + (ConvertFrom-UnicodeCodePoints @(0x8BBE, 0x7F6E))
$openConfigItem.Add_Click({
    Start-Process -FilePath "notepad.exe" -ArgumentList ('"{0}"' -f $configPath) | Out-Null
})
[void]$menu.Items.Add($openConfigItem)

$restartItem = New-Object System.Windows.Controls.MenuItem
$restartItem.Style = $menuItemStyle
$restartItem.Header = (ConvertFrom-UnicodeCodePoints @(0x91CD, 0x65B0, 0x542F, 0x52A8)) + " Companion"
$restartItem.Add_Click({
    $launcherPath = Join-Path $PluginRoot "scripts\start-companion.ps1"
    Start-Process -FilePath "powershell.exe" -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", ('"{0}"' -f $launcherPath),
        "-Restart"
    ) -WindowStyle Hidden | Out-Null
})
[void]$menu.Items.Add($restartItem)

$exitItem = New-Object System.Windows.Controls.MenuItem
$exitItem.Style = $menuItemStyle
$exitItem.Header = (ConvertFrom-UnicodeCodePoints @(0x9000, 0x51FA)) + " Companion"
$exitItem.Add_Click({ $window.Close() })
[void]$menu.Items.Add($exitItem)
$image.ContextMenu = $menu
$root.ContextMenu = $menu

$stateTimer = New-Object System.Windows.Threading.DispatcherTimer
$stateTimer.Interval = [TimeSpan]::FromMilliseconds(180)
$stateTimer.Add_Tick({
    Test-And-ReloadSprite
    Update-UsageDisplay
    $now = [DateTime]::UtcNow
    if ($usageEnabled -and ($now - $script:lastUsageMonitorCheck).TotalSeconds -ge 8) {
        $script:lastUsageMonitorCheck = $now
        Start-UsageMonitor
    }
    if (-not (Test-Path $statePath)) { return }
    try {
        $state = Get-Content -Raw -Encoding UTF8 -LiteralPath $statePath | ConvertFrom-Json
        if ([long]$state.sequence -gt $script:lastSequence) {
            $script:lastSequence = [long]$state.sequence
            $script:baseAction = if ($rowMap.ContainsKey([string]$state.action)) { [string]$state.action } else { "idle" }
            $script:stateExpiresAt = ([DateTime]$state.timestampUtc).ToUniversalTime().AddMilliseconds([int]$state.holdMs)
            $script:frameIndex = 0
            $script:lastFrameAt = [DateTime]::UtcNow
        }
    } catch {
        # A concurrent hook may be replacing the state file; retry next tick.
    }
})

$animationTimer = New-Object System.Windows.Threading.DispatcherTimer
$animationTimer.Interval = [TimeSpan]::FromMilliseconds(50)
$animationTimer.Add_Tick({
    $now = [DateTime]::UtcNow
    if ($script:temporaryAction -and $now -ge $script:temporaryUntil) {
        $script:temporaryAction = $null
        $script:frameIndex = 0
    }
    if (-not $script:temporaryAction -and $now -ge $script:stateExpiresAt) {
        $script:baseAction = "idle"
    }

    $action = if ($script:temporaryAction) { $script:temporaryAction } else { $script:baseAction }
    if ($action -eq "idle") {
        $lookFrame = Get-StableLookFrame
        if ($lookFrame -ge 0) {
            Set-Frame "look" $lookFrame
            return
        }
    } else {
        $script:lookActive = $false
        $script:lookFrame = -1
        $script:lastLookStepAt = [DateTime]::MinValue
    }

    if (-not $script:paused) {
        $duration = Get-FrameDuration $action $script:frameIndex
        if (($now - $script:lastFrameAt).TotalMilliseconds -ge $duration) {
            $script:frameIndex = ($script:frameIndex + 1) % [int]$frameCounts[$action]
            $script:lastFrameAt = $now
        }
    }
    Set-Frame $action $script:frameIndex
})

$window.Add_Closed({
    $stateTimer.Stop()
    $animationTimer.Stop()
    Remove-Item -LiteralPath $pidPath -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $usageRefreshRequestPath -ErrorAction SilentlyContinue
})

New-Item -ItemType Directory -Force -Path $DataRoot | Out-Null
if (-not [string]::IsNullOrWhiteSpace($PreviewPath)) {
    Update-UsageDisplay
    Set-Frame "idle" 0
    $previewSize = New-Object System.Windows.Size($window.Width, $window.Height)
    $root.Measure($previewSize)
    $root.Arrange((New-Object System.Windows.Rect(0, 0, $window.Width, $window.Height)))
    $root.UpdateLayout()

    $previewBitmap = New-Object System.Windows.Media.Imaging.RenderTargetBitmap(
        [int][Math]::Ceiling($window.Width),
        [int][Math]::Ceiling($window.Height),
        96,
        96,
        [System.Windows.Media.PixelFormats]::Pbgra32
    )
    $previewBitmap.Render($root)
    $previewEncoder = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
    [void]$previewEncoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($previewBitmap))
    $previewResolved = [IO.Path]::GetFullPath($PreviewPath)
    $previewDirectory = [IO.Path]::GetDirectoryName($previewResolved)
    if (-not [string]::IsNullOrWhiteSpace($previewDirectory)) {
        New-Item -ItemType Directory -Force -Path $previewDirectory | Out-Null
    }
    $previewStream = [IO.File]::Open($previewResolved, [IO.FileMode]::Create)
    try {
        $previewEncoder.Save($previewStream)
    } finally {
        $previewStream.Dispose()
    }
    $previewResolved
    return
}

$PID | Set-Content -LiteralPath $pidPath -Encoding ASCII
Start-UsageMonitor
Update-UsageDisplay
Set-Frame "idle" 0
$stateTimer.Start()
$animationTimer.Start()
[void]$window.ShowDialog()
