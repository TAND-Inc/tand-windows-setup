<#
.SYNOPSIS
    Install every driver found under a folder (driver restore).
.DESCRIPTION
    Prompts for a source folder (graphical picker, with a typed-path fallback),
    then adds and installs all .inf driver packages under it, recursively:

        pnputil /add-driver "<folder>\*.inf" /subdirs /install

    Pair this with a backup made by the companion "Export drivers" item.
.NOTES
    Requires Administrator. /install actively installs matching drivers for
    devices present on this machine; a reboot may be required (reported below).
#>

function Get-Folder {
    # Graphical folder picker with a typed-path fallback. Returns $null if the
    # user cancels the dialog and types nothing.
    param([string]$Description, [string]$Default)
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description         = $Description
        $dlg.ShowNewFolderButton = $false
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

Write-Host "=== Import (install) drivers from a folder ===" -ForegroundColor Cyan

$src = Get-Folder -Description "Choose the folder that holds the drivers to install" `
                  -Default "$env:SystemDrive\DriverBackup"
if (-not $src) { Write-Warning "No source folder chosen. Aborting."; return }
if (-not (Test-Path -LiteralPath $src)) { Write-Warning "Folder not found: $src"; return }

$infCount = @(Get-ChildItem -LiteralPath $src -Filter *.inf -Recurse -ErrorAction SilentlyContinue).Count
if ($infCount -eq 0) {
    Write-Warning "No .inf files found under '$src'. Nothing to install."
    return
}
Write-Host "Found $infCount .inf file(s) under: $src" -ForegroundColor White
Write-Host "Installing with pnputil /add-driver ... /subdirs /install ..." -ForegroundColor DarkGray

$pnputil = Join-Path $env:SystemRoot 'System32\pnputil.exe'
# PowerShell does NOT glob-expand *.inf for native commands, so the wildcard is
# passed through to pnputil verbatim and /subdirs makes it recurse. Quoting the
# path keeps spaces intact, and the launcher runs elevated -- the two things that
# usually force people to fall back to cmd.exe for this exact command.
& $pnputil /add-driver "$src\*.inf" /subdirs /install
$code = $LASTEXITCODE

switch ($code) {
    0       { Write-Host "Driver install complete." -ForegroundColor Green }
    3010    { Write-Host "Driver install complete - a REBOOT is required to finish." -ForegroundColor Yellow }
    default {
        Write-Warning "pnputil finished with exit code $code."
        Write-Host "If needed, re-run manually in an elevated CMD:" -ForegroundColor DarkGray
        Write-Host "    pnputil /add-driver `"$src\*.inf`" /subdirs /install" -ForegroundColor DarkGray
    }
}
