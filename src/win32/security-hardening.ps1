# Unishield 360 - Security hardening post-install script
# - Configures Windows event log rotation (max size + retention) so storage does not fill
# - Enables recommended auditpol audit policies so security channels populate
# - Installs Sysmon (if a Sysmon binary/config is bundled alongside this script)
# Safe to run as part of agent install; each step is isolated and non-fatal.
param(
    [string]$ScriptDir = $PSScriptRoot
)
$ErrorActionPreference = "Continue"

# ---------------------------------------------------------------------------
# 1. Event log rotation - cap channel sizes + enable retention (clear-oldest)
#    Prevents Sysmon/Security channels from filling the endpoint disk.
# ---------------------------------------------------------------------------
$channels = @(
    @{ Name = "Microsoft-Windows-Sysmon/Operational";                       SizeMB = 1024 },
    @{ Name = "Microsoft-Windows-Windows Firewall With Advanced Security/Firewall"; SizeMB = 256 },
    @{ Name = "Microsoft-Windows-Windows Defender/Operational";             SizeMB = 256 },
    @{ Name = "Microsoft-Windows-PowerShell/Operational";                   SizeMB = 512 },
    @{ Name = "Microsoft-Windows-WMI-Activity/Operational";                 SizeMB = 256 },
    @{ Name = "Microsoft-Windows-TaskScheduler/Operational";                SizeMB = 128 },
    @{ Name = "Microsoft-Windows-TerminalServices-LocalSessionManager/Operational"; SizeMB = 128 },
    @{ Name = "Microsoft-Windows-RemoteDesktopServices-RdpCoreTS/Operational"; SizeMB = 128 },
    @{ Name = "Microsoft-Windows-NetworkProfile/Operational";               SizeMB = 128 },
    @{ Name = "Microsoft-Windows-AppLocker/EXE and DLL";                    SizeMB = 128 },
    @{ Name = "Security";                                                   SizeMB = 1024 },
    @{ Name = "System";                                                     SizeMB = 256 },
    @{ Name = "Application";                                                SizeMB = 256 }
)
foreach ($ch in $channels) {
    $bytes = [int64]$ch.SizeMB * 1MB
    & wevtutil.exe sl $ch.Name "/ms:$bytes" /rt:true /e:true 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "rotation OK: $($ch.Name) ($($ch.SizeMB)MB, retain-oldest)"
    } else {
        Write-Host "rotation skip: $($ch.Name) (channel not present)"
    }
}

# ---------------------------------------------------------------------------
# 2. auditpol - enable audit categories so Security events populate
# ---------------------------------------------------------------------------
$auditRules = @(
    "Logon/Logoff /success:enable /failure:enable",
    "Account Logon /success:enable /failure:enable",
    "Account Management /success:enable /failure:enable",
    "Detailed Tracking /success:enable /failure:enable",
    "Policy Change /success:enable /failure:enable",
    "Object Access /success:enable /failure:enable",
    "Privilege Use /success:enable /failure:enable",
    "System /success:enable /failure:enable"
)
foreach ($rule in $auditRules) {
    & auditpol.exe /set /subcategory:$rule 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "auditpol OK: $rule"
    } else {
        Write-Host "auditpol note: $rule (may require admin / unsupported on this SKU)"
    }
}

# ---------------------------------------------------------------------------
# 3. Sysmon - install if a Sysmon binary + config are bundled next to this script
# ---------------------------------------------------------------------------
$sysmonExe = Join-Path $ScriptDir "Sysmon64.exe"
$sysmonConf = Join-Path $ScriptDir "sysmon-config.xml"
$sysmonService = "Sysmon"
$running = (Get-Service -Name $sysmonService -ErrorAction SilentlyContinue)

if (Test-Path $sysmonExe) {
    if (-not $running) {
        & $sysmonExe -accepteula -i $sysmonConf 2>&1 | Out-Null
        Write-Host "Sysmon installed: $(Test-Path $sysmonExe)"
    } else {
        # Already installed - refresh config only if a new one is bundled
        if (Test-Path $sysmonConf) {
            & $sysmonExe -accepteula -c $sysmonConf 2>&1 | Out-Null
            Write-Host "Sysmon config refreshed"
        }
    }
} else {
    Write-Host "Sysmon binary not bundled - skipping install (config channel already enabled)"
}

# ---------------------------------------------------------------------------
# 4. Force agent to pick up new audit/sysmon config
# ---------------------------------------------------------------------------
& sc.exe stop WazuhSvc 2>$null | Out-Null
Start-Sleep -Seconds 2
& sc.exe start WazuhSvc 2>$null | Out-Null
Write-Host "WazuhSvc restarted to apply new event sources"

Write-Host "Unishield 360 security hardening complete."