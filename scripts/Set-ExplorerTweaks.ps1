<#
.SYNOPSIS
    Common File Explorer quality-of-life tweaks (per-user, HKCU).
#>
$adv = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'

Set-ItemProperty -Path $adv -Name HideFileExt -Type DWord -Value 0   # show file extensions
Set-ItemProperty -Path $adv -Name Hidden      -Type DWord -Value 1   # show hidden files
Set-ItemProperty -Path $adv -Name LaunchTo    -Type DWord -Value 1   # open Explorer to "This PC"

Write-Host "Explorer tweaks applied. Restarting Explorer to apply..."
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
Start-Process explorer
