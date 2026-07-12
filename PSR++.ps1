# ==============================================================================
# PROGRAM: Problem Step Recorder Plus (PSR++)
# PLATFORM: Windows PowerShell 5.1+ & Windows Presentation Foundation (WPF)
# DESCRIPTION: A high-performance screen capturing utility optimized for secure,
#              rapid step-recording and visual software audits. Features an
#              interactive session preview sidebar and automatic clipboard copying.
# THEME: Catppuccin Macchiato
# ==============================================================================
Set-StrictMode -Version latest
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Drawing,System.Windows.Forms

 $global:EnableDebugLogs = $false

# ==============================================================================
# SECTION 1: NATIVE OS INTERMEDIARY (P/INVOKE DEFINITIONS)
# ==============================================================================
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32 {
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vKey);
    public const int VK_ESCAPE = 0x1B;
    [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(Point p);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out Point p);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr hWnd, ref Point lpPoint);
    [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr hwnd, uint gaFlags);
    [DllImport("user32.dll", CharSet = CharSet.Auto)] public static extern int GetClassName(IntPtr hWnd, System.Text.StringBuilder lpClassName, int nMaxCount);
    [DllImport("user32.dll")] public static extern bool GetCursorInfo(ref CURSORINFO pci);
    [DllImport("user32.dll")] public static extern IntPtr GetCursor();
    [DllImport("user32.dll")] public static extern bool DrawIcon(IntPtr hdc, int x, int y, IntPtr hIcon);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool IsProcessDPIAware();
    [DllImport("user32.dll")] public static extern IntPtr GetDC(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);
    [DllImport("gdi32.dll")] public static extern int GetDeviceCaps(IntPtr hdc, int nIndex);
    [DllImport("user32.dll", CharSet = CharSet.Auto)] public static extern IntPtr SendMessage(IntPtr hWnd, int Msg, IntPtr wParam, IntPtr lParam);
    
    // DWM API for exact visible window bounds (removes invisible 7px borders in Win10/11)
    [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr hwnd, int attribute, ref RECT pvAttribute, int cbAttribute);
    public const int DWMWA_EXTENDED_FRAME_BOUNDS = 9;
    
    public const int WM_SETICON = 0x0080;
    public const int ICON_SMALL = 0;
    [StructLayout(LayoutKind.Sequential)]
    public struct CURSORINFO { public int cbSize; public int flags; public IntPtr hCursor; public Point ptScreenPos; }
    public const int CURSOR_SHOWING = 0x00000001;
    public const uint GA_ROOT = 2;
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
    [StructLayout(LayoutKind.Sequential)]
    public struct Point { public int X; public int Y; }
}
"@

# ==============================================================================
# ENFORCE DPI AWARENESS
# ==============================================================================
try { [Win32]::SetProcessDPIAware() | Out-Null } catch { Write-Warning "Could not enforce DPI awareness. Captures may be offset on high-DPI displays." }

 $screenshotPath = Join-Path ([Environment]::GetFolderPath('MyPictures')) 'Screenshots'
if (-not (Test-Path $screenshotPath)) { New-Item -ItemType Directory -Path $screenshotPath | Out-Null }

# ==============================================================================
# SECTION 2: GLOBAL STATE VARIABLES & REAL-TIME LOGGING ENGINE
# ==============================================================================
 $captureFolder = $screenshotPath
 $global:lastCapturePath = $null; $global:isCapturing = $false; $global:wasMouseDown = $false
 $global:outlineColor = [System.Drawing.Color]::FromArgb(166, 218, 149); $global:delayTimer = $null
 $global:continuousMode = $false; $global:stopCapture = $false; $global:preparingCapture = $false
 $global:mouseHighlightColor = [System.Drawing.Color]::FromArgb(245, 169, 127)
 $global:mouseHighlightOpacity = 127; $global:mouseHighlightSize = 50
 $global:showMouseCursor = $true; $global:showMouseHighlight = $true; $global:captureCounter = 1
 $global:debugLogs = [System.Collections.Generic.List[string]]::new()

function Write-DebugLog {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $formattedMessage = "[$timestamp] $Message"
    $global:debugLogs.Add($formattedMessage)
    if ($global:EnableDebugLogs) { Write-Host $formattedMessage -ForegroundColor Yellow }
}

Write-DebugLog "Initialization started. PSR++ engine preparing host containers."
 $global:sessionId = Get-Date -Format "yyMMdd_HHmmss"
 $global:sessionFolder = Join-Path $captureFolder $global:sessionId
New-Item -ItemType Directory -Path $global:sessionFolder -Force | Out-Null
Write-DebugLog "Created session output directory: $global:sessionFolder"

try {
    Write-DebugLog "[DPI INFO] === SYSTEM DISPLAY DIAGNOSTICS START ==="
    $isAware = [Win32]::IsProcessDPIAware()
    Write-DebugLog "[DPI INFO] OS Process DPI Awareness Granted: $isAware"
    $hdc = [Win32]::GetDC([IntPtr]::Zero)
    $logicalW = [Win32]::GetDeviceCaps($hdc, 8); $logicalH = [Win32]::GetDeviceCaps($hdc, 10)
    $physicalW = [Win32]::GetDeviceCaps($hdc, 118); $physicalH = [Win32]::GetDeviceCaps($hdc, 117)
    $logPixX = [Win32]::GetDeviceCaps($hdc, 88); $logPixY = [Win32]::GetDeviceCaps($hdc, 90)
    [Win32]::ReleaseDC([IntPtr]::Zero, $hdc) | Out-Null
    $hardwareScale = [math]::Round(($physicalW / $logicalW) * 100)
    Write-DebugLog "[DPI INFO] GDI Logical Resolution (Virtual): ${logicalW}x${logicalH}"
    Write-DebugLog "[DPI INFO] GDI Physical Resolution (Hardware): ${physicalW}x${physicalH}"
    Write-DebugLog "[DPI INFO] Hardware Device Caps Scaling: $hardwareScale% (LogPixels: X=$logPixX, Y=$logPixY)"
    $screens = [System.Windows.Forms.Screen]::AllScreens
    Write-DebugLog "[DPI INFO] Total Connected Displays: $($screens.Count)"
    for ($i = 0; $i -lt $screens.Count; $i++) {
        $s = $screens[$i]; $primaryTag = if ($s.Primary) { "[PRIMARY]" } else { "" }
        Write-DebugLog "[DPI INFO] Display [$i] $primaryTag Name: $($s.DeviceName)"
        Write-DebugLog "[DPI INFO] Display [$i] Logical Bounds: X=$($s.Bounds.X), Y=$($s.Bounds.Y), W=$($s.Bounds.Width), H=$($s.Bounds.Height)"
    }
    Write-DebugLog "[DPI INFO] === SYSTEM DISPLAY DIAGNOSTICS END ==="
} catch { Write-DebugLog "[DPI INFO] Error retrieving enhanced DPI diagnostics: $_" }

 $iniPath = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'PSR_Plus_Config.json'

# ==============================================================================
# SECTION 3: CONFIGURATION SERIALIZERS (JSON FILE ENGINE)
# ==============================================================================
function Import-IniFile {
    param([string]$FilePath)
    if (-not (Test-Path $FilePath)) { return $null }
    return Get-Content $FilePath -Raw | ConvertFrom-Json
}

function Out-IniFile {
    param([string]$FilePath, [object]$Data)
    $Data | ConvertTo-Json -Depth 5 | Out-File $FilePath -Encoding utf8 -Force
}

 $icon = "AAABAAkAEBAAAAEAIABoBAAAlgAAABgYAAABACAAiAkAAP4EAAAgIAAAAQAgAKgQAACGDgAAMDAAAAEAIACoJQAALh8AAEBAAAABACAAKEIAANZEAABgYAAAAQAgAKiUAAD+hgAAgIAAAAEAIAAoCAEAphsBAMDAAAABACAAKFICAM4jAgAAAAAAAQAgAMAqAAD2dQQAKAAAABAAAAAgAAAAAQAgAAAAAAAABAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA4ZkZAOSfHQHhmBhy4JcX0+GXF8zhmBhI4ZcXAOGZGQAAAAAAAAAAAAAAAAAAAAAAtmUHALdlBwK0ZAgOsmIJBtyVGQDjnRsZ45wbt+GZGTTimxpe450boOSfHQPjnhwAAAAAAAAAAAAAAAAAumgGALxpBgS4ZgdstGQItbBhCZipWwgg56UgH+WjH8zmpSBb6KUegOejHZHqnRIB6KIaAAAAAAAAAAAAAAAAALtoBgC7aAYwuWcHuLZlCDWvYAmPq10Ku8Z/FULpqSHf5qci9MuYNbKEcmVAACTKDA83sgAONbQAAAAAAAAAAAC7aAYAu2gGMLlnB7i2ZQg1r2AJjqtdCP+tbSPT0q1d8MCjZvspRqjfCzO24A41tMUONbRkDjW0CQ41tAAAAAAAumgGALxpBgS4ZgdstWQItK9gCKSeYyjdoIx2/7Gysv+srrXsOVa1cwsztIEONbTgDjW0+Q41tHgONbQCDjW0AAAAAAC2ZQcAtWUGAt1vAAsWNqlLMUqmwZiaoNe7u7r/vr6+6bSyrDF8ibQADjW1Qw01tusNNbbkDTW3KQ01twAAAAAAAAAAAA01tgAMNLYcDjW0rAYvtj2urao7vr6+7Ly8vP+np6e+pqWkIwAOvwQMNrqyDDa6/ww2ulYMNroAAAAAAA41tAAONbQADjW0bA41tHF2hrkAvby8H7y8vOC5ubn/qKio/6ampr6Ym6QmCTa/qAo3vv8KN75bCje+AAAAAAAONbQADjW0CQ41tJMONbQlZXm5AL6+vh++vr7hwMDA9aurq9+kpKP/hYmWxhA7vtwIN8P4CTfCQgk3wgAAAAAADjW0AA41tBsONbSQDjW0Cp+mvgDBwcEfwcHB4tbW1uHAwMBPmZiVyVlpmf8LOsT/BzjH2Ac4xhsIOMYAAAAAAA41swAONbMTDjWzUA81sgO7vcIAw8PDH8TExOLZ2dni+vjxHD1Yp1cXQr/3BTjM/wY5y4oPNLEABjjJAAAAAAADOtIAAzrSEgM60VADOtFDACvSErW5xSLHx8bi1dbY50Fnz3MAN8/OAznQ/wQ6z9IFOc4kBTnOAAAAAAACO9UAAzrSAAI71IADOtT+AzrU9QE51M8eTMy4trvI9MTJ1v4fTMr6ATnS/MMy0+ADOtJGAjrUAAM60gAAAAAAAjvWAAE72AABO9d5ATvX+wE71/8BO9f/BDzT/2iDzP+0vtj/HU7R+gA51sACO9Y9GR6iAAI61gAAAAAAAAAAAAAAAAABO9gAATvYEAE72G4BO9jLATvY9gA62P8KQNXxP2jWxRdL1W8ANtcXATvVAAA72wAAAAAAAAAAAAAAAAD8HwAAxA8AAIAPAACADwAAgAMAAIABAADAIQAA4AEAAOQBAADEAQAAxAEAAMQDAADAAwAAwAcAAMAPAADAHwAAKAAAABgAAAAwAAAAAQAgAAAAAAAACQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAOGXFwDhmBgD4JcXa+CWFunglhb+4JYWx+GXFzPglxcA4JcWAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAOKaGQDimhk94pkZ5eGYGJ7hmBdo4ZkYzeKaGbfimxoN4psaAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAALVkCAC1ZQgCs2MICbJiCQOyYggAsGEJAOOdGwDjnRt7450b1eOcGxbjnRsA450bVOOdG+fjnhwt454cAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAC6aAYAt2YHALlnByi2ZQeYtGMIxLFhCZ2uYAkusWIIAOShHgDloR6B5aIe5eWjHzLnpiED5aIfduWhHuHkoR4k5KEeAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAC7aAYAu2kGFLlnB763ZgfWtGMIAK9gCTetXwrtq10K1aRXCTbpqiN+6Kkj/+mpIv/fpCjUuY9CeUtUjSoEL7sVDzWzBA41tAAONbQAAAAAAAAAAAAAAAAAAAAAAAAAAAC7aAYAu2kGRbpnB+m4ZgdCtGMIAK9gCTetXwrsql0K/6ZaCtPPlzK14a89/+OvO/+Cd3LmBzG42A01tOAONbTVDjW0pQ41tEgONbQFDjW0AAAAAAAAAAAAAAAAAAAAAAC7aAYAu2kGFLlnB763ZgfWtGMIAK9gCTetXwrsql0K/6ZaCtPPlzK14a89/+OvO/+Cd3LmBzG42A01tOAONbTVDjW0pQ41tEgONbQFDjW0AAAAAAAAAAAAAAAAAC6aAYAt2YHALlnByi2ZQeYs2MIxLJiCJqjWxJ5nmgz85yPgf+nqKr/tbW2/7W1tf+gpbaRACa0Hw41tDcONbSMDjW08A41tP8ONbT4DjW0bg01tAAONbQAAAAAAAAAAAAAAAAAAAAAALVkCAC1ZAgCv2cACDM+mQgLM7WDP1Wk75WXnPCpqan/u7u7/7u7u/+2trWFtLa/AB9CsgAONbMDDjW1bQ41tfgONbX/DjW12g01tiINNbYAAAAAAAAAAAAAAAAAAAAAAAAAAAALNLcAEjawAA41tGUONbTnDDS2ZpaXnFerq6vnzMzM/8vLy/+urq7ZoaGhO6GhoQAUO7YADTW3DQ02uL0NNrj/DTa4/Q02uF0NNrgADTa5AAAAAAAAAAAAAAAAAAAAAAAONbQADjW0KA41tNYONbR2Aiy2AvH//wC3t7eNu7u7/7y8vP+urq7/pKSk1qWlpTuio6QADji7AAw2u4cMNrv/DDa7/ww2u4IMNrsACza7AAAAAAAAAAAAAAAAAA41tAAONbQADjW0hw41tLUONbQODjW0ALu7uwC7u7sfu7u74Lu7u/+7u7v/uLi4/6enp/+lpaX/pqam6aamplinp6cBETu8AAs3vVkLN739Cze9/ws3vf8LN72uCze9BAs3vQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAONbQADjW0KA41tOUONbSQAjw2AvH//wC3t7eNu7u7/7y8vP+urq7/pKSk1qWlpTuio6QADji7AAw2u4cMNrv/DDa7/ww2u4IMNrsACza7AAAAAAAAAAAAAAAAAA41tAAONbQADjW0hw41tLUONbQODjW0ALu7uwC7u7sfu7u74Lu7u/+7u7v/uLi4/6enp/+lpaX/pqam6aamplinp6cBETu8AAs3vVkLN739Cze9/ws3vf8LN72uCze9BAs3vQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAONbQADjW0KA41tOUONbSQDjW0AQ41tAAAAAAAvLy8ALy8vB+8vLzgvLy8/729vf+6urr/qKio/6ampv+np6f/pqam6aKiolgALswACje/bgo3v/8KN7//Cje//wo3v6EKN74BCje/AAAAAAAAAAAAAAAAAAAAAAAAAAAADjW0AA41tAAONbRlDjW07Q41tDkONbQAAAAAAAAAAAC+vr4Avr6+H76+vuC+vr7/vr6+/7u7u/2pqan8p6en/6enp/+kpKT/m5ub542NjVQJN8GZCTfC/wk3wv8JN8L/CTfBhgk3wgAJN8EAAAAAAAAAAAAAAAAAAAAAAAAAAAAONbQADjW0AA41tKAONbTGDjW0DQ41tAAAAAAAAAAAAL+/vwC/v78fv7+/4b+/v/+/v7//wMDA/8fHx//JycnftLS0Taenp8ioqKj/p6en/6SkpP+enp7/lZWV/4mJiP9wdYP7GEG5+Ac3xf8IOMT/CDjE/wg4xP8IOMT/CDjEdgg4xAAJN8QAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA41tAAONbQDDjW0qA41tP8ONbRxDjW0AA41tAAAAAAAAAAAAAAAAAAAAAAAAAAAAMDAwADAwMAewMDA4cDAwP/AwMD/wMDA/8HBwf/b29v/5ubm/+SwGf/8B/A//8DwAf///+D4f/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////8="

# ==============================================================================
# CATPPUCCIN MACCHIATO THEME COLOR DEFINITIONS
# ==============================================================================
# Base: #24273a | Mantle: #1e2030 | Crust: #181926
# Surface0: #363a4f | Surface1: #494d64 | Surface2: #5b6078
# Overlay0: #6e738d | Overlay1: #8087a2 | Overlay2: #939ab7
# Subtext0: #a5adcb | Subtext1: #b8c0e0 | Text: #cad3f5
# Lavender: #b7bdf8 | Blue: #8aadf4 | Sapphire: #7dc4e4 | Sky: #91d7e3
# Teal: #8bd5ca | Green: #a6da95 | Yellow: #eed49f | Peach: #f5a97f
# Maroon: #ee99a0 | Red: #ed8796 | Mauve: #c6a0f6 | Pink: #f5bde6
# Flamingo: #f0c6c6 | Rosewater: #f4dbd6
# ==============================================================================

 $xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="PSR++" Height="700" Width="1050" WindowStyle="None" ResizeMode="CanMinimize" WindowStartupLocation="CenterScreen" Background="#24273a" UseLayoutRounding="True" SnapsToDevicePixels="True">
    <WindowChrome.WindowChrome>
        <WindowChrome CaptionHeight="32" ResizeBorderThickness="6" CornerRadius="0" GlassFrameThickness="0" UseAeroCaptionButtons="False"/>
    </WindowChrome.WindowChrome>
    <Window.Resources>
        <Style TargetType="Button">
            <Setter Property="Foreground" Value="#cad3f5"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="btnBorder" Background="{TemplateBinding Background}" CornerRadius="5" BorderThickness="0">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="btnBorder" Property="Opacity" Value="0.85"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="btnBorder" Property="Opacity" Value="0.4"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="CheckBox">
            <Setter Property="Foreground" Value="#cad3f5"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="CheckBox">
                        <StackPanel Orientation="Horizontal" Background="Transparent">
                            <Border x:Name="cbBorder" Width="16" Height="16" CornerRadius="3" Background="#363a4f" BorderBrush="#6e738d" BorderThickness="1" VerticalAlignment="Center">
                                <TextBlock x:Name="cbCheck" Text="" Foreground="#24273a" FontWeight="Bold" FontSize="14" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                            </Border>
                            <ContentPresenter Margin="8,0,0,0" VerticalAlignment="Center"/>
                        </StackPanel>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="cbBorder" Property="BorderBrush" Value="#8aadf4"/>
                            </Trigger>
                            <Trigger Property="IsChecked" Value="True">
                                <Setter TargetName="cbBorder" Property="Background" Value="#8aadf4"/>
                                <Setter TargetName="cbBorder" Property="BorderBrush" Value="#8aadf4"/>
                                <Setter TargetName="cbCheck" Property="Text" Value="✓"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="TextBlock">
            <Setter Property="Foreground" Value="#cad3f5"/>
        </Style>
        
        <!-- Refined Slider Style -->
        <Style TargetType="Slider">
            <Setter Property="Foreground" Value="#8aadf4"/>
            <Setter Property="Height" Value="20"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Slider">
                        <Grid>
                            <Border Height="4" VerticalAlignment="Center" Background="#494d64" CornerRadius="2"/>
                            <Track x:Name="PART_Track" VerticalAlignment="Center">
                                <Track.DecreaseRepeatButton>
                                    <RepeatButton Command="Slider.DecreaseLarge">
                                        <RepeatButton.Template>
                                            <ControlTemplate TargetType="RepeatButton">
                                                <Border Height="4" VerticalAlignment="Center" Background="#8aadf4" CornerRadius="2"/>
                                            </ControlTemplate>
                                        </RepeatButton.Template>
                                    </RepeatButton>
                                </Track.DecreaseRepeatButton>
                                <Track.IncreaseRepeatButton>
                                    <RepeatButton Command="Slider.IncreaseLarge">
                                        <RepeatButton.Template>
                                            <ControlTemplate TargetType="RepeatButton">
                                                <Border Height="4" VerticalAlignment="Center" Background="Transparent"/>
                                            </ControlTemplate>
                                        </RepeatButton.Template>
                                    </RepeatButton>
                                </Track.IncreaseRepeatButton>
                                <Track.Thumb>
                                    <Thumb>
                                        <Thumb.Template>
                                            <ControlTemplate TargetType="Thumb">
                                                <Border Background="#cad3f5" CornerRadius="8" Width="14" Height="14" BorderBrush="#8aadf4" BorderThickness="1"/>
                                            </ControlTemplate>
                                        </Thumb.Template>
                                    </Thumb>
                                </Track.Thumb>
                            </Track>
                        </Grid>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        
        <!-- Dark ScrollBar Style -->
        <Style x:Key="DarkScrollBarThumb" TargetType="Thumb">
            <Setter Property="Background" Value="#494d64"/>
            <Setter Property="BorderBrush" Value="Transparent"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Thumb">
                        <Border Background="{TemplateBinding Background}" CornerRadius="3" Margin="2"/>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#6e738d"/>
                </Trigger>
            </Style.Triggers>
        </Style>
        <Style TargetType="ScrollBar">
            <Setter Property="Background" Value="#181926"/>
            <Setter Property="BorderBrush" Value="#181926"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Width" Value="12"/>
            <Setter Property="MinWidth" Value="12"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ScrollBar">
                        <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}">
                            <Grid>
                                <Track x:Name="PART_Track" IsDirectionReversed="True">
                                    <Track.DecreaseRepeatButton>
                                        <RepeatButton Command="ScrollBar.PageUpCommand">
                                            <RepeatButton.Template>
                                                <ControlTemplate TargetType="RepeatButton">
                                                    <Border Background="Transparent"/>
                                                </ControlTemplate>
                                            </RepeatButton.Template>
                                        </RepeatButton>
                                    </Track.DecreaseRepeatButton>
                                    <Track.IncreaseRepeatButton>
                                        <RepeatButton Command="ScrollBar.PageDownCommand">
                                            <RepeatButton.Template>
                                                <ControlTemplate TargetType="RepeatButton">
                                                    <Border Background="Transparent"/>
                                                </ControlTemplate>
                                            </RepeatButton.Template>
                                        </RepeatButton>
                                    </Track.IncreaseRepeatButton>
                                    <Track.Thumb>
                                        <Thumb Style="{StaticResource DarkScrollBarThumb}"/>
                                    </Track.Thumb>
                                </Track>
                            </Grid>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
            <Style.Triggers>
                <Trigger Property="Orientation" Value="Horizontal">
                    <Setter Property="Width" Value="Auto"/>
                    <Setter Property="Height" Value="12"/>
                    <Setter Property="MinHeight" Value="12"/>
                </Trigger>
            </Style.Triggers>
        </Style>
        
        <!-- Dark ContextMenu Fix -->
        <Style TargetType="ContextMenu">
            <Setter Property="SnapsToDevicePixels" Value="True"/>
            <Setter Property="OverridesDefaultStyle" Value="True"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ContextMenu">
                        <Border Background="#1e2030" BorderBrush="#494d64" BorderThickness="1" Padding="0,2">
                            <ItemsPresenter Grid.IsSharedSizeScope="True" KeyboardNavigation.DirectionalNavigation="Cycle"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <ControlTemplate x:Key="SubmenuItemTemplate" TargetType="MenuItem">
            <Border x:Name="Border" Background="{TemplateBinding Background}" SnapsToDevicePixels="True">
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition x:Name="Col0" MinWidth="25" Width="Auto" SharedSizeGroup="MenuItemIconColumnGroup"/>
                        <ColumnDefinition Width="Auto" SharedSizeGroup="MenuTextColumnGroup"/>
                        <ColumnDefinition Width="Auto" SharedSizeGroup="MenuItemIGTColumnGroup"/>
                        <ColumnDefinition x:Name="Col3" Width="15"/>
                    </Grid.ColumnDefinitions>
                    <ContentPresenter Grid.Column="0" x:Name="Icon" Margin="5,0" VerticalAlignment="Center" ContentSource="Icon"/>
                    <Path x:Name="CheckMark" Visibility="Hidden" Grid.Column="0" Margin="5,0" VerticalAlignment="Center" HorizontalAlignment="Center" Data="M 0,4 L 3,7 L 8,0" Stroke="#cad3f5" StrokeThickness="2"/>
                    <ContentPresenter Grid.Column="1" x:Name="HeaderHost" Margin="{TemplateBinding Padding}" RecognizesAccessKey="True" ContentSource="Header" VerticalAlignment="Center"/>
                    <TextBlock Grid.Column="2" x:Name="InputGestureText" Margin="20,0,10,0" Text="{TemplateBinding InputGestureText}" VerticalAlignment="Center" Foreground="#8087a2"/>
                    <Path Grid.Column="3" x:Name="RightArrow" Visibility="Hidden" Margin="0,0,5,0" VerticalAlignment="Center" HorizontalAlignment="Right" Data="M 0,0 L 4,3 L 0,6 Z" Fill="#cad3f5"/>
                    <Popup x:Name="Popup" Placement="Right" HorizontalOffset="0" VerticalOffset="-2" IsOpen="{TemplateBinding IsSubmenuOpen}" AllowsTransparency="True" Focusable="False">
                        <Border x:Name="SubmenuBorder" Background="#1e2030" BorderBrush="#494d64" BorderThickness="1">
                            <ItemsPresenter Grid.IsSharedSizeScope="True" KeyboardNavigation.DirectionalNavigation="Cycle" Margin="0,2"/>
                        </Border>
                    </Popup>
                </Grid>
            </Border>
            <ControlTemplate.Triggers>
                <Trigger Property="Role" Value="SubmenuHeader">
                    <Setter TargetName="RightArrow" Property="Visibility" Value="Visible"/>
                </Trigger>
                <Trigger Property="IsChecked" Value="True">
                    <Setter TargetName="CheckMark" Property="Visibility" Value="Visible"/>
                </Trigger>
                <Trigger Property="IsEnabled" Value="False">
                    <Setter Property="Foreground" Value="#6e738d"/>
                </Trigger>
                <MultiTrigger>
                    <MultiTrigger.Conditions>
                        <Condition Property="IsHighlighted" Value="True"/>
                        <Condition Property="IsEnabled" Value="True"/>
                    </MultiTrigger.Conditions>
                    <Setter Property="Background" TargetName="Border" Value="#363a4f"/>
                    <Setter Property="Foreground" Value="#cad3f5"/>
                </MultiTrigger>
            </ControlTemplate.Triggers>
        </ControlTemplate>
        <Style TargetType="MenuItem">
            <Setter Property="Background" Value="#1e2030"/>
            <Setter Property="Foreground" Value="#cad3f5"/>
            <Setter Property="Padding" Value="5,3"/>
            <Setter Property="Template" Value="{StaticResource SubmenuItemTemplate}"/>
        </Style>
        
        <!-- TitleBar Button Styles -->
        <Style x:Key="TitleBarButton" TargetType="Button">
            <Setter Property="Background" Value="#181926"/>
            <Setter Property="Foreground" Value="#cad3f5"/>
            <Setter Property="Width" Value="46"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="#363a4f"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="TitleBarCloseButton" TargetType="Button" BasedOn="{StaticResource TitleBarButton}">
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="#ed8796"/>
                                <Setter Property="Foreground" Value="White"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="32"/>
            <RowDefinition Height="*"/>
        </Grid.RowDefinitions>
        
        <!-- Custom Title Bar -->
        <Grid Grid.Row="0" Background="#181926">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <Viewbox Grid.Column="0" Width="14" Height="14" Margin="10,0,5,0" VerticalAlignment="Center">
                <Canvas Width="16" Height="16">
                    <Path Data="M2,0 L10,0 L14,4 L14,16 L2,16 Z" Stroke="#cad3f5" StrokeThickness="1.5" Fill="Transparent"/>
                    <Path Data="M10,0 L10,4 L14,4" Stroke="#cad3f5" StrokeThickness="1.5" Fill="Transparent"/>
                    <Path Data="M4,7 L10,7 M4,10 L12,10 M4,13 L9,13" Stroke="#cad3f5" StrokeThickness="1.5" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
                </Canvas>
            </Viewbox>
            <TextBlock Grid.Column="1" Text="PSR++" Foreground="#cad3f5" VerticalAlignment="Center" Margin="5,0,0,0" FontSize="12"/>
            <StackPanel Grid.Column="2" Orientation="Horizontal" WindowChrome.IsHitTestVisibleInChrome="True">
                <Button Name="btnMin" Style="{StaticResource TitleBarButton}">
                    <Path Data="M 0.5,5.5 L 9.5,5.5" Stroke="{Binding Foreground, RelativeSource={RelativeSource AncestorType=Button}}" StrokeThickness="1" SnapsToDevicePixels="True"/>
                </Button>
                <Button Name="btnClose" Style="{StaticResource TitleBarCloseButton}">
                    <Path Data="M 0.5,0.5 L 9.5,9.5 M 0.5,9.5 L 9.5,0.5" Stroke="{Binding Foreground, RelativeSource={RelativeSource AncestorType=Button}}" StrokeThickness="1.2" SnapsToDevicePixels="True"/>
                </Button>
            </StackPanel>
        </Grid>

        <!-- Main Content Area -->
        <Grid Grid.Row="1" Margin="20">
            <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
            <Grid Grid.Row="0">
                <Grid.ColumnDefinitions><ColumnDefinition Width="250"/><ColumnDefinition Width="250"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                <Border Grid.Column="0" Background="#1e2030" BorderBrush="#494d64" BorderThickness="1" CornerRadius="5" Padding="15" Margin="0,0,10,0">
                    <StackPanel>
                        <Button Name="captureButton" Content="Single Capture" Height="25" Margin="0,0,0,5" Background="#8aadf4" Foreground="#24273a"/>
                        <Button Name="continuousModeButton" Content="Continuous Capture" Height="25" Margin="0,0,0,5" Background="#a6da95" Foreground="#24273a"/>
                        <Grid Height="25">
                            <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="10"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                            <Button Grid.Column="0" Name="openButton" Content="Open Last" IsEnabled="False" Background="#c6a0f6" Foreground="#24273a"/>
                            <Button Grid.Column="2" Name="openFolderButton" Content="Open Folder" Background="#b7bdf8" Foreground="#24273a"/>
                        </Grid>
                    </StackPanel>
                </Border>
                <Border Grid.Column="1" Background="#1e2030" BorderBrush="#494d64" BorderThickness="1" CornerRadius="5" Padding="15" Margin="0,0,10,0">
                    <StackPanel VerticalAlignment="Center">
                        <CheckBox Name="fullScreenCheckbox" Content="Capture Full Screen" Margin="0,0,0,4"/>
                        <CheckBox Name="mouseCursorCheckbox" Content="Show Mouse Cursor" IsChecked="True" Margin="0,0,0,4"/>
                        <CheckBox Name="mouseHighlightCheckbox" Content="Show Mouse Highlight" IsChecked="True" Margin="0,0,0,4"/>
                        <CheckBox Name="showOutlineCheckbox" Content="Show Window Outline" IsChecked="True" Margin="0,0,0,4"/>
                        <CheckBox Name="screenshotBorderCheckbox" Content="Add Outer Border (2px Black)" IsChecked="True"/>
                    </StackPanel>
                </Border>
                <Border Grid.Column="2" Background="#1e2030" BorderBrush="#494d64" BorderThickness="1" CornerRadius="5" Padding="15">
                    <Grid>
                        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="20"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                        <StackPanel Grid.Column="0">
                            <Grid Margin="0,0,0,5">
                                <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="30"/></Grid.ColumnDefinitions>
                                <Button Grid.Column="0" Name="colorButton" Content="Outline Color" Width="90" Height="24" HorizontalAlignment="Left" Background="#7dc4e4" Foreground="#24273a"/>
                                <Border Grid.Column="2" Name="colorSquare" Width="24" Height="24" BorderBrush="#6e738d" BorderThickness="1" Background="#a6da95"/>
                            </Grid>
                            <Grid Margin="0,0,0,5">
                                <Grid.ColumnDefinitions><ColumnDefinition Width="80"/><ColumnDefinition Width="*"/><ColumnDefinition Width="30"/></Grid.ColumnDefinitions>
                                <TextBlock Grid.Column="0" Text="Outline Width:" VerticalAlignment="Center" FontSize="11" Foreground="#b8c0e0"/>
                                <Slider Grid.Column="1" Name="outlineWidthSlider" Minimum="0" Maximum="50" Value="5" VerticalAlignment="Center"/>
                                <TextBlock Grid.Column="2" Text="{Binding ElementName=outlineWidthSlider, Path=Value, StringFormat={}{0:N0}}" VerticalAlignment="Center" HorizontalAlignment="Right" FontSize="11" Foreground="#cad3f5"/>
                            </Grid>
                            <Grid>
                                <Grid.ColumnDefinitions><ColumnDefinition Width="80"/><ColumnDefinition Width="*"/><ColumnDefinition Width="30"/></Grid.ColumnDefinitions>
                                <TextBlock Grid.Column="0" Text="Opacity:" VerticalAlignment="Center" FontSize="11" Foreground="#b8c0e0"/>
                                <Slider Grid.Column="1" Name="opacitySlider" Minimum="0" Maximum="100" Value="80" VerticalAlignment="Center"/>
                                <TextBlock Grid.Column="2" Text="{Binding ElementName=opacitySlider, Path=Value, StringFormat={}{0:N0}}" VerticalAlignment="Center" HorizontalAlignment="Right" FontSize="11" Foreground="#cad3f5"/>
                            </Grid>
                        </StackPanel>
                        <StackPanel Grid.Column="2">
                            <Grid Margin="0,0,0,5">
                                <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="30"/></Grid.ColumnDefinitions>
                                <Button Grid.Column="0" Name="mouseHighlightColorButton" Content="Highlight Color" Width="95" Height="24" HorizontalAlignment="Left" Background="#f5a97f" Foreground="#24273a"/>
                                <Border Grid.Column="2" Name="mouseColorSquare" Width="24" Height="24" BorderBrush="#6e738d" BorderThickness="1" Background="#f5a97f"/>
                            </Grid>
                            <Grid Margin="0,0,0,5">
                                <Grid.ColumnDefinitions><ColumnDefinition Width="95"/><ColumnDefinition Width="*"/><ColumnDefinition Width="30"/></Grid.ColumnDefinitions>
                                <TextBlock Grid.Column="0" Text="Highlight Size:" VerticalAlignment="Center" FontSize="11" Foreground="#b8c0e0"/>
                                <Slider Grid.Column="1" Name="mouseHighlightSizeSlider" Minimum="5" Maximum="100" Value="50" VerticalAlignment="Center"/>
                                <TextBlock Grid.Column="2" Text="{Binding ElementName=mouseHighlightSizeSlider, Path=Value, StringFormat={}{0:N0}}" VerticalAlignment="Center" HorizontalAlignment="Right" FontSize="11" Foreground="#cad3f5"/>
                            </Grid>
                            <Grid>
                                <Grid.ColumnDefinitions><ColumnDefinition Width="95"/><ColumnDefinition Width="*"/><ColumnDefinition Width="30"/></Grid.ColumnDefinitions>
                                <TextBlock Grid.Column="0" Text="Highlight Opacity:" VerticalAlignment="Center" FontSize="11" Foreground="#b8c0e0"/>
                                <Slider Grid.Column="1" Name="mouseOpacitySlider" Minimum="0" Maximum="100" Value="65" VerticalAlignment="Center"/>
                                <TextBlock Grid.Column="2" Text="{Binding ElementName=mouseOpacitySlider, Path=Value, StringFormat={}{0:N0}}" VerticalAlignment="Center" HorizontalAlignment="Right" FontSize="11" Foreground="#cad3f5"/>
                            </Grid>
                        </StackPanel>
                    </Grid>
                </Border>
            </Grid>
            <Grid Grid.Row="1" Margin="0,15,0,0">
                <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                <Border Name="sidebarBorder" Grid.Column="0" Width="180" Background="#1e2030" BorderBrush="#494d64" BorderThickness="1" CornerRadius="5" Margin="0,0,10,0" Visibility="Collapsed">
                    <Grid>
                        <Grid.RowDefinitions><RowDefinition Height="30"/><RowDefinition Height="*"/></Grid.RowDefinitions>
                        <Border Grid.Row="0" Background="#181926" BorderBrush="#494d64" BorderThickness="0,0,0,1" CornerRadius="5,5,0,0">
                            <TextBlock Text="SESSION HISTORY" VerticalAlignment="Center" HorizontalAlignment="Center" FontSize="10" FontWeight="Bold" Foreground="#a5adcb"/>
                        </Border>
                        <ScrollViewer Name="sidebarScrollViewer" Grid.Row="1" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="8,8,5,8">
                            <StackPanel Name="thumbnailStack"/>
                        </ScrollViewer>
                    </Grid>
                </Border>
                <Border Grid.Column="1" Background="#1e2030" BorderBrush="#494d64" BorderThickness="1" CornerRadius="5">
                    <Grid>
                        <Image Name="pictureBox" Stretch="Uniform" Margin="10">
                            <Image.ContextMenu>
                                <ContextMenu>
                                    <MenuItem Name="copyMenuItem" Header="Copy to Clipboard"/>
                                </ContextMenu>
                            </Image.ContextMenu>
                        </Image>
                        <ListBox Name="elementsListBox" Width="170" HorizontalAlignment="Right" Visibility="Collapsed"/>
                    </Grid>
                </Border>
            </Grid>
            <Border Grid.Row="2" Height="30" Margin="0,15,0,0" Background="#181926" BorderBrush="#494d64" BorderThickness="1" CornerRadius="3">
                <Grid Margin="10,0">
                    <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                    <TextBlock Name="statusLabel" Grid.Column="0" Text="Ready to Capture ..." VerticalAlignment="Center" FontWeight="SemiBold" FontSize="11" Foreground="#b8c0e0"/>
                    <TextBlock Name="clipboardStatusLabel" Grid.Column="1" Text="" Foreground="#8bd5ca" FontWeight="Bold" FontSize="11" VerticalAlignment="Center"/>
                </Grid>
            </Border>
        </Grid>
    </Grid>
</Window>
'@

# Parse XAML safely
 $xmlReader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
try {
    $window = [System.Windows.Markup.XamlReader]::Load($xmlReader)
} finally {
    $xmlReader.Dispose()
}

 $captureButton = $window.FindName("captureButton"); $continuousModeButton = $window.FindName("continuousModeButton")
 $openButton = $window.FindName("openButton"); $openFolderButton = $window.FindName("openFolderButton")
 $fullScreenCheckbox = $window.FindName("fullScreenCheckbox"); $mouseCursorCheckbox = $window.FindName("mouseCursorCheckbox")
 $mouseHighlightCheckbox = $window.FindName("mouseHighlightCheckbox"); $showOutlineCheckbox = $window.FindName("showOutlineCheckbox")
 $screenshotBorderCheckbox = $window.FindName("screenshotBorderCheckbox"); $colorButton = $window.FindName("colorButton")
 $colorSquare = $window.FindName("colorSquare"); $outlineWidthSlider = $window.FindName("outlineWidthSlider")
 $opacitySlider = $window.FindName("opacitySlider"); $mouseHighlightColorButton = $window.FindName("mouseHighlightColorButton")
 $mouseColorSquare = $window.FindName("mouseColorSquare"); $mouseHighlightSizeSlider = $window.FindName("mouseHighlightSizeSlider")
 $mouseOpacitySlider = $window.FindName("mouseOpacitySlider"); $statusLabel = $window.FindName("statusLabel")
 $pictureBox = $window.FindName("pictureBox"); $copyMenuItem = $window.FindName("copyMenuItem")
 $elementsListBox = $window.FindName("elementsListBox"); $sidebarBorder = $window.FindName("sidebarBorder")
 $thumbnailStack = $window.FindName("thumbnailStack"); $clipboardStatusLabel = $window.FindName("clipboardStatusLabel")
 $btnMin = $window.FindName("btnMin"); $btnClose = $window.FindName("btnClose")
 $sidebarScrollViewer = $window.FindName("sidebarScrollViewer")

# Custom Smooth Slow Scroll for Sidebar
 $sidebarScrollViewer.Add_PreviewMouseWheel({
    param($sender, $e)
    $e.Handled = $true
    $scrollAmount = 40 # Lower this number to make it slower
    if ($e.Delta -gt 0) {
        $targetOffset = $sender.VerticalOffset - $scrollAmount
        if ($targetOffset -lt 0) { $targetOffset = 0 }
        $sender.ScrollToVerticalOffset($targetOffset)
    } elseif ($e.Delta -lt 0) {
        $sender.ScrollToVerticalOffset($sender.VerticalOffset + $scrollAmount)
    }
})

# ==============================================================================
# SECTION 4: NATIVE TITLE BAR ICON ASSIGNMENT
# ==============================================================================
 $window.add_SourceInitialized({
    try {
        $bytes = [Convert]::FromBase64String($icon)
        $ms = New-Object System.IO.MemoryStream($bytes, 0, $bytes.Length)
        $drawingIcon = New-Object System.Drawing.Icon($ms)
        $hWnd = (New-Object System.Windows.Interop.WindowInteropHelper $window).Handle
        [Win32]::SendMessage($hWnd, [Win32]::WM_SETICON, [Win32]::ICON_SMALL, $drawingIcon.Handle) | Out-Null
        $drawingIcon.Dispose()
        $ms.Dispose()
    } catch {
        Write-DebugLog "Failed to set title bar icon: $_"
    }
})

# Window Control Button Bindings
 $btnMin.add_Click({ $window.WindowState = [System.Windows.WindowState]::Minimized })
 $btnClose.add_Click({ $window.Close() })

function Get-WpfBrush {
    param([System.Drawing.Color]$drawingColor)
    $mediaColor = [System.Windows.Media.Color]::FromRgb($drawingColor.R, $drawingColor.G, $drawingColor.B)
    return New-Object System.Windows.Media.SolidColorBrush($mediaColor)
}

function Convert-BitmapToWpfSource {
    param([System.Drawing.Bitmap]$bitmap)
    $ms = New-Object System.IO.MemoryStream
    $bitmap.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $ms.Position = 0
    $bi = New-Object System.Windows.Media.Imaging.BitmapImage
    $bi.BeginInit()
    $bi.StreamSource = $ms
    $bi.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $bi.EndInit()
    $bi.Freeze()
    $ms.Dispose() # Properly dispose memory stream
    return $bi
}

# Custom Themed Message Box
function Show-ThemedMessageBox {
    param([string]$Message, [string]$Title = "Information", $Owner = $null)
    $dlg = [System.Windows.Window]::new()
    $dlg.Title = $Title
    $dlg.Width = 400
    $dlg.Height = 150
    $dlg.WindowStyle = "None"
    $dlg.ResizeMode = "NoResize"
    $dlg.WindowStartupLocation = "CenterOwner"
    if ($Owner) { $dlg.Owner = $Owner }
    $dlg.Background = (New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(36, 39, 58)))

    $chrome = [System.Windows.Shell.WindowChrome]::new()
    $chrome.CaptionHeight = 32
    $chrome.CornerRadius = [System.Windows.CornerRadius]::new(0)
    $chrome.GlassFrameThickness = [System.Windows.Thickness]::new(0)
    $chrome.UseAeroCaptionButtons = $false
    [System.Windows.Shell.WindowChrome]::SetWindowChrome($dlg, $chrome)

    $mainBorder = [System.Windows.Controls.Border]::new()
    $mainBorder.BorderBrush = (New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(73, 77, 100)))
    $mainBorder.BorderThickness = [System.Windows.Thickness]::new(1)
    $mainBorder.Background = (New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(36, 39, 58)))

    $root = [System.Windows.Controls.Grid]::new()
    $r0 = [System.Windows.Controls.RowDefinition]::new(); $r0.Height = [System.Windows.GridLength]::new(32)
    $r1 = [System.Windows.Controls.RowDefinition]::new(); $r1.Height = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $null = $root.RowDefinitions.Add($r0); $null = $root.RowDefinitions.Add($r1)

    $titleBar = [System.Windows.Controls.Grid]::new()
    $titleBar.Background = (New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(24, 25, 38)))
    [System.Windows.Controls.Grid]::SetRow($titleBar, 0)

    $titleText = [System.Windows.Controls.TextBlock]::new()
    $titleText.Text = $Title
    $titleText.Foreground = (New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(202, 211, 245)))
    $titleText.VerticalAlignment = "Center"
    $titleText.Margin = [System.Windows.Thickness]::new(10,0,0,0)
    $null = $titleBar.Children.Add($titleText)

    $btnClose = [System.Windows.Controls.Button]::new()
    $btnClose.Content = "✕"
    $btnClose.Width = 46
    $btnClose.Height = 32
    $btnClose.FontSize = 12
    $btnClose.FontFamily = [System.Windows.Media.FontFamily]::new("Segoe UI")
    $btnClose.HorizontalAlignment = "Right"
    $btnClose.VerticalAlignment = "Top"
    $btnClose.Foreground = (New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(202, 211, 245)))
    
    $closeTemplate = [System.Windows.Markup.XamlReader]::Parse(@"
<ControlTemplate TargetType="Button" xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
    <Border x:Name="bd" Background="#181926">
        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
    </Border>
    <ControlTemplate.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
            <Setter TargetName="bd" Property="Background" Value="#ed8796"/>
            <Setter Property="Foreground" Value="White"/>
        </Trigger>
    </ControlTemplate.Triggers>
</ControlTemplate>
"@)
    $btnClose.Template = $closeTemplate
    [System.Windows.Shell.WindowChrome]::SetIsHitTestVisibleInChrome($btnClose, $true)
    $btnClose.Add_Click({ $dlg.Close() })
    $null = $titleBar.Children.Add($btnClose)
    $null = $root.Children.Add($titleBar)

    $contentPanel = [System.Windows.Controls.StackPanel]::new()
    [System.Windows.Controls.Grid]::SetRow($contentPanel, 1)
    $contentPanel.Margin = [System.Windows.Thickness]::new(15)
    $contentPanel.VerticalAlignment = "Center"

    $msgText = [System.Windows.Controls.TextBlock]::new()
    $msgText.Text = $Message
    $msgText.Foreground = (New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(202, 211, 245)))
    $msgText.TextWrapping = "Wrap"
    $msgText.Margin = [System.Windows.Thickness]::new(0,0,0,15)
    $null = $contentPanel.Children.Add($msgText)

    $btnOk = [System.Windows.Controls.Button]::new()
    $btnOk.Content = "OK"
    $btnOk.Width = 80
    $btnOk.Height = 28
    $btnOk.HorizontalAlignment = "Right"
    $btnOk.Background = (New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(138, 173, 244)))
    $btnOk.Foreground = (New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(36, 39, 58)))
    $btnOk.BorderThickness = [System.Windows.Thickness]::new(0)
    $btnOk.FontWeight = "SemiBold"
    $btnOk.IsDefault = $true
    $btnOk.IsCancel = $true
    
    $okTemplate = [System.Windows.Markup.XamlReader]::Parse(@"
<ControlTemplate TargetType="Button" xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
    <Border x:Name="bd" Background="{TemplateBinding Background}" CornerRadius="4">
        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
    </Border>
    <ControlTemplate.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
            <Setter TargetName="bd" Property="Opacity" Value="0.85"/>
        </Trigger>
    </ControlTemplate.Triggers>
</ControlTemplate>
"@)
    $btnOk.Template = $okTemplate
    $btnOk.Add_Click({ $dlg.DialogResult = $true; $dlg.Close() })
    $null = $contentPanel.Children.Add($btnOk)

    $null = $root.Children.Add($contentPanel)

    $mainBorder.Child = $root
    $dlg.Content = $mainBorder

    $dlg.ShowDialog() | Out-Null
}

function Load-Settings {
    try {
        $settings = Import-IniFile -FilePath $iniPath
        if ($null -ne $settings) {
            if ($null -ne $settings.General) {
                if ($null -ne $settings.General.FullScreen) { $fullScreenCheckbox.IsChecked = [System.Convert]::ToBoolean($settings.General.FullScreen) }
                if ($null -ne $settings.General.ShowCursor) { $mouseCursorCheckbox.IsChecked = [System.Convert]::ToBoolean($settings.General.ShowCursor) }
                if ($null -ne $settings.General.ShowHighlight) { $mouseHighlightCheckbox.IsChecked = [System.Convert]::ToBoolean($settings.General.ShowHighlight) }
                if ($null -ne $settings.General.ShowOutline) { $showOutlineCheckbox.IsChecked = [System.Convert]::ToBoolean($settings.General.ShowOutline) }
                if ($null -ne $settings.General.ScreenshotBorder) { $screenshotBorderCheckbox.IsChecked = [System.Convert]::ToBoolean($settings.General.ScreenshotBorder) }
            }
            if ($null -ne $settings.Sliders) {
                if ($null -ne $settings.Sliders.OutlineWidth) { $outlineWidthSlider.Value = [double]$settings.Sliders.OutlineWidth }
                if ($null -ne $settings.Sliders.Opacity) { $opacitySlider.Value = [double]$settings.Sliders.Opacity }
                if ($null -ne $settings.Sliders.HighlightSize) { $mouseHighlightSizeSlider.Value = [double]$settings.Sliders.HighlightSize }
                if ($null -ne $settings.Sliders.HighlightOpacity) { $mouseOpacitySlider.Value = [double]$settings.Sliders.HighlightOpacity }
            }
            if ($null -ne $settings.Colors) {
                if ($null -ne $settings.Colors.OutlineColor) {
                    $global:outlineColor = [System.Drawing.Color]::FromArgb([int]$settings.Colors.OutlineColor)
                    $colorSquare.Background = Get-WpfBrush $global:outlineColor
                }
                if ($null -ne $settings.Colors.HighlightColor) {
                    $global:mouseHighlightColor = [System.Drawing.Color]::FromArgb([int]$settings.Colors.HighlightColor)
                    $mouseColorSquare.Background = Get-WpfBrush $global:mouseHighlightColor
                }
            }
        }
    } catch { Write-Warning "Configuration failed to load: $_" }
}

function Save-Settings {
    try {
        $data = [PSCustomObject]@{
            General = [PSCustomObject]@{
                FullScreen = $fullScreenCheckbox.IsChecked.ToString(); ShowCursor = $mouseCursorCheckbox.IsChecked.ToString()
                ShowHighlight = $mouseHighlightCheckbox.IsChecked.ToString(); ShowOutline = $showOutlineCheckbox.IsChecked.ToString()
                ScreenshotBorder = $screenshotBorderCheckbox.IsChecked.ToString()
            }
            Sliders = [PSCustomObject]@{
                OutlineWidth = $outlineWidthSlider.Value.ToString(); Opacity = $opacitySlider.Value.ToString()
                HighlightSize = $mouseHighlightSizeSlider.Value.ToString(); HighlightOpacity = $mouseOpacitySlider.Value.ToString()
            }
            Colors = [PSCustomObject]@{
                OutlineColor = $global:outlineColor.ToArgb().ToString(); HighlightColor = $global:mouseHighlightColor.ToArgb().ToString()
            }
        }
        Out-IniFile -FilePath $iniPath -Data $data
    } catch { Write-Warning "Failed to save configuration settings: $_" }
}

Load-Settings

# ==============================================================================
# SECTION 5: SIDEBAR HISTORY COMPILER
# ==============================================================================
function Add-ThumbnailToSidebar {
    param([string]$ImagePath, [System.Windows.Media.Imaging.BitmapImage]$WpfImage)
    Write-DebugLog "Compiling sidebar thumbnail card for counter index: $global:captureCounter"
    if ($sidebarBorder.Visibility -eq [System.Windows.Visibility]::Collapsed) {
        $sidebarBorder.Visibility = [System.Windows.Visibility]::Visible
        Write-DebugLog "Revealed session history sidebar."
    }
    $thumbImage = New-Object System.Windows.Controls.Image
    $thumbImage.Source = $WpfImage; $thumbImage.Height = 100; $thumbImage.Stretch = [System.Windows.Media.Stretch]::Uniform; $thumbImage.Margin = "5"
    $thumbText = New-Object System.Windows.Controls.TextBlock
    $thumbText.Text = "Screenshot #$($global:captureCounter - 1)"; $thumbText.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
    $thumbText.FontSize = 10; $thumbText.FontWeight = [System.Windows.FontWeights]::SemiBold; $thumbText.Foreground = (New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(184, 192, 224))); $thumbText.Margin = "0,2,0,5"
    $itemStack = New-Object System.Windows.Controls.StackPanel
    $itemStack.Children.Add($thumbImage) | Out-Null; $itemStack.Children.Add($thumbText) | Out-Null
    $itemBorder = New-Object System.Windows.Controls.Border
    $itemBorder.BorderBrush = (New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(73, 77, 100))); $itemBorder.BorderThickness = "1"; $itemBorder.CornerRadius = "4"
    $itemBorder.Background = (New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(36, 39, 58))); $itemBorder.Margin = "0,0,0,10"; $itemBorder.Cursor = [System.Windows.Input.Cursors]::Hand
    $itemBorder.Child = $itemStack; $itemBorder.Tag = $ImagePath
    $itemBorder.add_MouseEnter({
        $this.BorderBrush = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(138, 173, 244))
        $this.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(54, 58, 79))
    })
    $itemBorder.add_MouseLeave({
        $this.BorderBrush = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(73, 77, 100))
        $this.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(36, 39, 58))
    })
    $itemBorder.add_MouseLeftButtonDown({
        try {
            $targetPath = $this.Tag
            Write-DebugLog "Sidebar thumbnail card click recorded. Target path to load: $targetPath"
            $previewImage = New-Object System.Windows.Media.Imaging.BitmapImage
            $previewImage.BeginInit(); $previewImage.UriSource = New-Object System.Uri($targetPath, [System.UriKind]::Absolute)
            $previewImage.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad; $previewImage.EndInit(); $previewImage.Freeze()
            $pictureBox.Source = $previewImage
            try {
                [System.Windows.Clipboard]::SetImage($previewImage)
                $clipboardStatusLabel.Text = "✅ Copy Auto-Saved to Clipboard!"
            } catch {
                $clipboardStatusLabel.Text = "⚠️ Clipboard Locked"
                Write-DebugLog "Clipboard lock exception in sidebar click: $_"
            }
            $global:lastCapturePath = $targetPath
            $statusLabel.Text = "Loaded and copied selected screenshot from session history."
            Write-DebugLog "Loaded preview successfully. Copied frame to clipboard."
        } catch {
            $statusLabel.Text = "Error loading capture: $_"
            Write-DebugLog "ERROR inside thumbnail click event: $_"
        }
    })
    $thumbnailStack.Children.Insert(0, $itemBorder) | Out-Null
}

# ==============================================================================
# SECTION 6: GRAPHICS CAPTURING HELPER OPERATIONS (CURSOR RENDERING)
# ==============================================================================
function Get-CursorInfo {
    try {
        $cursorInfo = New-Object Win32+CURSORINFO
        $cursorInfo.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf($cursorInfo)
        $success = [Win32]::GetCursorInfo([ref]$cursorInfo)
        if (-not $success) { throw "Failed to get cursor information" }
        return $cursorInfo
    } catch {
        Write-Error "Error getting cursor info: $_"
        return $null
    }
}

function Draw-Cursor {
    param($graphics, $cursorInfo, $offsetX = 0, $offsetY = 0)
    if ($global:showMouseCursor -and (([int]$cursorInfo.flags -band [Win32]::CURSOR_SHOWING) -eq [Win32]::CURSOR_SHOWING)) {
        $hdcGraphics = $graphics.GetHdc()
        [Win32]::DrawIcon($hdcGraphics, $cursorInfo.ptScreenPos.X - $offsetX, $cursorInfo.ptScreenPos.Y - $offsetY, $cursorInfo.hCursor)
        $graphics.ReleaseHdc($hdcGraphics)
    }
}

function Draw-CursorHighlight {
    param($graphics, $cursorInfo, $offsetX = 0, $offsetY = 0)
    if ($global:showMouseHighlight) {
        $highlightBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb($global:mouseHighlightOpacity, $global:mouseHighlightColor.R, $global:mouseHighlightColor.G, $global:mouseHighlightColor.B))
        $graphics.FillEllipse($highlightBrush, $cursorInfo.ptScreenPos.X - $offsetX - $global:mouseHighlightSize, $cursorInfo.ptScreenPos.Y - $offsetY - $global:mouseHighlightSize, $global:mouseHighlightSize * 2, $global:mouseHighlightSize * 2)
        $highlightBrush.Dispose()
    }
}

# ==============================================================================
# SECTION 7: WPF CONTROL EVENT BINDINGS
# ==============================================================================
 $mouseCursorCheckbox.add_Checked({ $global:showMouseCursor = $true })
 $mouseCursorCheckbox.add_Unchecked({ $global:showMouseCursor = $false })
 $mouseHighlightCheckbox.add_Checked({ $global:showMouseHighlight = $true })
 $mouseHighlightCheckbox.add_Unchecked({ $global:showMouseHighlight = $false })

 $colorButton.add_Click({
    $colorDialog = New-Object System.Windows.Forms.ColorDialog
    $colorDialog.Color = $global:outlineColor
    if ($colorDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $global:outlineColor = $colorDialog.Color
        $colorSquare.Background = Get-WpfBrush $global:outlineColor
    }
})

 $mouseHighlightColorButton.add_Click({
    $colorDialog = New-Object System.Windows.Forms.ColorDialog
    $colorDialog.Color = $global:mouseHighlightColor
    if ($colorDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $global:mouseHighlightColor = $colorDialog.Color
        $mouseColorSquare.Background = Get-WpfBrush $global:mouseHighlightColor
    }
})

 $openFolderButton.add_Click({
    if (Test-Path $global:sessionFolder) {
        Start-Process explorer.exe -ArgumentList $global:sessionFolder
    } else {
        Show-ThemedMessageBox -Message "Screenshots folder not found." -Title "Error" -Owner $window
    }
})

 $copyMenuItem.add_Click({
    if ($pictureBox.Source -ne $null) {
        try {
            [System.Windows.Clipboard]::SetImage($pictureBox.Source)
            $clipboardStatusLabel.Text = "✅ Copy Auto-Saved to Clipboard!"
        } catch {
            $clipboardStatusLabel.Text = "⚠️ Clipboard Locked"
            Write-DebugLog "Clipboard lock exception on manual copy: $_"
        }
    }
})

# ==============================================================================
# SECTION 8: CAPTURE INITIALIZATION & CORE RUNTIME TIMER
# ==============================================================================
 $captureButton.add_Click({
    try {
        if (-not $global:isCapturing -and -not $global:preparingCapture) {
            $global:preparingCapture = $true
            $captureButton.Content = "Cancel Capture"
            $captureButton.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(237, 135, 150))
            $statusLabel.Text = "Preparing capture..."
            Write-DebugLog "Started single capture routine."
            $window.WindowState = [System.Windows.WindowState]::Minimized
            if ($global:delayTimer) { $global:delayTimer.Stop() }
            $global:delayTimer = New-Object System.Windows.Threading.DispatcherTimer
            $global:delayTimer.Interval = [System.TimeSpan]::FromMilliseconds(300)
            $global:delayTimer.add_Tick({
                $global:delayTimer.Stop()
                $global:preparingCapture = $false
                $global:isCapturing = $true
                $global:wasMouseDown = $false
                $statusLabel.Text = "Capturing active... Click on target window."
                Write-DebugLog "Window minimized. Ready to capture click."
            })
            $global:delayTimer.Start()
        } else {
            $global:isCapturing = $false
            $global:preparingCapture = $false
            $captureButton.Content = "Single Capture"
            $captureButton.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(138, 173, 244))
            $statusLabel.Text = "Capture cancelled"
            $window.WindowState = [System.Windows.WindowState]::Normal
            $window.Activate()
            if ($global:delayTimer) { $global:delayTimer.Stop() }
            Write-DebugLog "Single capture cancelled."
        }
    } catch {
        $statusLabel.Text = "Error: $_"
        Write-DebugLog "ERROR inside Single Capture click: $_"
    }
})

 $continuousModeButton.add_Click({
    if (-not $global:continuousMode -and -not $global:preparingCapture) {
        $global:preparingCapture = $true
        $global:continuousMode = $true; $global:stopCapture = $false
        $continuousModeButton.Content = "Stop Capturing"; $captureButton.IsEnabled = $false
        $continuousModeButton.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(237, 135, 150))
        $statusLabel.Text = "Preparing continuous capture..."
        Write-DebugLog "Started continuous capture routine."
        Show-ThemedMessageBox -Message "Press the ESC button to stop recording." -Title "Continuous Capture" -Owner $window
        $window.WindowState = [System.Windows.WindowState]::Minimized
        if ($global:delayTimer) { $global:delayTimer.Stop() }
        $global:delayTimer = New-Object System.Windows.Threading.DispatcherTimer
        $global:delayTimer.Interval = [System.TimeSpan]::FromMilliseconds(300)
        $global:delayTimer.add_Tick({
            $global:delayTimer.Stop()
            $global:preparingCapture = $false
            $global:isCapturing = $true
            $global:wasMouseDown = $false
            $statusLabel.Text = "Continuous Capture active. Click on elements. Press ESC to stop."
            Write-DebugLog "Window minimized. Ready to capture continuous clicks."
        })
        $global:delayTimer.Start()
    } else {
        $global:stopCapture = $true; $global:continuousMode = $false; $global:isCapturing = $false; $global:preparingCapture = $false
        $continuousModeButton.Content = "Continuous Capture"; $captureButton.IsEnabled = $true
        $continuousModeButton.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(166, 218, 149))
        $window.WindowState = [System.Windows.WindowState]::Normal
        $window.Activate()
        $statusLabel.Text = "Saved to $screenshotPath"
        if ($global:delayTimer) { $global:delayTimer.Stop() }
        Write-DebugLog "Continuous capturing loop disabled."
    }
})

 $timer = New-Object System.Windows.Threading.DispatcherTimer
 $timer.Interval = [System.TimeSpan]::FromMilliseconds(50) # Reduced to 50ms for faster/more reliable click detection
 $timer.add_Tick({
    if ($global:isCapturing) {
        $escPressed = (([int][Win32]::GetAsyncKeyState(0x1B) -band 0x8000) -ne 0)
        if ($global:continuousMode -and $escPressed) {
            Write-DebugLog "Escape key press detected. Stopping continuous capturing loop."
            $global:stopCapture = $true; $global:isCapturing = $false; $global:continuousMode = $false
            $captureButton.Content = "Single Capture"; $continuousModeButton.Content = "Continuous Capture"
            $captureButton.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(138, 173, 244))
            $continuousModeButton.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(166, 218, 149))
            $captureButton.IsEnabled = $true
            $window.WindowState = [System.Windows.WindowState]::Normal
            $window.Activate()
            $statusLabel.Text = "Saved to $screenshotPath"
            return
        }
        try {
            $isMouseDown = (([int][Win32]::GetAsyncKeyState(0x01) -band 0x8000) -ne 0)
            if ($isMouseDown -and -not $global:wasMouseDown) {
                $global:wasMouseDown = $true
                $cursorPoint = New-Object Win32+Point
                [Win32]::GetCursorPos([ref]$cursorPoint) | Out-Null
                Write-DebugLog "[DPI INFO] Raw Mouse Click Coordinate Intercepted: X=$($cursorPoint.X), Y=$($cursorPoint.Y)"
                $hwnd = [Win32]::WindowFromPoint($cursorPoint)
                if ($hwnd -eq [IntPtr]::Zero) { throw "Invalid window handle" }
                $cursorInfo = Get-CursorInfo
                $outlineWidth = [int]$outlineWidthSlider.Value
                $opacityVal = [int]($opacitySlider.Value * 2.55)
                $global:mouseHighlightSize = [int]$mouseHighlightSizeSlider.Value
                $global:mouseHighlightOpacity = [int]($mouseOpacitySlider.Value * 2.55)
                $pen = $null; $screenshot = $null; $graphics = $null
                
                try {
                    # Unify Window Bounds Fetching (DWMWA_EXTENDED_FRAME_BOUNDS)
                    $rootHwnd = [Win32]::GetAncestor($hwnd, [Win32]::GA_ROOT)
                    $rootRect = New-Object Win32+RECT
                    $rectSize = [System.Runtime.InteropServices.Marshal]::SizeOf([type][Win32+RECT])
                    $dwmStatus = [Win32]::DwmGetWindowAttribute($rootHwnd, [Win32]::DWMWA_EXTENDED_FRAME_BOUNDS, [ref]$rootRect, $rectSize)
                    if ($dwmStatus -ne 0) {
                        [Win32]::GetWindowRect($rootHwnd, [ref]$rootRect) | Out-Null
                    }
                    $winWidth = $rootRect.Right - $rootRect.Left
                    $winHeight = $rootRect.Bottom - $rootRect.Top
                    
                    if ($winWidth -le 0 -or $winHeight -le 0) { throw "Invalid window dimensions calculated (${winWidth}x${winHeight})." }

                    if ($fullScreenCheckbox.IsChecked) {
                        # IMPROVEMENT: Use the actual screen the window resides on for accurate multi-monitor full-screen capture.
                        $targetScreen = [System.Windows.Forms.Screen]::FromHandle($hwnd)
                        $bounds = $targetScreen.Bounds
                        $physicalW = $bounds.Width; $physicalH = $bounds.Height
                        $screenOffsetX = $bounds.X; $screenOffsetY = $bounds.Y
                        
                        Write-DebugLog "[DPI INFO] Executing Full-Screen Capture. Target Monitor Bounds: X=$screenOffsetX, Y=$screenOffsetY, W=$physicalW, H=$physicalH"
                        $screenshot = New-Object System.Drawing.Bitmap ($physicalW, $physicalH)
                        $graphics = [System.Drawing.Graphics]::FromImage($screenshot)
                        $graphics.CopyFromScreen($screenOffsetX, $screenOffsetY, 0, 0, [System.Drawing.Size]::new($physicalW, $physicalH))
                        
                        if ($showOutlineCheckbox.IsChecked -and $outlineWidth -gt 0) {
                            $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb($opacityVal, $global:outlineColor.R, $global:outlineColor.G, $global:outlineColor.B), $outlineWidth)
                            $pen.Alignment = [System.Drawing.Drawing2D.PenAlignment]::Inset
                            
                            # FIX: Inset draws entirely inside the boundary, cleanly preventing clipping
                            $adjustedX = $rootRect.Left - $screenOffsetX
                            $adjustedY = $rootRect.Top - $screenOffsetY
                            $graphics.DrawRectangle($pen, $adjustedX, $adjustedY, $winWidth - 1, $winHeight - 1)
                        }
                        Draw-CursorHighlight $graphics $cursorInfo $screenOffsetX $screenOffsetY
                        Draw-Cursor $graphics $cursorInfo $screenOffsetX $screenOffsetY
                    } else {
                        Write-DebugLog "[DPI INFO] Executing Window-Only Capture. Detected Bounds: X=$($rootRect.Left), Y=$($rootRect.Top), W=$winWidth, H=$winHeight"
                        $screenshot = New-Object System.Drawing.Bitmap ($winWidth, $winHeight)
                        $graphics = [System.Drawing.Graphics]::FromImage($screenshot)
                        $graphics.CopyFromScreen($rootRect.Left, $rootRect.Top, 0, 0, $screenshot.Size)
                        
                        if ($showOutlineCheckbox.IsChecked -and $outlineWidth -gt 0) {
                            $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb($opacityVal, $global:outlineColor.R, $global:outlineColor.G, $global:outlineColor.B), $outlineWidth)
                            $pen.Alignment = [System.Drawing.Drawing2D.PenAlignment]::Inset
                            
                            # FIX: Inset draws entirely inside the boundary, cleanly preventing clipping
                            $graphics.DrawRectangle($pen, 0, 0, $winWidth - 1, $winHeight - 1)
                        }
                        Draw-CursorHighlight $graphics $cursorInfo $rootRect.Left $rootRect.Top
                        Draw-Cursor $graphics $cursorInfo $rootRect.Left $rootRect.Top
                    }
                    if ($screenshotBorderCheckbox.IsChecked) {
                        $outerPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::Black, 2)
                        $outerPen.Alignment = [System.Drawing.Drawing2D.PenAlignment]::Inset
                        # FIX: Inset draws cleanly on the extreme outer edge without clipping
                        $graphics.DrawRectangle($outerPen, 0, 0, $screenshot.Width - 1, $screenshot.Height - 1)
                        $outerPen.Dispose()
                    }
                    $wpfImage = Convert-BitmapToWpfSource $screenshot
                    $pictureBox.Source = $wpfImage
                    $paddedCounter = "{0:D2}" -f $global:captureCounter
                    $global:lastCapturePath = Join-Path $global:sessionFolder "$paddedCounter-$(Get-Date -Format 'yy.MM.dd_HH.mm.ss').png"
                    $screenshot.Save($global:lastCapturePath, [System.Drawing.Imaging.ImageFormat]::Png)
                    Write-DebugLog "Saved capture #$global:captureCounter to path: $global:lastCapturePath"
                    
                    try {
                        [System.Windows.Clipboard]::SetImage($wpfImage)
                        $clipboardStatusLabel.Text = "✅ Copy Auto-Saved to Clipboard!"
                    } catch {
                        $clipboardStatusLabel.Text = "⚠️ Clipboard Locked"
                        Write-DebugLog "Clipboard lock exception on capture: $_"
                    }
                    
                    $global:captureCounter++
                    Add-ThumbnailToSidebar -ImagePath $global:lastCapturePath -WpfImage $wpfImage
                    $className = New-Object System.Text.StringBuilder 256
                    [Win32]::GetClassName($hwnd, $className, 256) | Out-Null
                    $elementsListBox.Items.Clear()
                    $elementsListBox.Items.Add("Element Details:") | Out-Null
                    $elementsListBox.Items.Add("Class: $($className.ToString())") | Out-Null
                    $elementsListBox.Items.Add("Position: $($cursorPoint.X),$($cursorPoint.Y)") | Out-Null
                } finally {
                    if ($null -ne $graphics) { $graphics.Dispose() }
                    if ($null -ne $pen) { $pen.Dispose() }
                    if ($null -ne $screenshot) { $screenshot.Dispose() }
                }
                if (-not $global:continuousMode) {
                    $global:isCapturing = $false; $captureButton.Content = "Single Capture"; $openButton.IsEnabled = $true
                    $captureButton.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(138, 173, 244))
                    $window.WindowState = [System.Windows.WindowState]::Normal
                    $window.Activate()
                    $window.Topmost = $true
                    $window.Topmost = $false
                    $statusLabel.Text = "Saved to $screenshotPath"
                } else {
                    $openButton.IsEnabled = $true; $statusLabel.Text = "Saved to $screenshotPath"
                }
            } elseif (-not $isMouseDown) {
                $global:wasMouseDown = $false
            }
        } catch {
            $errorMessage = $_.Exception.Message
            $statusLabel.Text = "Capture error: $errorMessage"
            Write-DebugLog "ERROR within active capture loop: $errorMessage"
            if (-not $global:continuousMode) {
                $global:isCapturing = $false; $captureButton.Content = "Single Capture"
                $captureButton.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(138, 173, 244))
                $window.WindowState = [System.Windows.WindowState]::Normal
                $window.Activate()
                $window.Topmost = $true
                $window.Topmost = $false
            }
        }
    }
})
 $timer.Start()

# ==============================================================================
# SECTION 10: PREVIEW ACTIONS & DISMISSAL
# ==============================================================================
 $openButton.add_Click({
    try {
        if ($global:lastCapturePath -and (Test-Path $global:lastCapturePath)) {
            $pictureBox.Source = New-Object System.Windows.Media.Imaging.BitmapImage (New-Object System.Uri $global:lastCapturePath)
            $statusLabel.Text = "Showing capture: $($global:lastCapturePath)"
            $window.WindowState = [System.Windows.WindowState]::Normal
            $window.Activate()
            Start-Process -FilePath $global:lastCapturePath
        } else {
            $statusLabel.Text = "No capture file found"
        }
    } catch {
        $statusLabel.Text = "Error opening capture: $_"
    }
})

 $window.add_Closing({
    Save-Settings
    $timer.Stop()
    if ($global:delayTimer) { $global:delayTimer.Stop() }
    $global:continuousMode = $false
    $global:stopCapture = $true
    Write-DebugLog "PSR++ application exiting."
})

 $window.ShowDialog() | Out-Null
