#Requires -Version 5.1
<#
.SYNOPSIS
    Windows Setup Toolkit - launcher
.DESCRIPTION
    Entry point intended to be run via:

        irm https://raw.githubusercontent.com/TAND-Inc/tand-windows-setup/main/launcher.ps1 | iex

    Loads a JSON manifest of apps/scripts from the repo and presents a WPF
    selection menu. Selected items are installed (winget/choco/download) or run (scripts).

    The launcher is deliberately thin: all content lives in config/apps.json and
    scripts/*.ps1, so adding a new app or tweak is a manifest edit, not a code change.

    Targets fresh Windows 11 IoT Enterprise LTSC, which ships WITHOUT the Microsoft
    Store and therefore without winget. Install-Winget bootstraps it on demand, and
    any manifest item may carry a "fallback" (typically a direct download) used when
    the primary method is unavailable or fails.

    The menu reopens after each run so multiple batches can be applied in one session.
    Already-installed items are detected from the uninstall registry and labelled with
    their version.
#>

# ============================================================================
#  CONFIGURATION  -- point this at the RAW base of your repo (no trailing slash)
# ============================================================================
$BaseUrl = 'https://raw.githubusercontent.com/TAND-Inc/tand-windows-setup/main'

# ============================================================================
#  PREREQUISITES
# ============================================================================
# Older Windows defaults to TLS 1.0/1.1, which fails the HTTPS handshake to GitHub
# (and to PSGallery during the winget bootstrap).
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Suppress per-request progress bars: they slow Invoke-WebRequest/RestMethod
# dramatically and render as noise when the launcher is piped through iex.
$ProgressPreference = 'SilentlyContinue'

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$script:WingetAvailable = $false
$script:WingetTried     = $false

# ============================================================================
#  HELPERS
# ============================================================================
function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function New-Brush {
    param([string]$Hex)
    # Programmatic WPF property assignment needs a Brush object, not a string.
    [Windows.Media.SolidColorBrush]::new(
        [Windows.Media.ColorConverter]::ConvertFromString($Hex))
}

function Get-Manifest {
    param([string]$Url)
    try {
        Invoke-RestMethod -Uri $Url -UseBasicParsing
    } catch {
        throw "Failed to load manifest from $Url`n$_"
    }
}

function Get-InstalledPrograms {
    <#
      Snapshot of installed desktop programs from the uninstall registry keys
      (HKLM 64-bit, HKLM 32-bit, HKCU). Returns objects with Name + Version.
      This works WITHOUT winget, which matters on a fresh LTSC box, and it picks
      up anything installed via MSI or a normal EXE installer. Note: MSIX/Store
      apps (e.g. Windows Terminal) do NOT appear here.
    #>
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($p in $paths) {
        try {
            Get-ItemProperty -Path $p -ErrorAction SilentlyContinue | ForEach-Object {
                if ($_.DisplayName) {
                    $list.Add([pscustomobject]@{
                        Name    = [string]$_.DisplayName
                        Version = [string]$_.DisplayVersion
                    })
                }
            }
        } catch { }
    }
    $list
}

function Get-ItemInstallInfo {
    <#
      Decide whether a manifest item is already installed, and at what version.
      Only app methods are detectable; tweak/script items always return $null.
      Match on the optional `detect` string, falling back to the item `name`.
    #>
    param($Item, $Installed)

    if (@('winget', 'choco', 'download') -notcontains $Item.method) { return $null }

    $needle =
        if (($Item.PSObject.Properties.Name -contains 'detect') -and $Item.detect) { $Item.detect }
        else { $Item.name }

    $hit = $Installed | Where-Object { $_.Name -like "*$needle*" } | Select-Object -First 1
    if ($hit) {
        $ver = if ($hit.Version) { $hit.Version } else { 'unknown' }
        return [pscustomobject]@{ Installed = $true; Version = $ver }
    }
    return $null
}

function Get-WingetStatus {
    # Refresh PATH first: a provisioned winget.exe may not be on PATH yet this session.
    $env:Path += ";$env:LOCALAPPDATA\Microsoft\WindowsApps"
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        $ver = $null
        try { $ver = (winget --version) 2>$null } catch { }
        if ($ver) { return "winget is installed ($ver)." }
        return "winget is installed."
    }
    return "winget is NOT installed. It will be bootstrapped automatically when a winget item runs."
}

function Install-Winget {
    <#
      Ensure winget is available on this machine; return $true/$false.

      Fresh Windows 11 IoT/Enterprise LTSC has no Microsoft Store, so winget
      (App Installer) is usually absent. We try, cheapest first:
        1) winget already on PATH
        2) re-register an App Installer that is present but not registered
        3) install via the Microsoft.WinGet.Client module + Repair-WinGetPackageManager

      We deliberately use the module/Repair path rather than hand-downloading the
      msixbundle: Microsoft retired the old hardcoded VCLibs URL, so any script
      that pins dependency links now fails silently. Repair pulls the right
      dependencies itself.
    #>
    # A freshly-provisioned winget.exe lands here but may not be on PATH yet.
    $env:Path += ";$env:LOCALAPPDATA\Microsoft\WindowsApps"

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "winget already available." -ForegroundColor Green
        return $true
    }

    Write-Host "winget not found; attempting to bootstrap it..." -ForegroundColor Yellow

    # 2) App Installer present but unregistered for this user (cheap, no network).
    try {
        Add-AppxPackage -RegisterByFamilyName `
            -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction Stop
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            Write-Host "winget registered." -ForegroundColor Green
            return $true
        }
    } catch {
        # Expected on stripped LTSC images where the package isn't present at all.
    }

    # 3) Full install via the WinGet PowerShell module.
    try {
        Write-Host "    installing Microsoft.WinGet.Client module..." -ForegroundColor DarkGray
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ErrorAction Stop | Out-Null
        Install-Module -Name Microsoft.WinGet.Client -Force -Repository PSGallery `
            -Scope AllUsers -ErrorAction Stop | Out-Null
        Import-Module Microsoft.WinGet.Client -ErrorAction SilentlyContinue
        Write-Host "    running Repair-WinGetPackageManager (downloads dependencies)..." -ForegroundColor DarkGray
        Repair-WinGetPackageManager -Force -Latest -ErrorAction Stop
    } catch {
        Write-Warning "winget bootstrap failed: $_"
    }

    $env:Path += ";$env:LOCALAPPDATA\Microsoft\WindowsApps"
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "winget bootstrapped successfully." -ForegroundColor Green
        return $true
    }

    Write-Warning "Could not make winget available. winget items will use their fallback (if any)."
    return $false
}

function Invoke-Install {
    <#
      Execute a single install "spec" (the item itself, or its .fallback).
      Throws on failure so the caller can decide whether to try a fallback.
    #>
    param($Spec, [string]$BaseUrl)

    switch ($Spec.method) {
        'winget' {
            if (-not $script:WingetAvailable) {
                throw "winget is not available on this system."
            }
            winget install --id $Spec.payload --exact --silent `
                --accept-package-agreements --accept-source-agreements --source winget
            # winget exit codes are quirky: 0 = success; the two negative codes
            # below mean "already installed" / "no applicable upgrade", also fine.
            $okCodes = @(0, -1978335189, -1978335212)
            if ($okCodes -notcontains $LASTEXITCODE) {
                throw "winget exited with code $LASTEXITCODE."
            }
        }
        'choco' {
            if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
                Write-Host "    Chocolatey not found; installing it..." -ForegroundColor Yellow
                Set-ExecutionPolicy Bypass -Scope Process -Force
                Invoke-Expression ((New-Object Net.WebClient).DownloadString(
                    'https://community.chocolatey.org/install.ps1'))
            }
            choco install $Spec.payload -y
            if ($LASTEXITCODE -ne 0) { throw "choco exited with code $LASTEXITCODE." }
        }
        'script' {
            $url = "$BaseUrl/scripts/$($Spec.payload)"
            $tmp = Join-Path $env:TEMP $Spec.payload
            Invoke-RestMethod -Uri $url -OutFile $tmp -UseBasicParsing
            & $tmp
            Remove-Item $tmp -ErrorAction SilentlyContinue
        }
        'download' {
            # Direct vendor installer. Spec fields: url, file (optional), args (optional).
            $url = $Spec.url
            if (-not $url) { throw "download item has no 'url'." }

            $file = if ($Spec.file) { $Spec.file } else { [IO.Path]::GetFileName(($url -split '\?')[0]) }
            if (-not $file) { $file = "installer.tmp" }
            $tmp = Join-Path $env:TEMP $file

            Write-Host "    downloading $file ..." -ForegroundColor DarkGray
            Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing

            $arguments = [string]$Spec.args
            try {
                if ($file -match '\.msi$') {
                    $msiArgs = ("/i `"$tmp`" $arguments").Trim()
                    $p = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArgs -Wait -PassThru
                } else {
                    $sp = @{ FilePath = $tmp; Wait = $true; PassThru = $true }
                    if ($arguments) { $sp.ArgumentList = $arguments }
                    $p = Start-Process @sp
                }
                # 0 = success, 3010 = success but a reboot is required.
                if (@(0, 3010) -notcontains $p.ExitCode) {
                    throw "installer exited with code $($p.ExitCode)."
                }
            } finally {
                Remove-Item $tmp -ErrorAction SilentlyContinue
            }
        }
        default {
            throw "Unknown method '$($Spec.method)'."
        }
    }
}

function Invoke-ToolkitItem {
    param($Item, [string]$BaseUrl)

    Write-Host "==> $($Item.name)" -ForegroundColor Cyan
    try {
        Invoke-Install -Spec $Item -BaseUrl $BaseUrl
        Write-Host "    done." -ForegroundColor Green
    } catch {
        $primaryErr = $_
        $hasFallback = ($Item.PSObject.Properties.Name -contains 'fallback') -and $Item.fallback
        if ($hasFallback) {
            Write-Warning "    primary ($($Item.method)) failed: $primaryErr"
            Write-Host    "    trying fallback ($($Item.fallback.method))..." -ForegroundColor Yellow
            try {
                Invoke-Install -Spec $Item.fallback -BaseUrl $BaseUrl
                Write-Host "    done (via fallback)." -ForegroundColor Green
            } catch {
                Write-Warning "    FALLBACK FAILED: $_"
            }
        } else {
            Write-Warning "    FAILED: $primaryErr"
        }
    }
}

function Show-ToolkitMenu {
    <#
      Build a fresh WPF window from the manifest, detecting installed state each
      time it opens, and return @{ Action = 'run'|'close'; Selected = @(items) }.
    #>
    param($Manifest)

    $installed = Get-InstalledPrograms

    $Xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Windows Setup Toolkit" Height="710" Width="600"
        WindowStartupLocation="CenterScreen" Background="#1E1E2E"
        FontFamily="Segoe UI">
  <Grid Margin="16">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <StackPanel Grid.Row="0" Margin="0,0,0,10">
      <TextBlock Text="Windows Setup Toolkit" FontSize="22" FontWeight="Bold" Foreground="#CDD6F4"/>
      <TextBlock Text="Select apps and tweaks to apply, then click Run Selected. The menu reopens after each run."
                 FontSize="12" Foreground="#A6ADC8" Margin="0,2,0,0" TextWrapping="Wrap"/>
    </StackPanel>

    <Border Grid.Row="1" BorderBrush="#45475A" BorderThickness="1" CornerRadius="6"
            Background="#181825" Padding="10" Margin="0,0,0,10">
      <DockPanel LastChildFill="True">
        <Button x:Name="WingetCheckBtn" Content="Check winget" Width="120" Height="30"
                DockPanel.Dock="Left" Background="#45475A" Foreground="#CDD6F4" BorderThickness="0"/>
        <TextBlock x:Name="WingetStatus" Text="winget status unknown - click &quot;Check winget&quot;."
                   VerticalAlignment="Center" Margin="12,0,0,0" Foreground="#A6ADC8" TextWrapping="Wrap"/>
      </DockPanel>
    </Border>

    <Border Grid.Row="2" BorderBrush="#45475A" BorderThickness="1" CornerRadius="6" Background="#181825">
      <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="10">
        <StackPanel x:Name="ItemsPanel"/>
      </ScrollViewer>
    </Border>

    <DockPanel Grid.Row="3" Margin="0,12,0,0" LastChildFill="False">
      <Button x:Name="SelectAllBtn"   Content="Select All"  Width="90"  Height="32" DockPanel.Dock="Left"/>
      <Button x:Name="SelectNoneBtn"  Content="Clear"       Width="70"  Height="32" Margin="8,0,0,0" DockPanel.Dock="Left"/>
      <Button x:Name="RecommendedBtn" Content="Recommended" Width="110" Height="32" Margin="8,0,0,0" DockPanel.Dock="Left"/>
      <Button x:Name="RunBtn"   Content="Run Selected" Width="130" Height="32" DockPanel.Dock="Right"
              Background="#89B4FA" Foreground="#1E1E2E" FontWeight="Bold" BorderThickness="0"/>
      <Button x:Name="CloseBtn" Content="Close" Width="80" Height="32" Margin="0,0,8,0" DockPanel.Dock="Right"/>
    </DockPanel>
  </Grid>
</Window>
'@

    $reader = [System.Xml.XmlNodeReader]::new([xml]$Xaml)
    $window = [Windows.Markup.XamlReader]::Load($reader)
    $panel  = $window.FindName('ItemsPanel')

    # Populate the panel from the manifest, grouped by category.
    $checkboxes = New-Object System.Collections.Generic.List[object]
    foreach ($group in ($Manifest.items | Group-Object category)) {
        $header = New-Object Windows.Controls.TextBlock
        $header.Text       = $group.Name
        $header.FontWeight = 'Bold'
        $header.FontSize   = 14
        $header.Foreground = New-Brush '#F9E2AF'
        $header.Margin     = '0,10,0,4'
        $panel.AddChild($header)

        foreach ($item in $group.Group) {
            $info = Get-ItemInstallInfo -Item $item -Installed $installed

            $cb = New-Object Windows.Controls.CheckBox
            if ($info) {
                $cb.Content    = "$($item.name)  (Installed - Version: $($info.Version))"
                $cb.Foreground = New-Brush '#A6E3A1'   # green = already installed
            } else {
                $cb.Content    = $item.name
                $cb.Foreground = New-Brush '#CDD6F4'
            }
            $cb.ToolTip   = $item.description
            $cb.IsChecked = $false                      # nothing checked at launch
            $cb.Margin    = '6,3,0,3'
            $cb.Tag       = $item
            $panel.AddChild($cb)
            $checkboxes.Add($cb)
        }
    }

    # Selection buttons.
    $window.FindName('SelectAllBtn').Add_Click({   foreach ($c in $checkboxes) { $c.IsChecked = $true } })
    $window.FindName('SelectNoneBtn').Add_Click({  foreach ($c in $checkboxes) { $c.IsChecked = $false } })
    $window.FindName('RecommendedBtn').Add_Click({ foreach ($c in $checkboxes) { $c.IsChecked = [bool]$c.Tag.default } })

    # winget status button.
    $statusBlock = $window.FindName('WingetStatus')
    $window.FindName('WingetCheckBtn').Add_Click({
        $msg = Get-WingetStatus
        $statusBlock.Text = $msg
        if ($msg -like '*NOT installed*') { $statusBlock.Foreground = New-Brush '#F38BA8' }
        else                              { $statusBlock.Foreground = New-Brush '#A6E3A1' }
    })

    # Result plumbing.
    $script:MenuAction   = 'close'
    $script:MenuSelected = @()
    $window.FindName('RunBtn').Add_Click({
        $script:MenuSelected = @($checkboxes | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag })
        $script:MenuAction   = 'run'
        $window.Close()
    })
    $window.FindName('CloseBtn').Add_Click({
        $script:MenuAction = 'close'
        $window.Close()
    })

    $null = $window.ShowDialog()
    [pscustomobject]@{ Action = $script:MenuAction; Selected = $script:MenuSelected }
}

# ============================================================================
#  ADMIN CHECK  (installs and HKLM tweaks need elevation)
# ============================================================================
if (-not (Test-Admin)) {
    Write-Warning "Not running as Administrator. Most installs/tweaks will fail."
    $ans = Read-Host "Relaunch elevated? (Y/n)"
    if ($ans -notmatch '^(n|no)$') {
        $cmd = "irm $BaseUrl/launcher.ps1 | iex"
        Start-Process -Verb RunAs -FilePath 'powershell.exe' -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $cmd)
        return
    }
}

# ============================================================================
#  LOAD MANIFEST
# ============================================================================
$manifest = Get-Manifest -Url "$BaseUrl/config/apps.json"
if (-not $manifest.items) { throw "Manifest contained no items." }

# ============================================================================
#  MAIN LOOP  (menu -> run -> reopen menu, until Close)
# ============================================================================
do {
    $menu = Show-ToolkitMenu -Manifest $manifest

    if ($menu.Action -ne 'run') { break }

    if (-not $menu.Selected -or $menu.Selected.Count -eq 0) {
        Write-Host "Nothing selected." -ForegroundColor Yellow
        continue   # reopen the menu
    }

    # Bootstrap winget once per session, only if something selected needs it.
    if ($menu.Selected | Where-Object { $_.method -eq 'winget' }) {
        if (-not $script:WingetAvailable -and -not $script:WingetTried) {
            $script:WingetTried     = $true
            $script:WingetAvailable = Install-Winget
        }
    }

    Write-Host "`nRunning $($menu.Selected.Count) item(s)...`n" -ForegroundColor White
    foreach ($item in $menu.Selected) {
        Invoke-ToolkitItem -Item $item -BaseUrl $BaseUrl
    }
    Write-Host "`nBatch complete. Reopening the menu..." -ForegroundColor Green
} while ($true)

Write-Host "`nClosing the toolkit. Done." -ForegroundColor Green
