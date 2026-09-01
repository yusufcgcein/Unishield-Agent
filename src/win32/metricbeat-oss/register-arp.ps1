# ============================================================
#  Unishield 360 - Metric Agent: register in Add/Remove Programs
#  Run from the install dir (elevated) after extracting the zip.
# ============================================================
$ErrorActionPreference = "Stop"
$installDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$key = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Unishield 360 Metric Agent"

New-Item -Path $key -Force | Out-Null
New-ItemProperty -Path $key -Name "DisplayName" -Value "Unishield 360 Metric Agent" -PropertyType String -Force | Out-Null
New-ItemProperty -Path $key -Name "DisplayVersion" -Value "7.10.2" -PropertyType String -Force | Out-Null
New-ItemProperty -Path $key -Name "Publisher" -Value "Unishield 360" -PropertyType String -Force | Out-Null
New-ItemProperty -Path $key -Name "DisplayIcon" -Value "$installDir\unishield.ico" -PropertyType String -Force | Out-Null
New-ItemProperty -Path $key -Name "UninstallString" -Value "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$installDir\uninstall-agent.ps1`"" -PropertyType String -Force | Out-Null
New-ItemProperty -Path $key -Name "InstallLocation" -Value $installDir -PropertyType String -Force | Out-Null
New-ItemProperty -Path $key -Name "EstimatedSize" -Value 68000 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $key -Name "NoModify" -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $key -Name "NoRepair" -Value 1 -PropertyType DWord -Force | Out-Null

Write-Host "Unishield 360 Metric Agent registered in Add/Remove Programs." -ForegroundColor Green