# Unishield 360 - patches OpenSearch/Metricbeat settings into metricbeat.yml
# Reads OS_URL / OS_USER / OS_PASS / MB_INDEX env vars (set by the installer
# from its /OSURL=/OSUSER=/OSPASS=/MBINDEX= command-line params, which survive
# UAC elevation).
param([string]$Conf)
$ErrorActionPreference = "Stop"
$Conf = $Conf -replace '["\r\n]', ''
$content = Get-Content $Conf -Raw

if ($env:OS_URL) {
    $content = $content -replace 'hosts: \[[^\]]*\]', "hosts: [""$($env:OS_URL)""]"
}
if ($env:OS_USER) {
    $content = $content -replace 'username: ".*"', "username: ""$($env:OS_USER)"""
}
if ($env:OS_PASS) {
    $content = $content -replace 'password: ".*"', "password: ""$($env:OS_PASS)"""
}
if ($env:MB_INDEX) {
    $content = $content -replace 'index: "[^"]*"', "index: ""$($env:MB_INDEX)-%{+yyyy.MM.dd}"""
}
[System.IO.File]::WriteAllText($Conf, $content)