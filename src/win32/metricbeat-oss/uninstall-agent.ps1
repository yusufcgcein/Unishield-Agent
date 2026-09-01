# ============================================================
#  Unishield 360 - Metric Agent uninstaller
#  Removes the metricbeat service, deletes install + data,
#  and clears the Add/Remove Programs entry.
# ============================================================
$ErrorActionPreference = "Continue"

Write-Host "Uninstalling Unishield 360 Metric Agent..." -ForegroundColor Cyan

# 1. Stop + remove service
if (Get-Service metricbeat -ErrorAction SilentlyContinue) {
    Stop-Service metricbeat -Force
    Start-Sleep -Seconds 2
    sc.exe delete metricbeat
    Start-Sleep -Seconds 2
}

# 2. Remove ARP entry
Remove-Item "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Unishield 360 Metric Agent" -Recurse -Force -ErrorAction SilentlyContinue

# 3. Remove install dir
Remove-Item "C:\Program Files\metricbeat-oss" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "C:\ProgramData\metricbeat" -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "Uninstall complete." -ForegroundColor Green