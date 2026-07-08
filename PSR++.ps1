# ==============================================================================
# PROGRAM: Problem Step Recorder Plus (PSR++)
# PLATFORM: Windows PowerShell 5.1+ & Windows Presentation Foundation (WPF)
# DESCRIPTION: A high-performance screen capturing utility optimized for secure,
#              rapid step-recording and visual software audits. Features an
#              interactive session preview sidebar and automatic clipboard copying.
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
 $global:outlineColor = [System.Drawing.Color]::FromArgb(0, 255, 0); $global:delayTimer = $null
 $global:continuousMode = $false; $global:stopCapture = $false
 $global:mouseHighlightColor = [System.Drawing.Color]::FromArgb(255, 165, 0)
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
 $icon = "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tAAONbQADjW0hw41tLUONbQODjW0ALu7uwC7u7sfu7u74Lu7u/+7u7v/uLi4/6enp/+lpaX/pqam6aamplinp6cBETu8AAs3vVkLN739Cze9/ws3vf8LN72uCze9BAs3vQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAONbQADjW0KA41tOUONbSQDjW0AQ41tAAAAAAAvLy8ALy8vB+8vLzgvLy8/729vf+6urr/qKio/6ampv+np6f/pqam6aKiolgALswACje/bgo3v/8KN7//Cje//wo3v6EKN74BCje/AAAAAAAAAAAAAAAAAAAAAAAAAAAADjW0AA41tAAONbRlDjW07Q41tDkONbQAAAAAAAAAAAC+vr4Avr6+H76+vuC+vr7/vr6+/7u7u/2pqan8p6en/6enp/+kpKT/m5ub542NjVQJN8GZCTfC/wk3wv8JN8L/CTfBhgk3wgAJN8EAAAAAAAAAAAAAAAAAAAAAAAAAAAAONbQADjW0AA41tKAONbTGDjW0DQ41tAAAAAAAAAAAAL+/vwC/v78fv7+/4b+/v/+/v7//wMDA/8fHx//JycnftLS0Taenp8ioqKj/p6en/6SkpP+enp7/lZWV/4mJiP9wdYP7GEG5+Ac3xf8IOMT/CDjE/wg4xP8IOMT/CDjEdgg4xAAJN8QAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA41tAAONbQDDjW0qA41tP8ONbRxDjW0AA41tAAAAAAAAAAAAAAAAAAAAAAAAAAAAMDAwADAwMAewMDA4cDAwP/AwMD/wMDA/8HBwf/b29v/5ubm/+SwGf/8B/A//8DwAf///+D4f/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////8="
function Get-WpfIcon {
    param([string]$base64String)
    $bytes = [Convert]::FromBase64String($base64String)
    $ms = New-Object System.IO.MemoryStream($bytes, 0, $bytes.Length)
    $bi = New-Object System.Windows.Media.Imaging.BitmapImage
    $bi.BeginInit(); $bi.StreamSource = $ms; $bi.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad; $bi.EndInit(); $bi.Freeze()
    $ms.Close()
    return $bi
}
 $xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="PSR++" Height="700" Width="1050" MaxWidth="{Binding Source={x:Static SystemParameters.WorkArea}, Path=Width}" MaxHeight="{Binding Source={x:Static SystemParameters.WorkArea}, Path=Height}" WindowStartupLocation="CenterScreen" Background="#F5F5F5" ResizeMode="CanMinimize" UseLayoutRounding="True" SnapsToDevicePixels="True">
    <Grid Margin="20">
        <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
        <Grid Grid.Row="0">
            <Grid.ColumnDefinitions><ColumnDefinition Width="250"/><ColumnDefinition Width="250"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
            <Border Grid.Column="0" Background="White" BorderBrush="#E0E0E0" BorderThickness="1" CornerRadius="5" Padding="15" Margin="0,0,10,0">
                <StackPanel>
                    <Button Name="captureButton" Content="Single Capture" Height="25" Margin="0,0,0,5" Background="#007AFF" Foreground="White" BorderThickness="0" FontWeight="SemiBold"/>
                    <Button Name="continuousModeButton" Content="Continuous Capture" Height="25" Margin="0,0,0,5" Background="#34C759" Foreground="White" BorderThickness="0" FontWeight="SemiBold"/>
                    <Grid Height="25">
                        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="10"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                        <Button Grid.Column="0" Name="openButton" Content="Open Last" IsEnabled="False"/>
                        <Button Grid.Column="2" Name="openFolderButton" Content="Open Folder"/>
                    </Grid>
                </StackPanel>
            </Border>
            <Border Grid.Column="1" Background="White" BorderBrush="#E0E0E0" BorderThickness="1" CornerRadius="5" Padding="15" Margin="0,0,10,0">
                <StackPanel VerticalAlignment="Center">
                    <CheckBox Name="fullScreenCheckbox" Content="Capture Full Screen" Margin="0,0,0,4"/>
                    <CheckBox Name="mouseCursorCheckbox" Content="Show Mouse Cursor" IsChecked="True" Margin="0,0,0,4"/>
                    <CheckBox Name="mouseHighlightCheckbox" Content="Show Mouse Highlight" IsChecked="True" Margin="0,0,0,4"/>
                    <CheckBox Name="showOutlineCheckbox" Content="Show Window Outline" IsChecked="True" Margin="0,0,0,4"/>
                    <CheckBox Name="screenshotBorderCheckbox" Content="Add Outer Border (2px Black)" IsChecked="True"/>
                </StackPanel>
            </Border>
            <Border Grid.Column="2" Background="White" BorderBrush="#E0E0E0" BorderThickness="1" CornerRadius="5" Padding="15">
                <Grid>
                    <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="20"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                    <StackPanel Grid.Column="0">
                        <Grid Margin="0,0,0,5">
                            <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="30"/></Grid.ColumnDefinitions>
                            <Button Grid.Column="0" Name="colorButton" Content="Outline Color" Width="90" Height="24" HorizontalAlignment="Left"/>
                            <Border Grid.Column="2" Name="colorSquare" Width="24" Height="24" BorderBrush="Gray" BorderThickness="1" Background="Lime"/>
                        </Grid>
                        <Grid Margin="0,0,0,5">
                            <Grid.ColumnDefinitions><ColumnDefinition Width="80"/><ColumnDefinition Width="*"/><ColumnDefinition Width="30"/></Grid.ColumnDefinitions>
                            <TextBlock Grid.Column="0" Text="Outline Width:" VerticalAlignment="Center" FontSize="11"/>
                            <Slider Grid.Column="1" Name="outlineWidthSlider" Minimum="0" Maximum="50" Value="5" VerticalAlignment="Center"/>
                            <TextBlock Grid.Column="2" Text="{Binding ElementName=outlineWidthSlider, Path=Value, StringFormat={}{0:N0}}" VerticalAlignment="Center" HorizontalAlignment="Right" FontSize="11"/>
                        </Grid>
                        <Grid>
                            <Grid.ColumnDefinitions><ColumnDefinition Width="80"/><ColumnDefinition Width="*"/><ColumnDefinition Width="30"/></Grid.ColumnDefinitions>
                            <TextBlock Grid.Column="0" Text="Opacity:" VerticalAlignment="Center" FontSize="11"/>
                            <Slider Grid.Column="1" Name="opacitySlider" Minimum="0" Maximum="100" Value="80" VerticalAlignment="Center"/>
                            <TextBlock Grid.Column="2" Text="{Binding ElementName=opacitySlider, Path=Value, StringFormat={}{0:N0}}" VerticalAlignment="Center" HorizontalAlignment="Right" FontSize="11"/>
                        </Grid>
                    </StackPanel>
                    <StackPanel Grid.Column="2">
                        <Grid Margin="0,0,0,5">
                            <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="30"/></Grid.ColumnDefinitions>
                            <Button Grid.Column="0" Name="mouseHighlightColorButton" Content="Highlight Color" Width="95" Height="24" HorizontalAlignment="Left"/>
                            <Border Grid.Column="2" Name="mouseColorSquare" Width="24" Height="24" BorderBrush="Gray" BorderThickness="1" Background="Orange"/>
                        </Grid>
                        <Grid Margin="0,0,0,5">
                            <Grid.ColumnDefinitions><ColumnDefinition Width="95"/><ColumnDefinition Width="*"/><ColumnDefinition Width="30"/></Grid.ColumnDefinitions>
                            <TextBlock Grid.Column="0" Text="Highlight Size:" VerticalAlignment="Center" FontSize="11"/>
                            <Slider Grid.Column="1" Name="mouseHighlightSizeSlider" Minimum="5" Maximum="100" Value="50" VerticalAlignment="Center"/>
                            <TextBlock Grid.Column="2" Text="{Binding ElementName=mouseHighlightSizeSlider, Path=Value, StringFormat={}{0:N0}}" VerticalAlignment="Center" HorizontalAlignment="Right" FontSize="11"/>
                        </Grid>
                        <Grid>
                            <Grid.ColumnDefinitions><ColumnDefinition Width="95"/><ColumnDefinition Width="*"/><ColumnDefinition Width="30"/></Grid.ColumnDefinitions>
                            <TextBlock Grid.Column="0" Text="Highlight Opacity:" VerticalAlignment="Center" FontSize="11"/>
                            <Slider Grid.Column="1" Name="mouseOpacitySlider" Minimum="0" Maximum="100" Value="65" VerticalAlignment="Center"/>
                            <TextBlock Grid.Column="2" Text="{Binding ElementName=mouseOpacitySlider, Path=Value, StringFormat={}{0:N0}}" VerticalAlignment="Center" HorizontalAlignment="Right" FontSize="11"/>
                        </Grid>
                    </StackPanel>
                </Grid>
            </Border>
        </Grid>
        <Grid Grid.Row="1" Margin="0,15,0,0">
            <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
            <Border Name="sidebarBorder" Grid.Column="0" Width="180" Background="White" BorderBrush="#E0E0E0" BorderThickness="1" CornerRadius="5" Margin="0,0,10,0" Visibility="Collapsed">
                <Grid>
                    <Grid.RowDefinitions><RowDefinition Height="30"/><RowDefinition Height="*"/></Grid.RowDefinitions>
                    <Border Grid.Row="0" Background="#F9F9F9" BorderBrush="#E0E0E0" BorderThickness="0,0,0,1" CornerRadius="5,5,0,0">
                        <TextBlock Text="SESSION HISTORY" VerticalAlignment="Center" HorizontalAlignment="Center" FontSize="10" FontWeight="Bold" Foreground="#666666"/>
                    </Border>
                    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="8,8,5,8">
                        <StackPanel Name="thumbnailStack"/>
                    </ScrollViewer>
                </Grid>
            </Border>
            <Border Grid.Column="1" Background="White" BorderBrush="#E0E0E0" BorderThickness="1" CornerRadius="5">
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
        <Border Grid.Row="2" Height="30" Margin="0,15,0,0" Background="White" BorderBrush="#E0E0E0" BorderThickness="1" CornerRadius="3">
            <Grid Margin="10,0">
                <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                <TextBlock Name="statusLabel" Grid.Column="0" Text="Ready to Capture ..." VerticalAlignment="Center" FontWeight="SemiBold" FontSize="11"/>
                <TextBlock Name="clipboardStatusLabel" Grid.Column="1" Text="" Foreground="#007AFF" FontWeight="Bold" FontSize="11" VerticalAlignment="Center"/>
            </Grid>
        </Border>
    </Grid>
</Window>
'@
 $xmlReader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
 $window = [System.Windows.Markup.XamlReader]::Load($xmlReader)
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
 $window.Icon = Get-WpfIcon -base64String $icon
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
    $bi.BeginInit(); $bi.StreamSource = $ms; $bi.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad; $bi.EndInit(); $bi.Freeze()
    $ms.Close()
    return $bi
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
    $thumbText.FontSize = 10; $thumbText.FontWeight = [System.Windows.FontWeights]::SemiBold; $thumbText.Foreground = [System.Windows.Media.Brushes]::DimGray; $thumbText.Margin = "0,2,0,5"
    $itemStack = New-Object System.Windows.Controls.StackPanel
    $itemStack.Children.Add($thumbImage) | Out-Null; $itemStack.Children.Add($thumbText) | Out-Null
    $itemBorder = New-Object System.Windows.Controls.Border
    $itemBorder.BorderBrush = [System.Windows.Media.Brushes]::Gainsboro; $itemBorder.BorderThickness = "1"; $itemBorder.CornerRadius = "4"
    $itemBorder.Background = [System.Windows.Media.Brushes]::White; $itemBorder.Margin = "0,0,0,10"; $itemBorder.Cursor = [System.Windows.Input.Cursors]::Hand
    $itemBorder.Child = $itemStack; $itemBorder.Tag = $ImagePath
    $itemBorder.add_MouseEnter({
        $this.BorderBrush = [System.Windows.Media.Brushes]::LightBlue
        $this.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(245, 249, 255))
    })
    $itemBorder.add_MouseLeave({
        $this.BorderBrush = [System.Windows.Media.Brushes]::Gainsboro
        $this.Background = [System.Windows.Media.Brushes]::White
    })
    $itemBorder.add_MouseLeftButtonDown({
        try {
            $targetPath = $this.Tag
            Write-DebugLog "Sidebar thumbnail card click recorded. Target path to load: $targetPath"
            $previewImage = New-Object System.Windows.Media.Imaging.BitmapImage
            $previewImage.BeginInit(); $previewImage.UriSource = New-Object System.Uri($targetPath, [System.UriKind]::Absolute)
            $previewImage.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad; $previewImage.EndInit(); $previewImage.Freeze()
            $pictureBox.Source = $previewImage
            [System.Windows.Clipboard]::SetImage($previewImage)
            $global:lastCapturePath = $targetPath
            $clipboardStatusLabel.Text = "✅ Copy Auto-Saved to Clipboard!"
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
    if ($global:showMouseCursor -and ($cursorInfo.flags -band [Win32]::CURSOR_SHOWING) -eq [Win32]::CURSOR_SHOWING) {
        $hdcGraphics = $graphics.GetHdc()
        [Win32]::DrawIcon($hdcGraphics, $cursorInfo.ptScreenPos.X - $offsetX, $cursorInfo.ptScreenPos.Y - $offsetY, $cursorInfo.hCursor)
        $graphics.ReleaseHdc($hdcGraphics)
    }
}
function Draw-CursorHighlight {
    param($graphics, $cursorInfo, $offsetX = 0, $offsetY = 0)
    if ($global:showMouseHighlight) {
        $highlightBrush = New-Object Drawing.SolidBrush ([System.Drawing.Color]::FromArgb($global:mouseHighlightOpacity, $global:mouseHighlightColor.R, $global:mouseHighlightColor.G, $global:mouseHighlightColor.B))
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
        [System.Windows.MessageBox]::Show("Screenshots folder not found.", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
    }
})
 $copyMenuItem.add_Click({
    if ($pictureBox.Source -ne $null) { [System.Windows.Clipboard]::SetImage($pictureBox.Source) }
})
# ==============================================================================
# SECTION 8: CAPTURE INITIALIZATION & CORE RUNTIME TIMER
# ==============================================================================
 $captureButton.add_Click({
    try {
        if (-not $global:isCapturing) {
            $global:isCapturing = $true
            $global:wasMouseDown = $true
            $captureButton.Content = "Cancel Capture"
            $statusLabel.Text = "Preparing capture..."
            Write-DebugLog "Started single capture routine."
            if ($global:delayTimer) { $global:delayTimer.Stop() }
            $global:delayTimer = New-Object System.Windows.Threading.DispatcherTimer
            $global:delayTimer.Interval = [System.TimeSpan]::FromSeconds(1)
            $global:delayTimer.add_Tick({
                $global:delayTimer.Stop()
                $statusLabel.Text = "Capturing active... Click on target window."
                $window.WindowState = [System.Windows.WindowState]::Minimized
                Write-DebugLog "Window minimized. Ready to capture click."
            })
            $global:delayTimer.Start()
        } else {
            $global:isCapturing = $false
            $captureButton.Content = "Single Capture"
            $statusLabel.Text = "Capture cancelled"
            $window.WindowState = [System.Windows.WindowState]::Normal
            if ($global:delayTimer) { $global:delayTimer.Stop() }
            Write-DebugLog "Single capture cancelled."
        }
    } catch {
        $statusLabel.Text = "Error: $_"
        Write-DebugLog "ERROR inside Single Capture click: $_"
    }
})
 $continuousModeButton.add_Click({
    if (-not $global:continuousMode) {
        # Show the dialog FIRST, before enabling capturing to prevent the dialog's own click from being captured
        [System.Windows.MessageBox]::Show("Press the ESC button to stop recording.", "Continuous Capture", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
        
        $global:continuousMode = $true; $global:isCapturing = $true; $global:stopCapture = $false
        $global:wasMouseDown = $true # Ensure the mouse click on the dialog doesn't trigger capture
        $continuousModeButton.Content = "Stop Capturing"; $captureButton.IsEnabled = $false
        $statusLabel.Text = "Preparing continuous capture..."
        Write-DebugLog "Started continuous capture routine."
        
        if ($global:delayTimer) { $global:delayTimer.Stop() }
        $global:delayTimer = New-Object System.Windows.Threading.DispatcherTimer
        $global:delayTimer.Interval = [System.TimeSpan]::FromSeconds(1)
        $global:delayTimer.add_Tick({
            $global:delayTimer.Stop()
            $statusLabel.Text = "Continuous Capture active. Click on elements. Press ESC to stop."
            $window.WindowState = [System.Windows.WindowState]::Minimized
            Write-DebugLog "Window minimized. Ready to capture continuous clicks."
        })
        $global:delayTimer.Start()
    } else {
        $global:stopCapture = $true; $global:continuousMode = $false; $global:isCapturing = $false
        $continuousModeButton.Content = "Continuous Capture"; $captureButton.IsEnabled = $true
        $window.WindowState = [System.Windows.WindowState]::Normal
        $statusLabel.Text = "Saved to $screenshotPath"
        if ($global:delayTimer) { $global:delayTimer.Stop() }
        Write-DebugLog "Continuous capturing loop disabled."
    }
})
 $timer = New-Object System.Windows.Threading.DispatcherTimer
 $timer.Interval = [System.TimeSpan]::FromMilliseconds(100)
 $timer.add_Tick({
    if ($global:isCapturing) {
        $escPressed = [Win32]::GetAsyncKeyState(0x1B) -ne 0
        if ($global:continuousMode -and $escPressed) {
            Write-DebugLog "Escape key press detected. Stopping continuous capturing loop."
            $global:stopCapture = $true; $global:isCapturing = $false; $global:continuousMode = $false
            $captureButton.Content = "Single Capture"; $continuousModeButton.Content = "Continuous Capture"
            $captureButton.IsEnabled = $true; $window.WindowState = [System.Windows.WindowState]::Normal
            $statusLabel.Text = "Saved to $screenshotPath"
            return
        }
        try {
            $isMouseDown = ([Win32]::GetAsyncKeyState(0x01) -band 0x8000) -ne 0
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
                    if ($fullScreenCheckbox.IsChecked) {
                        $hdc = [Win32]::GetDC([IntPtr]::Zero)
                        $physicalW = [Win32]::GetDeviceCaps($hdc, 118); $physicalH = [Win32]::GetDeviceCaps($hdc, 117)
                        [Win32]::ReleaseDC([IntPtr]::Zero, $hdc) | Out-Null
                        Write-DebugLog "[DPI INFO] Executing Full-Screen Capture. Target Bounds: W=$physicalW, H=$physicalH"
                        $screenshot = New-Object System.Drawing.Bitmap ($physicalW, $physicalH)
                        $graphics = [System.Drawing.Graphics]::FromImage($screenshot)
                        $clientRect = New-Object Win32+RECT
                        [Win32]::GetClientRect($hwnd, [ref]$clientRect) | Out-Null
                        $win32Point = New-Object Win32+Point; $win32Point.X = 0; $win32Point.Y = 0
                        [Win32]::ClientToScreen($hwnd, [ref]$win32Point) | Out-Null
                        $graphics.CopyFromScreen(0, 0, 0, 0, [System.Drawing.Size]::new($physicalW, $physicalH))
                        if ($showOutlineCheckbox.IsChecked) {
                            $pen = New-Object Drawing.Pen ([System.Drawing.Color]::FromArgb($opacityVal, $global:outlineColor.R, $global:outlineColor.G, $global:outlineColor.B), $outlineWidth)
                            $graphics.DrawRectangle($pen, $win32Point.X + ($outlineWidth / 2), $win32Point.Y + ($outlineWidth / 2), $clientRect.Right - $outlineWidth, $clientRect.Bottom - $outlineWidth)
                        }
                        Draw-CursorHighlight $graphics $cursorInfo 0 0
                        Draw-Cursor $graphics $cursorInfo 0 0
                    } else {
                        $rootHwnd = [Win32]::GetAncestor($hwnd, [Win32]::GA_ROOT)
                        $rootRect = New-Object Win32+RECT
                        [Win32]::GetWindowRect($rootHwnd, [ref]$rootRect) | Out-Null
                        $clientRect = New-Object Win32+RECT
                        [Win32]::GetClientRect($hwnd, [ref]$clientRect) | Out-Null
                        $win32Point = New-Object Win32+Point; $win32Point.X = 0; $win32Point.Y = 0
                        [Win32]::ClientToScreen($hwnd, [ref]$win32Point) | Out-Null
                        $width = $rootRect.Right - $rootRect.Left; $height = $rootRect.Bottom - $rootRect.Top
                        Write-DebugLog "[DPI INFO] Executing Window-Only Capture. Detected Bounds: X=$($rootRect.Left), Y=$($rootRect.Top), W=$width, H=$height"
                        $screenshot = New-Object System.Drawing.Bitmap ($width, $height)
                        $graphics = [System.Drawing.Graphics]::FromImage($screenshot)
                        $graphics.CopyFromScreen($rootRect.Left, $rootRect.Top, 0, 0, $screenshot.Size)
                        if ($showOutlineCheckbox.IsChecked) {
                            $pen = New-Object Drawing.Pen ([System.Drawing.Color]::FromArgb($opacityVal, $global:outlineColor.R, $global:outlineColor.G, $global:outlineColor.B), $outlineWidth)
                            $adjustedLeft = $win32Point.X - $rootRect.Left; $adjustedTop = $win32Point.Y - $rootRect.Top
                            $graphics.DrawRectangle($pen, $adjustedLeft + ($outlineWidth / 2), $adjustedTop + ($outlineWidth / 2), $clientRect.Right - $outlineWidth, $clientRect.Bottom - $outlineWidth)
                        }
                        Draw-CursorHighlight $graphics $cursorInfo $rootRect.Left $rootRect.Top
                        Draw-Cursor $graphics $cursorInfo $rootRect.Left $rootRect.Top
                    }
                    if ($screenshotBorderCheckbox.IsChecked) {
                        $outerPen = New-Object Drawing.Pen ([System.Drawing.Color]::Black, 2)
                        $graphics.DrawRectangle($outerPen, 1, 1, $screenshot.Width - 2, $screenshot.Height - 2)
                        $outerPen.Dispose()
                    }
                    $wpfImage = Convert-BitmapToWpfSource $screenshot
                    $pictureBox.Source = $wpfImage
                    $paddedCounter = "{0:D2}" -f $global:captureCounter
                    $global:lastCapturePath = Join-Path $global:sessionFolder "$paddedCounter-$(Get-Date -Format 'yy.MM.dd_HH.mm.ss').png"
                    $screenshot.Save($global:lastCapturePath, [System.Drawing.Imaging.ImageFormat]::Png)
                    Write-DebugLog "Saved capture #$global:captureCounter to path: $global:lastCapturePath"
                    [System.Windows.Clipboard]::SetImage($wpfImage)
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
                $clipboardStatusLabel.Text = "Last screenshot automatically copied to clipboard"
                if (-not $global:continuousMode) {
                    $global:isCapturing = $false; $captureButton.Content = "Single Capture"; $openButton.IsEnabled = $true
                    $window.WindowState = [System.Windows.WindowState]::Normal; $statusLabel.Text = "Saved to $screenshotPath"
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
                $window.WindowState = [System.Windows.WindowState]::Normal
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
