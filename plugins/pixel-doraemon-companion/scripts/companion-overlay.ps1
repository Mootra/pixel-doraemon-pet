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

if ($null -eq ("PixelDoraemon.FocusNative" -as [type])) {
    Add-Type @'
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;

namespace PixelDoraemon {
    public static class FocusNative {
        private const int WH_KEYBOARD_LL = 13;
        private const int WH_MOUSE_LL = 14;
        private const int WM_KEYDOWN = 0x0100;
        private const int WM_SYSKEYDOWN = 0x0104;
        private const int WM_LBUTTONDOWN = 0x0201;
        private const int WM_RBUTTONDOWN = 0x0204;
        private const int WM_MBUTTONDOWN = 0x0207;
        private const int WM_XBUTTONDOWN = 0x020B;

        [DllImport("user32.dll", SetLastError = true)]
        private static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc callback, IntPtr module, uint threadId);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool UnhookWindowsHookEx(IntPtr hook);

        [DllImport("user32.dll")]
        private static extern IntPtr CallNextHookEx(IntPtr hook, int code, IntPtr wParam, IntPtr lParam);

        [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        private static extern IntPtr GetModuleHandle(string moduleName);

        private delegate IntPtr LowLevelKeyboardProc(int code, IntPtr wParam, IntPtr lParam);
        private static readonly object KeyboardLock = new object();
        private static IntPtr keyboardHook = IntPtr.Zero;
        private static IntPtr mouseHook = IntPtr.Zero;
        private static LowLevelKeyboardProc keyboardCallback;
        private static LowLevelKeyboardProc mouseCallback;
        private static long keyboardPresses;
        private static long lastActivityUtcTicks;

        public static uint GetActivityIdleMilliseconds() {
            lock (KeyboardLock) {
                if (lastActivityUtcTicks <= 0) return UInt32.MaxValue;
                long elapsed = (DateTime.UtcNow.Ticks - lastActivityUtcTicks) / TimeSpan.TicksPerMillisecond;
                if (elapsed <= 0) return 0;
                return elapsed >= UInt32.MaxValue ? UInt32.MaxValue : (uint)elapsed;
            }
        }

        public static void StartInputCounter() {
            lock (KeyboardLock) {
                if (keyboardHook != IntPtr.Zero && mouseHook != IntPtr.Zero) return;
                keyboardPresses = 0;
                lastActivityUtcTicks = 0;
                keyboardCallback = KeyboardHookCallback;
                mouseCallback = MouseHookCallback;
                using (Process current = Process.GetCurrentProcess()) {
                    keyboardHook = SetWindowsHookEx(WH_KEYBOARD_LL, keyboardCallback, GetModuleHandle(current.MainModule.ModuleName), 0);
                    mouseHook = SetWindowsHookEx(WH_MOUSE_LL, mouseCallback, GetModuleHandle(current.MainModule.ModuleName), 0);
                }
                if (keyboardHook == IntPtr.Zero || mouseHook == IntPtr.Zero) {
                    if (keyboardHook != IntPtr.Zero) UnhookWindowsHookEx(keyboardHook);
                    if (mouseHook != IntPtr.Zero) UnhookWindowsHookEx(mouseHook);
                    keyboardHook = IntPtr.Zero;
                    mouseHook = IntPtr.Zero;
                    throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
                }
            }
        }

        public static long ConsumeKeyboardPresses() {
            lock (KeyboardLock) {
                long count = keyboardPresses;
                keyboardPresses = 0;
                return count;
            }
        }

        public static void StopInputCounter() {
            lock (KeyboardLock) {
                if (keyboardHook != IntPtr.Zero) UnhookWindowsHookEx(keyboardHook);
                if (mouseHook != IntPtr.Zero) UnhookWindowsHookEx(mouseHook);
                keyboardHook = IntPtr.Zero;
                mouseHook = IntPtr.Zero;
                keyboardCallback = null;
                mouseCallback = null;
            }
        }

        private static void NoteActivity() {
            lastActivityUtcTicks = DateTime.UtcNow.Ticks;
        }

        private static IntPtr KeyboardHookCallback(int code, IntPtr wParam, IntPtr lParam) {
            if (code >= 0 && ((int)wParam == WM_KEYDOWN || (int)wParam == WM_SYSKEYDOWN)) {
                lock (KeyboardLock) {
                    keyboardPresses++;
                    NoteActivity();
                }
            }
            return CallNextHookEx(keyboardHook, code, wParam, lParam);
        }

        private static IntPtr MouseHookCallback(int code, IntPtr wParam, IntPtr lParam) {
            if (code >= 0 && ((int)wParam == WM_LBUTTONDOWN || (int)wParam == WM_RBUTTONDOWN || (int)wParam == WM_MBUTTONDOWN || (int)wParam == WM_XBUTTONDOWN)) {
                lock (KeyboardLock) {
                    NoteActivity();
                }
            }
            return CallNextHookEx(mouseHook, code, wParam, lParam);
        }
    }
}
'@
}

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

function Get-ClampedConfigDouble($UserSection, $DefaultSection, [string]$Name, [double]$Minimum, [double]$Maximum) {
    $value = [double](Get-ConfigValue $UserSection $DefaultSection $Name)
    return [Math]::Min($Maximum, [Math]::Max($Minimum, $value))
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
$usageDisplayIntervalMs = [Math]::Max(1000, [int](Get-ConfigValue $script:config.usage $script:defaultConfig.usage "displayIntervalMs"))
$usageDisplayDurationMs = [Math]::Max(1000, [int](Get-ConfigValue $script:config.usage $script:defaultConfig.usage "displayDurationMs"))
$bubblePageDurationMs = [Math]::Max(1000, [int](Get-ConfigValue $script:config.usage $script:defaultConfig.usage "bubblePageDurationMs"))
$usageBubbleOpacity = Get-ClampedConfigDouble $script:config.usage $script:defaultConfig.usage "bubbleBackgroundOpacity" 0.15 1.0
$focusEnabled = [bool](Get-ConfigValue $script:config.focus $script:defaultConfig.focus "enabled")
$focusIdleThresholdSeconds = [Math]::Max(15, [int](Get-ConfigValue $script:config.focus $script:defaultConfig.focus "idleThresholdSeconds"))
$focusPomodoroSeconds = [Math]::Max(300, [int](Get-ConfigValue $script:config.focus $script:defaultConfig.focus "pomodoroMinutes") * 60)
$focusStatePath = Join-Path $DataRoot "focus-state.json"
$persistentDataRoot = Join-Path ([Environment]::GetFolderPath("LocalApplicationData")) "PixelDoraemonCompanion"
$progressStatePath = Join-Path $persistentDataRoot "progress-state.json"
$celebrationDurationMs = [Math]::Max(3000, [int](Get-ConfigValue $script:config.progress $script:defaultConfig.progress "celebrationDurationMs"))
$maximumProgressHistory = [Math]::Max(10, [int](Get-ConfigValue $script:config.progress $script:defaultConfig.progress "maximumHistory"))
$focusMilestones = @(Get-ConfigValue $script:config.progress $script:defaultConfig.progress "focusMilestones")
$keyboardMilestones = @(Get-ConfigValue $script:config.progress $script:defaultConfig.progress "keyboardMilestones")
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
        focusEnabled = $focusEnabled
        focusActivation = "keyboard-or-mouse-click"
        focusStatePath = $focusStatePath
        progressStatePath = $progressStatePath
    } | ConvertTo-Json -Depth 4
    return
}

$script:singleInstanceMutex = New-Object System.Threading.Mutex($false, "Local\PixelDoraemonCompanion.Overlay")
$script:ownsSingleInstanceMutex = $false
try {
    $script:ownsSingleInstanceMutex = $script:singleInstanceMutex.WaitOne(0, $false)
} catch [System.Threading.AbandonedMutexException] {
    $script:ownsSingleInstanceMutex = $true
}
if (-not $script:ownsSingleInstanceMutex) {
    $script:singleInstanceMutex.Dispose()
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
$usageBubbleFillBrush = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb([byte][Math]::Round(255 * $usageBubbleOpacity), 255, 255, 255))
$usageBubbleFillBrush.Freeze()

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
$tailLarge.Fill = $usageBubbleFillBrush
$tailLarge.Stroke = $doraOutlineBrush
$tailLarge.StrokeThickness = 3
[System.Windows.Controls.Canvas]::SetLeft($tailLarge, $window.Width - ($spriteDisplayWidth * 0.58))
[System.Windows.Controls.Canvas]::SetTop($tailLarge, $usageBubbleHeight + 5)
[void]$usageCanvas.Children.Add($tailLarge)

$tailSmall = New-Object System.Windows.Shapes.Ellipse
$tailSmall.Width = 13
$tailSmall.Height = 9
$tailSmall.Fill = $usageBubbleFillBrush
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
$usageBubble.Background = $usageBubbleFillBrush
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

$bubblePageIndicatorText = New-Object System.Windows.Controls.TextBlock
$bubblePageIndicatorText.Text = "1 / 3"
$bubblePageIndicatorText.Foreground = $usageMutedBrush
$bubblePageIndicatorText.FontFamily = New-Object System.Windows.Media.FontFamily -ArgumentList "Segoe UI"
$bubblePageIndicatorText.FontSize = 9.5
$bubblePageIndicatorText.FontWeight = [System.Windows.FontWeights]::SemiBold
$bubblePageIndicatorText.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
$bubblePageIndicatorText.Margin = New-Object System.Windows.Thickness(7, 0, 0, 0)
[void]$usageHeader.Children.Add($bubblePageIndicatorText)
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
$script:usageBubbleVisible = $usageEnabled
$script:usageBubbleUntil = if ($usageEnabled) {
    [DateTime]::UtcNow.AddMilliseconds($usageDisplayDurationMs)
} else {
    [DateTime]::MinValue
}
$script:nextUsageBubbleAt = if ($usageEnabled) {
    [DateTime]::UtcNow.AddMilliseconds($usageDisplayIntervalMs)
} else {
    [DateTime]::MaxValue
}
$script:focusDate = [DateTime]::Now.ToString("yyyy-MM-dd")
$script:focusActiveSeconds = 0
$script:focusPomodoroElapsedSeconds = 0
$script:focusCompletedPomodoros = 0
$script:keyboardPresses = 0
$script:keyboardCounterAvailable = $focusEnabled
$script:focusIsActive = $false
$script:focusIdleSeconds = 0
$script:lastFocusSampleAt = [DateTime]::UtcNow
$script:lastFocusPersistedAt = [DateTime]::MinValue
$script:lastProgressPersistedAt = [DateTime]::MinValue
$script:totalFocusSeconds = 0
$script:totalKeyboardPresses = 0
$script:totalCompletedFocusRounds = 0
$script:unlockedMilestones = [ordered]@{}
$script:progressHistory = @()
$script:activeCelebration = $null
$script:celebrationQueue = @()
$script:celebrationUntil = [DateTime]::MinValue
$script:usageMinimumRemaining = $null
$script:usageDetailLabel = ConvertFrom-UnicodeCodePoints @(0x6B63, 0x5728, 0x8BFB, 0x53D6)
$script:usageTooltip = ""
$script:bubblePage = 0
$script:lastBubblePageChangedAt = [DateTime]::UtcNow

function Set-UsageBubbleVisible([bool]$Visible) {
    if (-not $usageEnabled -or $script:usageBubbleVisible -eq $Visible) { return }

    $script:usageBubbleVisible = $Visible
    $usageCanvas.Visibility = if ($Visible) {
        [System.Windows.Visibility]::Visible
    } else {
        [System.Windows.Visibility]::Collapsed
    }
    $usageRow.Height = New-Object System.Windows.GridLength($(if ($Visible) { $usagePanelHeight } else { 0 }))
    $window.Height = $spriteDisplayHeight + $(if ($Visible) { $usagePanelHeight } else { 0 })
    $window.Top = $workArea.Bottom - $window.Height - 40
}

function Update-UsageBubbleSchedule {
    if (-not $usageEnabled) { return }

    $now = [DateTime]::UtcNow
    if ($script:usageBubbleVisible -and $now -ge $script:usageBubbleUntil) {
        Set-UsageBubbleVisible $false
        $script:nextUsageBubbleAt = $now.AddMilliseconds($usageDisplayIntervalMs)
    } elseif (-not $script:usageBubbleVisible -and $now -ge $script:nextUsageBubbleAt) {
        Set-UsageBubbleVisible $true
        $script:usageBubbleUntil = $now.AddMilliseconds($usageDisplayDurationMs)
        Set-BubblePage 0
    }
}

function Show-UsageBubbleFromInteraction {
    if (-not $usageEnabled) { return }

    $wasVisible = $script:usageBubbleVisible
    Update-UsageDisplay
    $script:usageBubbleUntil = [DateTime]::UtcNow.AddMilliseconds($usageDisplayDurationMs)
    Set-UsageBubbleVisible $true
    if (-not $wasVisible) { Set-BubblePage 0 }
}

function Format-FocusDuration([int]$Seconds) {
    return ("{0:00}:{1:00}" -f [Math]::Floor($Seconds / 60), ($Seconds % 60))
}

function Get-AppStatLabel($Stats) {
    $items = @($Stats.GetEnumerator() | Sort-Object Key | ForEach-Object { "{0} {1}" -f $_.Key, $_.Value })
    if ($items.Count -eq 0) { return "--" }
    return ($items -join "  ")
}

function Get-AppDurationLabel($Stats) {
    $items = @($Stats.GetEnumerator() | Sort-Object Key | ForEach-Object { "{0} {1}" -f $_.Key, (Format-FocusDuration ([int]$_.Value)) })
    if ($items.Count -eq 0) { return "--" }
    return ($items -join "  ")
}

function Get-ProgressHistoryLabel {
    $items = @($script:progressHistory | Select-Object -First 5 | ForEach-Object {
        $occurredAt = [DateTime]::MinValue
        [void][DateTime]::TryParse([string]$_.occurredAtUtc, [ref]$occurredAt)
        "{0}  {1:MM-dd HH:mm}" -f $_.title, $occurredAt.ToLocalTime()
    })
    if ($items.Count -eq 0) { return "--" }
    return ($items -join "`n")
}

function Write-ProgressState {
    $stateDirectory = Split-Path -Parent $progressStatePath
    New-Item -ItemType Directory -Force -Path $stateDirectory | Out-Null
    $state = [ordered]@{
        schemaVersion = 1
        totalFocusSeconds = $script:totalFocusSeconds
        totalKeyboardPresses = $script:totalKeyboardPresses
        completedFocusRounds = $script:totalCompletedFocusRounds
        unlockedMilestones = $script:unlockedMilestones
        history = @($script:progressHistory)
        updatedAtUtc = [DateTime]::UtcNow.ToString("o")
    }
    $temporaryPath = "{0}.{1}.tmp" -f $progressStatePath, $PID
    $state | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $temporaryPath -Encoding UTF8
    Move-Item -LiteralPath $temporaryPath -Destination $progressStatePath -Force
    $script:lastProgressPersistedAt = [DateTime]::UtcNow
}

function Initialize-ProgressState {
    if (Test-Path -LiteralPath $progressStatePath) {
        try {
            $stored = Get-Content -Raw -Encoding UTF8 -LiteralPath $progressStatePath | ConvertFrom-Json
            $script:totalFocusSeconds = [Math]::Max(0, [int]$stored.totalFocusSeconds)
            $script:totalKeyboardPresses = [Math]::Max(0, [long]$stored.totalKeyboardPresses)
            $script:totalCompletedFocusRounds = [Math]::Max(0, [int]$stored.completedFocusRounds)
            if ($null -ne $stored.unlockedMilestones) {
                foreach ($property in $stored.unlockedMilestones.PSObject.Properties) {
                    $script:unlockedMilestones[$property.Name] = [bool]$property.Value
                }
            }
            if ($null -ne $stored.history) {
                $script:progressHistory = @($stored.history | Select-Object -First $maximumProgressHistory)
            }
        } catch {
            # Preserve a usable companion when an interrupted write left invalid progress data.
        }
    } else {
        # Carry today's existing counters into the first durable lifetime record.
        $script:totalFocusSeconds = $script:focusActiveSeconds
        $script:totalKeyboardPresses = $script:keyboardPresses
        $script:totalCompletedFocusRounds = $script:focusCompletedPomodoros
        Write-ProgressState
    }
}

function Show-Celebration([string]$Kind, [string]$Title, [string]$Value, [string]$Message) {
    $celebration = [pscustomobject]@{
        kind = $Kind
        title = $Title
        value = $Value
        message = $Message
    }
    if ($null -ne $script:activeCelebration -and [DateTime]::UtcNow -lt $script:celebrationUntil) {
        $script:celebrationQueue = @($script:celebrationQueue) + @($celebration)
        return
    }
    $script:activeCelebration = $celebration
    $script:celebrationUntil = [DateTime]::UtcNow.AddMilliseconds($celebrationDurationMs)
    $script:usageBubbleUntil = $script:celebrationUntil
    Set-UsageBubbleVisible $true
    Update-BubblePage
}

function Add-ProgressEvent([string]$Id, [string]$Kind, [string]$Title, [string]$Value, [string]$Message, [bool]$AlwaysShow = $false) {
    if (-not $AlwaysShow -and $script:unlockedMilestones.Contains($Id)) { return }
    if (-not $AlwaysShow) { $script:unlockedMilestones[$Id] = $true }
    $event = [pscustomobject]@{
        id = $Id
        kind = $Kind
        title = $Title
        value = $Value
        message = $Message
        occurredAtUtc = [DateTime]::UtcNow.ToString("o")
    }
    $script:progressHistory = @($event) + @($script:progressHistory | Select-Object -First ($maximumProgressHistory - 1))
    Write-ProgressState
    Show-Celebration $Kind $Title $Value $Message
}

function Check-ProgressMilestones {
    foreach ($milestone in $focusMilestones) {
        $threshold = [int]$milestone.thresholdSeconds
        if ($threshold -gt 0 -and $script:totalFocusSeconds -ge $threshold) {
            Add-ProgressEvent ("focus-{0}" -f $threshold) "focus-milestone" ([string]$milestone.title) (Format-FocusDuration $script:totalFocusSeconds) ([string]$milestone.message)
        }
    }
    foreach ($milestone in $keyboardMilestones) {
        $threshold = [long]$milestone.thresholdCount
        if ($threshold -eq 10000 -and $script:totalKeyboardPresses -ge $threshold) {
            # The 10k key milestone repeats at every later multiple of 10k.
            $latestMilestone = [long]([Math]::Floor($script:totalKeyboardPresses / $threshold) * $threshold)
            $pendingMilestones = @()
            while ($latestMilestone -ge $threshold -and -not $script:unlockedMilestones.Contains("keyboard-$latestMilestone")) {
                $pendingMilestones = @($latestMilestone) + @($pendingMilestones)
                $latestMilestone -= $threshold
            }
            foreach ($milestoneValue in $pendingMilestones) {
                Add-ProgressEvent ("keyboard-{0}" -f $milestoneValue) "keyboard-repeat" ([string]$milestone.title) ("{0:N0}" -f $milestoneValue) ([string]$milestone.message)
            }
        } elseif ($threshold -gt 0 -and $script:totalKeyboardPresses -ge $threshold) {
            Add-ProgressEvent ("keyboard-{0}" -f $threshold) "keyboard-milestone" ([string]$milestone.title) ("{0:N0}" -f $script:totalKeyboardPresses) ([string]$milestone.message)
        }
    }
}

function Show-FocusDashboard {
    $dashboard = New-Object System.Windows.Window
    $dashboard.Title = (ConvertFrom-UnicodeCodePoints @(0x54C6, 0x5566, 0x0041, 0x68A6)) + (ConvertFrom-UnicodeCodePoints @(0x4E13, 0x6CE8, 0x540E, 0x53F0))
    $dashboard.Width = 430
    $dashboard.Height = 500
    $dashboard.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterScreen
    $dashboard.ResizeMode = [System.Windows.ResizeMode]::NoResize
    $dashboard.Background = $brushConverter.ConvertFromString("#FFF8FBFF")

    $panel = New-Object System.Windows.Controls.StackPanel
    $panel.Margin = New-Object System.Windows.Thickness(24)
    $title = New-Object System.Windows.Controls.TextBlock
    $title.Text = (ConvertFrom-UnicodeCodePoints @(0x4ECA, 0x65E5, 0x4E13, 0x6CE8, 0x6570, 0x636E))
    $title.Foreground = $doraOutlineBrush
    $title.FontFamily = New-Object System.Windows.Media.FontFamily -ArgumentList "Microsoft YaHei UI"
    $title.FontSize = 22
    $title.FontWeight = [System.Windows.FontWeights]::Bold
    $title.Margin = New-Object System.Windows.Thickness(0, 0, 0, 14)
    [void]$panel.Children.Add($title)

    foreach ($line in @(
        ((ConvertFrom-UnicodeCodePoints @(0x6709, 0x6548, 0x4E13, 0x6CE8)) + ": " + (Format-FocusDuration $script:focusActiveSeconds)),
        ((ConvertFrom-UnicodeCodePoints @(0x5F53, 0x524D, 0x8F6E)) + ": " + (Format-FocusDuration $script:focusPomodoroElapsedSeconds) + " / " + (Format-FocusDuration $focusPomodoroSeconds)),
        ((ConvertFrom-UnicodeCodePoints @(0x5B8C, 0x6210, 0x8F6E, 0x6570)) + ": " + $script:focusCompletedPomodoros),
        ((ConvertFrom-UnicodeCodePoints @(0x8BA1, 0x65F6, 0x89E6, 0x53D1)) + ": " + (ConvertFrom-UnicodeCodePoints @(0x952E, 0x76D8, 0x6309, 0x4E0B, 0x6216, 0x9F20, 0x6807, 0x70B9, 0x51FB))),
        ((ConvertFrom-UnicodeCodePoints @(0x952E, 0x76D8, 0x6572, 0x51FB)) + ": " + ("{0:N0}" -f $script:keyboardPresses)),
        ((ConvertFrom-UnicodeCodePoints @(0x7EDF, 0x8BA1, 0x8303, 0x56F4)) + ": " + (ConvertFrom-UnicodeCodePoints @(0x6240, 0x6709, 0x5E94, 0x7528, 0xFF08, 0x4EC5, 0x4FDD, 0x5B58, 0x6B21, 0x6570, 0xFF09))),
        ((ConvertFrom-UnicodeCodePoints @(0x7D2F, 0x8BA1, 0x4E13, 0x6CE8)) + ": " + (Format-FocusDuration $script:totalFocusSeconds) + "  /  " + (ConvertFrom-UnicodeCodePoints @(0x7D2F, 0x8BA1, 0x8F6E, 0x6B21)) + ": " + $script:totalCompletedFocusRounds),
        ((ConvertFrom-UnicodeCodePoints @(0x7D2F, 0x8BA1, 0x6572, 0x51FB)) + ": " + ("{0:N0}" -f $script:totalKeyboardPresses)),
        ((ConvertFrom-UnicodeCodePoints @(0x8BA1, 0x65F6, 0x89C4, 0x5219, 0xFF1A, 0x952E, 0x76D8, 0x6309, 0x4E0B, 0x6216, 0x9F20, 0x6807, 0x70B9, 0x51FB, 0x540E, 0x8BA1, 0x65F6, 0xFF0C, 0x8D85, 0x8FC7)) + " {0}s " + (ConvertFrom-UnicodeCodePoints @(0x672A, 0x64CD, 0x4F5C, 0x5373, 0x6682, 0x505C)) -f $focusIdleThresholdSeconds)
    )) {
        $text = New-Object System.Windows.Controls.TextBlock
        $text.Text = $line
        $text.Foreground = $doraOutlineBrush
        $text.FontFamily = New-Object System.Windows.Media.FontFamily -ArgumentList "Microsoft YaHei UI"
        $text.FontSize = 13
        $text.Margin = New-Object System.Windows.Thickness(0, 3, 0, 3)
        $text.TextWrapping = [System.Windows.TextWrapping]::Wrap
        [void]$panel.Children.Add($text)
    }

    $historyTitle = New-Object System.Windows.Controls.TextBlock
    $historyTitle.Text = ConvertFrom-UnicodeCodePoints @(0x6700, 0x8FD1, 0x5386, 0x7A0B)
    $historyTitle.Foreground = $doraOutlineBrush
    $historyTitle.FontFamily = New-Object System.Windows.Media.FontFamily -ArgumentList "Microsoft YaHei UI"
    $historyTitle.FontWeight = [System.Windows.FontWeights]::Bold
    $historyTitle.Margin = New-Object System.Windows.Thickness(0, 10, 0, 2)
    [void]$panel.Children.Add($historyTitle)
    $history = New-Object System.Windows.Controls.TextBlock
    $history.Text = Get-ProgressHistoryLabel
    $history.Foreground = $usageMutedBrush
    $history.FontFamily = New-Object System.Windows.Media.FontFamily -ArgumentList "Microsoft YaHei UI"
    $history.FontSize = 11
    $history.TextWrapping = [System.Windows.TextWrapping]::Wrap
    [void]$panel.Children.Add($history)

    $privacy = New-Object System.Windows.Controls.TextBlock
    $privacy.Text = (ConvertFrom-UnicodeCodePoints @(0x53EA, 0x8BB0, 0x5F55, 0x8FDB, 0x7A0B, 0x540D, 0x79F0, 0x4E0E, 0x6B21, 0x6570, 0xFF0C, 0x4E0D, 0x8BFB, 0x53D6, 0x8F93, 0x5165, 0x5185, 0x5BB9))
    $privacy.Foreground = $usageMutedBrush
    $privacy.FontFamily = New-Object System.Windows.Media.FontFamily -ArgumentList "Microsoft YaHei UI"
    $privacy.FontSize = 11
    $privacy.Margin = New-Object System.Windows.Thickness(0, 14, 0, 0)
    $privacy.TextWrapping = [System.Windows.TextWrapping]::Wrap
    [void]$panel.Children.Add($privacy)

    $dashboard.Content = $panel
    [void]$dashboard.ShowDialog()
}

function Update-BubblePage {
    if (-not $usageEnabled) { return }

    if ($null -ne $script:activeCelebration) {
        if ([DateTime]::UtcNow -lt $script:celebrationUntil) {
            $bubblePageIndicatorText.Text = "*"
            $usageHeaderDot.Fill = $doraYellowBrush
            $usageTitleText.Text = (ConvertFrom-UnicodeCodePoints @(0x5E86, 0x795D)) + " * " + $script:activeCelebration.title
            $usageValueText.Text = $script:activeCelebration.value
            $usageValueText.Foreground = $doraRedBrush
            $usageDetailText.Text = $script:activeCelebration.message
            return
        }
        if ($script:celebrationQueue.Count -gt 0) {
            $script:activeCelebration = $script:celebrationQueue[0]
            $script:celebrationQueue = @($script:celebrationQueue | Select-Object -Skip 1)
            $script:celebrationUntil = [DateTime]::UtcNow.AddMilliseconds($celebrationDurationMs)
            $script:usageBubbleUntil = $script:celebrationUntil
            Update-BubblePage
            return
        }
        $script:activeCelebration = $null
    }

    $bubblePageIndicatorText.Text = "{0} / 3" -f ($script:bubblePage + 1)
    switch ($script:bubblePage) {
        0 {
            $usageHeaderDot.Fill = $doraRedBrush
            $usageTitleText.Text = "CODEX " + (ConvertFrom-UnicodeCodePoints @(0x5269, 0x4F59, 0x989D, 0x5EA6))
            if ($null -eq $script:usageMinimumRemaining) {
                $usageValueText.Text = "--"
                $usageValueText.Foreground = $usageMutedBrush
            } else {
                $usageValueText.Text = "{0}%" -f $script:usageMinimumRemaining
                $usageValueText.Foreground = if ($script:usageMinimumRemaining -le 20) { $doraRedBrush } elseif ($script:usageMinimumRemaining -le 50) { $brushConverter.ConvertFromString("#FFC88600") } else { $doraBlueBrush }
            }
            $usageDetailText.Text = $script:usageDetailLabel
        }
        1 {
            $usageHeaderDot.Fill = if ($script:focusIsActive) { $doraBlueBrush } else { $usageMutedBrush }
            $usageTitleText.Text = ConvertFrom-UnicodeCodePoints @(0x4E13, 0x6CE8, 0x65F6, 0x95F4)
            $usageValueText.Text = Format-FocusDuration $script:focusPomodoroElapsedSeconds
            $usageValueText.Foreground = if ($script:focusIsActive) { $doraBlueBrush } else { $usageMutedBrush }
            $stateLabel = if ($script:focusIsActive) { ConvertFrom-UnicodeCodePoints @(0x6B63, 0x5728, 0x4E13, 0x6CE8) } else { ConvertFrom-UnicodeCodePoints @(0x6682, 0x505C, 0x8BA1, 0x65F6) }
            $usageDetailText.Text = "$stateLabel  " + (ConvertFrom-UnicodeCodePoints @(0x4ECA, 0x65E5)) + " " + (Format-FocusDuration $script:focusActiveSeconds) + "  /  " + (ConvertFrom-UnicodeCodePoints @(0x603B, 0x8BA1)) + " " + (Format-FocusDuration $script:totalFocusSeconds)
        }
        default {
            $usageHeaderDot.Fill = $doraYellowBrush
            $usageTitleText.Text = ConvertFrom-UnicodeCodePoints @(0x952E, 0x76D8, 0x6572, 0x51FB)
            $usageValueText.Text = "{0:N0}" -f $script:keyboardPresses
            $usageValueText.Foreground = $doraOutlineBrush
            $usageDetailText.Text = (ConvertFrom-UnicodeCodePoints @(0x4ECA, 0x65E5)) + " " + ("{0:N0}" -f $script:keyboardPresses) + "  /  " + (ConvertFrom-UnicodeCodePoints @(0x603B, 0x8BA1)) + " " + ("{0:N0}" -f $script:totalKeyboardPresses)
        }
    }
}

function Set-BubblePage([int]$Page) {
    $script:bubblePage = (($Page % 3) + 3) % 3
    $script:lastBubblePageChangedAt = [DateTime]::UtcNow
    Update-BubblePage
}

function Show-NextBubblePage {
    Set-BubblePage ($script:bubblePage + 1)
}

function Update-BubblePageRotation {
    if (-not $usageEnabled -or -not $script:usageBubbleVisible) { return }
    if ($null -ne $script:activeCelebration -and [DateTime]::UtcNow -lt $script:celebrationUntil) { return }
    if (([DateTime]::UtcNow - $script:lastBubblePageChangedAt).TotalMilliseconds -ge $bubblePageDurationMs) {
        Show-NextBubblePage
    }
}

function Update-FocusDisplay {
    if (-not $focusEnabled) { return }

    $focusStatus = if ($script:focusIsActive) { ConvertFrom-UnicodeCodePoints @(0x8BA1, 0x65F6, 0x4E2D) } else { ConvertFrom-UnicodeCodePoints @(0x6682, 0x505C) }
    $focusMarker = ConvertFrom-UnicodeCodePoints @(0x4E13, 0x6CE8, 0x8BA1, 0x65F6)
    $focusLine = "{0}: {1}; {2}: {3}; {4}: {5}; {6}: {7}s; {8}: {9}" -f `
        $focusMarker, $focusStatus, `
        (ConvertFrom-UnicodeCodePoints @(0x4ECA, 0x65E5)), (Format-FocusDuration $script:focusActiveSeconds), `
        (ConvertFrom-UnicodeCodePoints @(0x5B8C, 0x6210, 0x8F6E, 0x6570)), $script:focusCompletedPomodoros, `
        (ConvertFrom-UnicodeCodePoints @(0x8DDD, 0x4E0A, 0x6B21, 0x64CD, 0x4F5C)), $script:focusIdleSeconds, `
        (ConvertFrom-UnicodeCodePoints @(0x952E, 0x76D8, 0x6572, 0x51FB)), $script:keyboardPresses
    $focusLine += "; {0}: {1}; {2}: {3}" -f `
        (ConvertFrom-UnicodeCodePoints @(0x7D2F, 0x8BA1, 0x4E13, 0x6CE8)), (Format-FocusDuration $script:totalFocusSeconds), `
        (ConvertFrom-UnicodeCodePoints @(0x7D2F, 0x8BA1, 0x6572, 0x51FB)), $script:totalKeyboardPresses
    $markerIndex = ([string]$usageBubble.ToolTip).IndexOf("`n$focusMarker")
    $baseTooltip = if ($markerIndex -ge 0) { ([string]$usageBubble.ToolTip).Substring(0, $markerIndex) } else { [string]$usageBubble.ToolTip }
    $usageBubble.ToolTip = if ([string]::IsNullOrWhiteSpace($baseTooltip)) { $focusLine } else { "$baseTooltip`n$focusLine" }
    Update-BubblePage
}

function Write-FocusState {
    if (-not $focusEnabled) { return }

    $state = [ordered]@{
        schemaVersion = 1
        date = $script:focusDate
        activeSeconds = $script:focusActiveSeconds
        keyboardPresses = $script:keyboardPresses
        keyboardCounterAvailable = $script:keyboardCounterAvailable
        pomodoroElapsedSeconds = $script:focusPomodoroElapsedSeconds
        completedPomodoros = $script:focusCompletedPomodoros
        isActive = $script:focusIsActive
        idleSeconds = $script:focusIdleSeconds
        updatedAtUtc = [DateTime]::UtcNow.ToString("o")
    }
    $temporaryPath = "{0}.{1}.tmp" -f $focusStatePath, $PID
    $state | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $temporaryPath -Encoding UTF8
    Move-Item -LiteralPath $temporaryPath -Destination $focusStatePath -Force
    $script:lastFocusPersistedAt = [DateTime]::UtcNow
}

function Initialize-FocusState {
    if (-not $focusEnabled -or -not (Test-Path -LiteralPath $focusStatePath)) {
        Update-FocusDisplay
        return
    }
    try {
        $stored = Get-Content -Raw -Encoding UTF8 -LiteralPath $focusStatePath | ConvertFrom-Json
        if ([string]$stored.date -eq $script:focusDate) {
            $script:focusActiveSeconds = [int]$stored.activeSeconds
            $script:focusPomodoroElapsedSeconds = [int]$stored.pomodoroElapsedSeconds
            $script:focusCompletedPomodoros = [int]$stored.completedPomodoros
            $script:keyboardPresses = [int]$stored.keyboardPresses
        }
    } catch {
        # Start a fresh daily tally if an interrupted write left an invalid state file.
    }
    Update-FocusDisplay
}

function Update-FocusTracking {
    if (-not $focusEnabled) { return }

    $now = [DateTime]::UtcNow
    $elapsedSeconds = [Math]::Floor(($now - $script:lastFocusSampleAt).TotalSeconds)
    if ($elapsedSeconds -lt 1) { return }
    $script:lastFocusSampleAt = $now
    $elapsedSeconds = [Math]::Min(2, [int]$elapsedSeconds)

    $today = [DateTime]::Now.ToString("yyyy-MM-dd")
    if ($today -ne $script:focusDate) {
        $script:focusDate = $today
        $script:focusActiveSeconds = 0
        $script:focusPomodoroElapsedSeconds = 0
        $script:focusCompletedPomodoros = 0
        $script:keyboardPresses = 0
    }

    $script:focusIdleSeconds = [Math]::Floor([double][PixelDoraemon.FocusNative]::GetActivityIdleMilliseconds() / 1000)
    $script:focusIsActive = $script:focusIdleSeconds -le $focusIdleThresholdSeconds

    if ($script:keyboardCounterAvailable) {
        $newKeyboardPresses = [int][PixelDoraemon.FocusNative]::ConsumeKeyboardPresses()
        if ($newKeyboardPresses -gt 0) {
            $script:keyboardPresses += $newKeyboardPresses
            $script:totalKeyboardPresses += $newKeyboardPresses
        }
        Check-ProgressMilestones
    }

    if ($script:focusIsActive) {
        $script:focusActiveSeconds += $elapsedSeconds
        $script:focusPomodoroElapsedSeconds += $elapsedSeconds
        $script:totalFocusSeconds += $elapsedSeconds
        if ($script:focusPomodoroElapsedSeconds -ge $focusPomodoroSeconds) {
            $newCompletedRounds = [int][Math]::Floor($script:focusPomodoroElapsedSeconds / $focusPomodoroSeconds)
            $script:focusCompletedPomodoros += $newCompletedRounds
            $script:totalCompletedFocusRounds += $newCompletedRounds
            $script:focusPomodoroElapsedSeconds %= $focusPomodoroSeconds
            $roundTitle = "30 " + (ConvertFrom-UnicodeCodePoints @(0x5206, 0x949F, 0x4E13, 0x6CE8, 0x5B8C, 0x6210))
            $roundValue = (ConvertFrom-UnicodeCodePoints @(0x7B2C)) + " {0} " + (ConvertFrom-UnicodeCodePoints @(0x8F6E)) -f $script:totalCompletedFocusRounds
            $roundMessage = ConvertFrom-UnicodeCodePoints @(0x8FD9, 0x4E00, 0x6BB5, 0x4E13, 0x6CE8, 0x5DF2, 0x7ECF, 0x6C89, 0x6DC0, 0x6210, 0x4F60, 0x7684, 0x8282, 0x594F)
            Add-ProgressEvent ("focus-round-{0}" -f $script:totalCompletedFocusRounds) "focus-round" $roundTitle $roundValue $roundMessage $true
        }
        Check-ProgressMilestones
    }

    Update-FocusDisplay
    if (($now - $script:lastFocusPersistedAt).TotalSeconds -ge 10) {
        Write-FocusState
    }
    if (($now - $script:lastProgressPersistedAt).TotalSeconds -ge 10) {
        Write-ProgressState
    }
}

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
    if ($null -eq $Minutes) { return (ConvertFrom-UnicodeCodePoints @(0x672A, 0x77E5, 0x7A97, 0x53E3)) }
    $value = [long]$Minutes
    if ($value -ge 1440 -and $value % 1440 -eq 0) { return ("{0}" -f ($value / 1440)) + (ConvertFrom-UnicodeCodePoints @(0x5929)) }
    if ($value -ge 60 -and $value % 60 -eq 0) { return ("{0}" -f ($value / 60)) + (ConvertFrom-UnicodeCodePoints @(0x5C0F, 0x65F6)) }
    return ("{0}" -f $value) + (ConvertFrom-UnicodeCodePoints @(0x5206, 0x949F))
}

function Get-UsageResetLabel($EpochSeconds) {
    if ($null -eq $EpochSeconds) { return $null }
    try {
        return [DateTimeOffset]::FromUnixTimeSeconds([long]$EpochSeconds).ToLocalTime().ToString("MM'/'dd HH:mm")
    } catch {
        return $null
    }
}

function Set-UsageUnavailable([string]$Reason) {
    $script:usageMinimumRemaining = $null
    $script:usageDetailLabel = ConvertFrom-UnicodeCodePoints @(0x989D, 0x5EA6, 0x6682, 0x4E0D, 0x53EF, 0x7528)
    $usageBubble.ToolTip = if ([string]::IsNullOrWhiteSpace($Reason)) {
        "Codex " + (ConvertFrom-UnicodeCodePoints @(0x5269, 0x4F59, 0x989D, 0x5EA6, 0x6682, 0x4E0D, 0x53EF, 0x7528))
    } else {
        "Codex " + (ConvertFrom-UnicodeCodePoints @(0x5269, 0x4F59, 0x989D, 0x5EA6, 0x6682, 0x4E0D, 0x53EF, 0x7528, 0x3002, 0x8BE6, 0x7EC6, 0x539F, 0x56E0, 0xFF1A)) + "`n$Reason"
    }
    Update-BubblePage
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

            $detail = "{0}" + (ConvertFrom-UnicodeCodePoints @(0x7A97, 0x53E3, 0xFF1A, 0x5269, 0x4F59)) + " {1}%" -f $duration, $remaining
            if ($showResetTime) {
                $reset = Get-UsageResetLabel $usageWindow.resetsAt
                if ($reset) { $detail += (ConvertFrom-UnicodeCodePoints @(0xFF0C, 0x91CD, 0x7F6E, 0x4E8E)) + " $reset" }
            }
            [void]$detailParts.Add($detail)
        }

        if ($labelParts.Count -eq 0 -and $null -ne $state.credits -and [bool]$state.credits.unlimited) {
            [void]$labelParts.Add((ConvertFrom-UnicodeCodePoints @(0x4E0D, 0x9650, 0x91CF)))
            [void]$detailParts.Add("Codex " + (ConvertFrom-UnicodeCodePoints @(0x5F53, 0x524D, 0x7528, 0x91CF, 0x4E0D, 0x9650, 0x5236)))
        }
        if ($labelParts.Count -eq 0) {
            Set-UsageUnavailable (ConvertFrom-UnicodeCodePoints @(0x5F53, 0x524D, 0x8D26, 0x6237, 0x6CA1, 0x6709, 0x53EF, 0x663E, 0x793A, 0x7684, 0x7528, 0x91CF, 0x7A97, 0x53E3))
            return
        }

        $tooltip = New-Object System.Collections.Generic.List[string]
        [void]$tooltip.Add("Codex " + (ConvertFrom-UnicodeCodePoints @(0x5269, 0x4F59, 0x989D, 0x5EA6)))
        foreach ($detail in $detailParts) { [void]$tooltip.Add($detail) }
        if ($null -ne $state.credits -and [bool]$state.credits.hasCredits -and -not [bool]$state.credits.unlimited) {
            [void]$tooltip.Add(((ConvertFrom-UnicodeCodePoints @(0x53EF, 0x7528, 0x70B9, 0x6570)) + ": {0}" -f $state.credits.balance))
        }
        [void]$tooltip.Add(((ConvertFrom-UnicodeCodePoints @(0x66F4, 0x65B0, 0x65F6, 0x95F4)) + ": {0}" -f ([DateTime]$state.timestampUtc).ToLocalTime().ToString("HH:mm:ss")))
        $usageBubble.ToolTip = $tooltip -join "`n"

        $minimumRemaining = if ($remainingValues.Count -gt 0) {
            ($remainingValues | Measure-Object -Minimum).Minimum
        } else {
            100
        }
        $script:usageMinimumRemaining = if ($remainingValues.Count -gt 0) { [int]$minimumRemaining } else { 100 }
        $script:usageDetailLabel = if ($remainingValues.Count -gt 0) {
            $labelParts -join ("  " + [char]0x00B7 + "  ")
        } else {
            ConvertFrom-UnicodeCodePoints @(0x5F53, 0x524D, 0x8D26, 0x6237, 0x4E0D, 0x9650, 0x91CF)
        }
        Update-BubblePage
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
        $wasBubbleVisible = $script:usageBubbleVisible
        Show-UsageBubbleFromInteraction
        if ($wasBubbleVisible) { Show-NextBubblePage }
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
$menuHeaderText.Text = (ConvertFrom-UnicodeCodePoints @(0x54C6, 0x5566, 0x0041, 0x68A6)) + (ConvertFrom-UnicodeCodePoints @(0x4F19, 0x4F34))
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

if ($focusEnabled) {
    $focusDashboardItem = New-Object System.Windows.Controls.MenuItem
    $focusDashboardItem.Style = $menuItemStyle
    $focusDashboardItem.Header = (ConvertFrom-UnicodeCodePoints @(0x6253, 0x5F00)) + (ConvertFrom-UnicodeCodePoints @(0x4E13, 0x6CE8, 0x540E, 0x53F0))
    $focusDashboardItem.Add_Click({ Show-FocusDashboard })
    [void]$menu.Items.Add($focusDashboardItem)
}

$openConfigItem = New-Object System.Windows.Controls.MenuItem
$openConfigItem.Style = $menuItemStyle
$openConfigItem.Header = (ConvertFrom-UnicodeCodePoints @(0x6253, 0x5F00)) + (ConvertFrom-UnicodeCodePoints @(0x4F19, 0x4F34, 0x8BBE, 0x7F6E))
$openConfigItem.Add_Click({
    Start-Process -FilePath "notepad.exe" -ArgumentList ('"{0}"' -f $configPath) | Out-Null
})
[void]$menu.Items.Add($openConfigItem)

$restartItem = New-Object System.Windows.Controls.MenuItem
$restartItem.Style = $menuItemStyle
$restartItem.Header = (ConvertFrom-UnicodeCodePoints @(0x91CD, 0x65B0, 0x542F, 0x52A8)) + (ConvertFrom-UnicodeCodePoints @(0x4F19, 0x4F34))
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
$exitItem.Header = (ConvertFrom-UnicodeCodePoints @(0x9000, 0x51FA)) + (ConvertFrom-UnicodeCodePoints @(0x4F19, 0x4F34))
$exitItem.Add_Click({ $window.Close() })
[void]$menu.Items.Add($exitItem)
$image.ContextMenu = $menu
$root.ContextMenu = $menu

$stateTimer = New-Object System.Windows.Threading.DispatcherTimer
$stateTimer.Interval = [TimeSpan]::FromMilliseconds(180)
$stateTimer.Add_Tick({
    Test-And-ReloadSprite
    Update-UsageDisplay
    Update-UsageBubbleSchedule
    Update-BubblePageRotation
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

$focusTimer = New-Object System.Windows.Threading.DispatcherTimer
$focusTimer.Interval = [TimeSpan]::FromSeconds(1)
$focusTimer.Add_Tick({ Update-FocusTracking })

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
    $focusTimer.Stop()
    Write-FocusState
    Write-ProgressState
    if ($script:keyboardCounterAvailable) { [PixelDoraemon.FocusNative]::StopInputCounter() }
    Remove-Item -LiteralPath $pidPath -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $usageRefreshRequestPath -ErrorAction SilentlyContinue
    if ($script:ownsSingleInstanceMutex) {
        $script:singleInstanceMutex.ReleaseMutex()
        $script:ownsSingleInstanceMutex = $false
    }
    $script:singleInstanceMutex.Dispose()
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
Initialize-FocusState
Initialize-ProgressState
if ($focusEnabled) {
    try {
        [PixelDoraemon.FocusNative]::StartInputCounter()
    } catch {
        $script:keyboardCounterAvailable = $false
    }
}
Set-Frame "idle" 0
$stateTimer.Start()
$animationTimer.Start()
$focusTimer.Start()
[void]$window.ShowDialog()
