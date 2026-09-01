# Unishield 360 - patches manager address/port/protocol into ossec.conf
# Reads WAZUH_MANAGER / WAZUH_MANAGER_PORT / WAZUH_PROTOCOL env vars.
param([string]$Conf)
$ErrorActionPreference = "Stop"
$Conf = $Conf -replace '["\r\n]', ''
$content = Get-Content $Conf -Raw
if ($env:WAZUH_MANAGER) {
    $content = $content -replace '<address>[^<]*</address>', "<address>$($env:WAZUH_MANAGER)</address>"
}
if ($env:WAZUH_MANAGER_PORT) {
    $content = $content -replace '<port>[0-9]*</port>', "<port>$($env:WAZUH_MANAGER_PORT)</port>"
}
if ($env:WAZUH_PROTOCOL) {
    $content = $content -replace '<protocol>[^<]*</protocol>', "<protocol>$($env:WAZUH_PROTOCOL)</protocol>"
}
[System.IO.File]::WriteAllText($Conf, $content)