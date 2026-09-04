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
    @{ Name = "Microsoft-Windows-Sysmon/Operational";                       SizeMB = 500 },
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
    @{ Category = "Logon/Logoff";  Success = "enable"; Failure = "enable" },
    @{ Category = "Account Logon"; Success = "enable"; Failure = "enable" },
    @{ Category = "Account Management"; Success = "enable"; Failure = "enable" },
    @{ Category = "Detailed Tracking"; Success = "enable"; Failure = "enable" },
    @{ Category = "Policy Change"; Success = "enable"; Failure = "enable" },
    @{ Category = "Object Access"; Success = "enable"; Failure = "enable" },
    @{ Category = "Privilege Use"; Success = "enable"; Failure = "enable" },
    @{ Category = "System"; Success = "enable"; Failure = "enable" }
)
foreach ($r in $auditRules) {
    & auditpol.exe /set /subcategory:"$($r.Category)" "/success:$($r.Success)" "/failure:$($r.Failure)" 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "auditpol OK: $($r.Category)"
    } else {
        Write-Host "auditpol note: $($r.Category) (may require admin / unsupported on this SKU)"
    }
}

# ---------------------------------------------------------------------------
# 3. Sysmon - install if bundled, else auto-download from Microsoft (best-effort)
# ---------------------------------------------------------------------------
$sysmonExe = Join-Path $ScriptDir "Sysmon64.exe"
$sysmonConf = Join-Path $ScriptDir "sysmon-config.xml"
$sysmonService = "Sysmon"
$running = (Get-Service -Name $sysmonService -ErrorAction SilentlyContinue)

function Download-Sysmon {
    param([string]$TargetDir)
    # Official Sysinternals Sysmon package (Microsoft download.microsoft.com)
    $url = "https://download.sysinternals.com/files/Sysmon.zip"
    $zip = Join-Path $env:TEMP "Sysmon.zip"
    $extract = Join-Path $env:TEMP "Sysmon-extract"
    try {
        Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing -TimeoutSec 60
        if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }
        Expand-Archive -Path $zip -DestinationPath $extract -Force
        Copy-Item (Join-Path $extract "Sysmon64.exe") $TargetDir -Force -ErrorAction SilentlyContinue
        Copy-Item (Join-Path $extract "Sysmon.exe") $TargetDir -Force -ErrorAction SilentlyContinue
        Write-Host "Sysmon downloaded from Microsoft"
        return $true
    } catch {
        Write-Host "Sysmon download failed: $_"
        return $false
    } finally {
        if (Test-Path $zip) { Remove-Item $zip -Force }
    }
}

if (-not (Test-Path $sysmonExe)) {
    $downloaded = Download-Sysmon $ScriptDir
    if ($downloaded) { $sysmonExe = Join-Path $ScriptDir "Sysmon64.exe" }
}

if (Test-Path $sysmonExe) {
    if (-not $running) {
        $confArg = @()
        if (Test-Path $sysmonConf) { $confArg = @("-c", $sysmonConf) }
        & $sysmonExe -accepteula -i @($confArg) 2>&1 | Out-Null
        Start-Sleep -Seconds 2
        $svc = Get-Service -Name $sysmonService -ErrorAction SilentlyContinue
        if ($svc) { Write-Host "Sysmon service installed: $($svc.Status)" }
        else { Write-Host "Sysmon install failed (run manually)" }
    } else {
        # Already installed - refresh config only if a new one is bundled
        if (Test-Path $sysmonConf) {
            & $sysmonExe -accepteula -c $sysmonConf 2>&1 | Out-Null
            Write-Host "Sysmon config refreshed"
        }
    }
} else {
    Write-Host "Sysmon binary unavailable (no internet or download blocked) - config channel enabled, install Sysmon manually"
}

# ---------------------------------------------------------------------------
# 4. Force agent to pick up new audit/sysmon config
# ---------------------------------------------------------------------------
& sc.exe stop WazuhSvc 2>$null | Out-Null
Start-Sleep -Seconds 2
& sc.exe start WazuhSvc 2>$null | Out-Null
Write-Host "WazuhSvc restarted to apply new event sources"

Write-Host "Unishield 360 security hardening complete."