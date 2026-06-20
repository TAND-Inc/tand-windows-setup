<#
.SYNOPSIS
    Set the Windows telemetry policy to the lowest allowed level.
.NOTES
    Requires Administrator. Value 0 (Security) is only fully honored on
    Enterprise/Education SKUs; on Pro/Home the effective floor is 1 (Basic).
#>
$key = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
Set-ItemProperty -Path $key -Name AllowTelemetry -Type DWord -Value 0
Write-Host "Telemetry policy set to minimum (effective level depends on Windows edition)."
