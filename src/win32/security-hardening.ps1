# Unishield 360 - Security hardening post-install script (v2)
# - Sets SCENoApplyLegacyAuditPolicy so advanced audit subcategories take effect
# - Enables auditpol audit subcategories (Security event population)
# - Configures Windows event log rotation (max size + retention) to prevent disk fill
# - Downloads + installs Sysmon from Microsoft (best-effort, requires internet)
# Logs everything to security-hardening.log next to this script.
param(
    [string]$ScriptDir = $PSScriptRoot
)
$ErrorActionPreference = "Continue"
$logFile = Join-Path $ScriptDir "security-hardening.log"
function Log($msg) {
    $line = "[$(Get-Date -Format 'HH:mm:ss')] $msg"
    Write-Host $line
    Add-Content -Path $logFile -Value $line
}
function Run($cmd, $argsList) {
    try {
        $out = & $cmd @argsList 2>&1
        $code = $LASTEXITCODE
        return @{ Code = $code; Output = ($out -join "`n") }
    } catch {
        return @{ Code = -1; Output = $_.Exception.Message }
    }
}
Log "=== Unishield 360 security hardening start (v2) ==="
Log "IsElevated: $((New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))"

# ---------------------------------------------------------------------------
# 1. Enable advanced audit policy (REQUIRED for auditpol subcategories to work)
#    Without SCENoApplyLegacyAuditPolicy=1, Windows ignores advanced audit config.
# ---------------------------------------------------------------------------
try {
    New-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Force | Out-Null
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "SCENoApplyLegacyAuditPolicy" -Value 1 -Type DWord
    $v = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa").SCENoApplyLegacyAuditPolicy
    Log "SCENoApplyLegacyAuditPolicy = $v (OK, advanced audit policy enabled)"
} catch {
    Log "SCENoApplyLegacyAuditPolicy set FAILED: $($_.Exception.Message)"
}

# ---------------------------------------------------------------------------
# 2. auditpol - enable audit categories (Security channel events)
#    Uses category form via cmd.exe (subcategory form + PowerShell mangling
#    returns error 87 on some systems; categories set all subcategories).
# ---------------------------------------------------------------------------
$auditCats = @(
    "Logon/Logoff",
    "Account Logon",
    "Account Management",
    "Detailed Tracking",
    "Policy Change",
    "Object Access",
    "Privilege Use",
    "System"
)
foreach ($cat in $auditCats) {
    $cmd = "auditpol.exe /set /category:`"$cat`" /success:enable /failure:enable"
    & cmd.exe /c $cmd 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { Log "auditpol OK: $cat" }
    else { Log "auditpol FAIL: $cat (code $LASTEXITCODE)" }
}

# ---------------------------------------------------------------------------
# 3. Event log rotation - cap channel sizes + retention (clear-oldest)
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
    $cmd = "wevtutil.exe sl `"$($ch.Name)`" /ms:$bytes /rt:true /e:true"
    & cmd.exe /c $cmd 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { Log "rotation OK: $($ch.Name) ($($ch.SizeMB)MB, retain-oldest)" }
    else { Log "rotation skip: $($ch.Name) (code $LASTEXITCODE)" }
}

# ---------------------------------------------------------------------------
# 4. Sysmon - download from Microsoft (if not bundled) and install service
#    Sysmon installs its driver + service; place binary in C:\Windows (standard).
# ---------------------------------------------------------------------------
function Download-Sysmon {
    $url = "https://download.sysinternals.com/files/Sysmon.zip"
    $zip = Join-Path $env:TEMP "Sysmon.zip"
    $extract = Join-Path $env:TEMP "Sysmon-extract"
    try {
        Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing -TimeoutSec 90
        if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }
        Expand-Archive -Path $zip -DestinationPath $extract -Force
        Log "Sysmon downloaded from Microsoft ($url)"
        return $extract
    } catch {
        Log "Sysmon download FAILED: $($_.Exception.Message)"
        return $null
    } finally {
        if (Test-Path $zip) { Remove-Item $zip -Force }
    }
}

$sysmonDest = Join-Path $env:WINDIR "Sysmon64.exe"
$sysmonService = "Sysmon"
$running = Get-Service -Name $sysmonService -ErrorAction SilentlyContinue

if (-not $running) {
    $sysmonSrc = $null
    # 1) bundled next to script
    $bundled = Join-Path $ScriptDir "Sysmon64.exe"
    if (Test-Path $bundled) { $sysmonSrc = $bundled }
    else {
        # 2) auto-download
        $extract = Download-Sysmon
        if ($extract -and (Test-Path (Join-Path $extract "Sysmon64.exe"))) {
            $sysmonSrc = Join-Path $extract "Sysmon64.exe"
        }
    }
    if ($sysmonSrc) {
        try {
            Copy-Item $sysmonSrc $sysmonDest -Force
            Log "Sysmon binary placed at $sysmonDest"
            $confArg = @()
            if (Test-Path (Join-Path $ScriptDir "sysmon-config.xml")) {
                $confArg = @("-c", (Join-Path $ScriptDir "sysmon-config.xml"))
            }
            $res = Run $sysmonDest @("-accepteula", "-i") + $confArg
            Log "Sysmon install cmd exit code: $($res.Code)"
            if ($res.Output) { Log "Sysmon install output: $($res.Output)" }
            Start-Sleep -Seconds 3
            $svc = Get-Service -Name $sysmonService -ErrorAction SilentlyContinue
            if ($svc) { Log "Sysmon service: $($svc.Status)" }
            else { Log "Sysmon service NOT registered after install (check driver/signature)" }
        } catch {
            Log "Sysmon install exception: $($_.Exception.Message)"
        }
    } else {
        Log "Sysmon binary unavailable (no internet / download blocked) - manual install needed"
    }
} else {
    Log "Sysmon already installed ($($running.Status))"
}

# ---------------------------------------------------------------------------
# 5. Restart agent to pick up new event sources
# ---------------------------------------------------------------------------
$r = Run "sc.exe" @("stop", "WazuhSvc"); Log "WazuhSvc stop: $($r.Code)"
Start-Sleep -Seconds 2
$r = Run "sc.exe" @("start", "WazuhSvc"); Log "WazuhSvc start: $($r.Code)"
Log "=== Unishield 360 security hardening complete ==="