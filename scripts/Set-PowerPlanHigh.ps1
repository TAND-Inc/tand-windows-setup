<#
.SYNOPSIS
    Activate the built-in High Performance power plan.
#>
$highPerf = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'  # well-known GUID for High Performance
powercfg /setactive $highPerf
if ($LASTEXITCODE -eq 0) {
    Write-Host "High Performance power plan activated."
} else {
    Write-Warning "Could not set High Performance plan (it may be hidden on this hardware)."
}
