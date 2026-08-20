#requires -Version 5.1
<#
.SYNOPSIS
    Opens the customer RemoteApp download portal in the default browser.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

$candidates = New-Object System.Collections.Generic.List[string]
$cfgDir = Join-Path $env:ProgramData 'RdpVirtualBoxApp\Config'
$webPort = 8001
$apiPort = 8444
$httpsPort = 8445

foreach ($name in @('customers.json', 'probe-api.json')) {
    $p = Join-Path $cfgDir $name
    if (Test-Path -LiteralPath $p) {
        try {
            $j = Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($j.webPort) { $webPort = [int]$j.webPort }
            if ($j.port) { $apiPort = [int]$j.port }
            if ($j.httpsPort) { $httpsPort = [int]$j.httpsPort }
        } catch { }
    }
}

foreach ($u in @(
        "http://127.0.0.1:${webPort}/download",
        "http://127.0.0.1:${apiPort}/download",
        "https://127.0.0.1:${httpsPort}/download"
    )) {
    if (-not $candidates.Contains($u)) { [void]$candidates.Add($u) }
}

$open = $candidates[0]
foreach ($u in $candidates) {
    try {
        $r = Invoke-WebRequest -Uri $u -UseBasicParsing -TimeoutSec 3 -MaximumRedirection 0
        if ($r.StatusCode -ge 200 -and $r.StatusCode -lt 500) {
            $open = $u
            break
        }
    } catch {
        if ($_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 200) {
            $open = $u
            break
        }
    }
}

Start-Process $open
Write-Output $open
