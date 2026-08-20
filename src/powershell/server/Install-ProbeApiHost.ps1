#requires -Version 5.1
<#
.SYNOPSIS
    Wizard / Inno Setup entry point that installs and starts the Probe REST API.

.DESCRIPTION
    ServerSetupUI.ps1 scripts'i Args olmadan cagirir. Bu sarmalayici
    Start-ProbeApiHost.ps1 -Mode Install'i named parameter ile calistirir
    ki ValidateSet bozulmasin. Web portu ProgramData config / RDPVB_WEB_PORT
    / varsayilan 8001 sirasiyla okunur.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$hostScript = Join-Path $PSScriptRoot 'Start-ProbeApiHost.ps1'
if (-not (Test-Path -LiteralPath $hostScript)) {
    throw "Start-ProbeApiHost.ps1 bulunamadi: $hostScript"
}

function Get-InstallWebPort {
    $envPort = [string]$env:RDPVB_WEB_PORT
    if ($envPort -match '^\d+$') {
        $n = [int]$envPort
        if ($n -ge 1 -and $n -le 65535) { return $n }
    }
    $cfgDir = Join-Path $env:ProgramData 'RdpVirtualBoxApp\Config'
    foreach ($name in @('customers.json', 'probe-api.json')) {
        $p = Join-Path $cfgDir $name
        if (-not (Test-Path -LiteralPath $p)) { continue }
        try {
            $j = Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($j.webPort) {
                $n = [int]$j.webPort
                if ($n -ge 1 -and $n -le 65535) { return $n }
            }
        } catch { }
    }
    return 8001
}

& $hostScript -Mode Install -Port 8444 -WebPort (Get-InstallWebPort)
