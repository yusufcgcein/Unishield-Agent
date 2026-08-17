# ============================================================
#  Unishield 360 Agent - Change Manager IP (Windows)
#
#  Use this on an ALREADY-INSTALLED agent to point it at a
#  different manager/collector, without reinstalling.
#
#  Usage (run PowerShell as Administrator):
#    .\set-agent-ip.ps1 100.110.74.122
#    .\set-agent-ip.ps1 203.0.113.10 1514
# ============================================================
param(
    [Parameter(Mandatory=$true)][string]$ManagerIP,
    [string]$Port = "1514"
)

$conf = "C:\Program Files (x86)\ossec-agent\ossec.conf"
if (-not (Test-Path $conf)) {
    $conf = "C:\Program Files\ossec-agent\ossec.conf"
}
if (-not (Test-Path $conf)) {
    Write-Error "ossec.conf not found. Is the agent installed?"
    exit 1
}

Write-Host "Unishield 360 Agent - setting manager to $ManagerIP`:$Port"

# Stop agent service
Write-Host "[1/3] Stopping agent service..."
Stop-Service WazuhSvc -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# Update config
Write-Host "[2/3] Updating $conf ..."
$content = Get-Content $conf -Raw
$content = $content -replace '<address>[^<]*</address>', "<address>$ManagerIP</address>"
$content = $content -replace '<port>[0-9]*</port>', "<port>$Port</port>"
[System.IO.File]::WriteAllText($conf, $content)

Get-Content $conf | Select-Object -First 12

# Start agent (auto re-enrolls if needed)
Write-Host "[3/3] Starting agent service..."
Start-Service WazuhSvc -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "DONE. Agent now reports to $ManagerIP`:$Port"
Write-Host "Verify:  Get-Service WazuhSvc"
Write-Host "         Get-Content 'C:\Program Files (x86)\ossec-agent\client.keys'"
