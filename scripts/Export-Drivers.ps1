<#
.SYNOPSIS
    Back up all third-party drivers from the running Windows install to a folder.
.DESCRIPTION
    Prompts for a destination folder (graphical picker, with a typed-path
    fallback), then exports every installed third-party / OEM driver package
    with Export-WindowsDriver -Online. If that cmdlet is unavailable it falls
    back to the DISM CLI (dism /online /export-driver).

    Re-apply a backup later with the companion "Import drivers" item, which runs
    pnputil /add-driver <folder>\*.inf /subdirs /install.
.NOTES
    Requires Administrator. Only third-party / OEM drivers are exported; inbox
    Microsoft drivers are intentionally skipped.
#>

function Get-Folder {
    # Graphical folder picker with a typed-path fallback. Returns $null if the
    # user cancels the dialog and types nothing.
    param([string]$Description, [string]$Default)
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description         = $Description
        $dlg.ShowNewFolderButton = $true
        if ($Default) { $dlg.SelectedPath = $Default }
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK -and $dlg.SelectedPath) {
            return $dlg.SelectedPath
        }
    } catch {
        # No usable GUI (e.g. a non-STA host); fall through to a typed path.
    }
    $typed = (Read-Host "$Description - type a full path").Trim().Trim('"')
    if ($typed) { return $typed }
    return $null
}

Write-Host "=== Export (back up) all third-party drivers ===" -ForegroundColor Cyan

$dest = Get-Folder -Description "Choose a destination folder for the driver backup" `
                   -Default "$env:SystemDrive\DriverBackup"
if (-not $dest) { Write-Warning "No destination chosen. Aborting."; return }

if (-not (Test-Path -LiteralPath $dest)) {
    try { New-Item -ItemType Directory -Path $dest -Force -ErrorAction Stop | Out-Null }
    catch { Write-Warning "Could not create '$dest': $_"; return }
}

Write-Host "Exporting drivers to: $dest" -ForegroundColor White
Write-Host "(this can take several minutes on a machine with many drivers)..." -ForegroundColor DarkGray

try {
    $exported = Export-WindowsDriver -Online -Destination $dest -ErrorAction Stop
    Write-Host ("Exported {0} driver package(s) via Export-WindowsDriver." -f @($exported).Count) -ForegroundColor Green
} catch {
    Write-Warning "Export-WindowsDriver failed or is unavailable: $_"
    Write-Host "Falling back to DISM (dism /online /export-driver)..." -ForegroundColor Yellow
    & "$env:SystemRoot\System32\dism.exe" /online /export-driver "/destination:$dest"
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Drivers exported via DISM." -ForegroundColor Green
    } else {
        Write-Warning "DISM export failed (exit code $LASTEXITCODE)."
        return
    }
}

Write-Host "Driver backup complete: $dest" -ForegroundColor Green
