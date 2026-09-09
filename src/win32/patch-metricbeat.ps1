# Unishield 360 - patches Logstash/Metricbeat settings into metricbeat.yml
# Reads LS_HOST env var (set by the installer from its /LSHOST= command-line
# param, which survives UAC elevation).
param([string]$Conf)
$ErrorActionPreference = "Stop"
$Conf = $Conf -replace '["\r\n]', ''
$content = Get-Content $Conf -Raw

if ($env:LS_HOST) {
    $content = $content -replace 'hosts: \[[^\]]*\]', "hosts: [""$($env:LS_HOST)""]"
}
[System.IO.File]::WriteAllText($Conf, $content)