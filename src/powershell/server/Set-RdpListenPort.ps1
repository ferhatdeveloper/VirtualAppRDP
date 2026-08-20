#requires -Version 5.1
<#
.SYNOPSIS
    RDP TCP portunu degistirir, firewall ve .rdp dosyalarini gunceller.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateRange(1, 65535)]
    [int]$Port = 0,

    [switch]$Restart
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$probe = Join-Path $PSScriptRoot 'ProbeApi.ps1'
$fw    = Join-Path $PSScriptRoot 'FirewallConfig.ps1'
. $probe
if (Test-Path -LiteralPath $fw) { . $fw }

if ($Port -lt 1) { $Port = Get-ConfiguredRdpPort }

$cfg = Get-ProbeApiConfig
$cfg.rdpPort = $Port
Save-ProbeApiConfig -Config $cfg
$env:RDPVB_RDP_PORT = [string]$Port

$epPath = Join-Path $env:ProgramData 'RdpVirtualBoxApp\Config\client-endpoints.json'
if (Test-Path -LiteralPath $epPath) {
    try {
        $j = Get-Content -LiteralPath $epPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $j | Add-Member -NotePropertyName rdpPort -NotePropertyValue $Port -Force
        $j | ConvertTo-Json | Set-Content -LiteralPath $epPath -Encoding UTF8
    } catch {}
}

$tcpKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'
if (Test-Path -LiteralPath $tcpKey) {
    Set-ItemProperty -LiteralPath $tcpKey -Name PortNumber -Value $Port -Type DWord -Force
}
$legacy = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\Wds\rdpwd\Tds\tcp'
if (Test-Path -LiteralPath $legacy) {
    Set-ItemProperty -LiteralPath $legacy -Name PortNumber -Value $Port -Type DWord -Force
}

if (Get-Command -Name Set-RdpVirtualBoxAppFirewall -ErrorAction SilentlyContinue) {
    Set-RdpVirtualBoxAppFirewall -RdpPort $Port -ErrorAction SilentlyContinue | Out-Null
}

try {
    $udpName = "RdpVirtualBoxApp - RDP UDP $Port"
    if (-not (Get-NetFirewallRule -DisplayName $udpName -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName $udpName -Direction Inbound -Action Allow -Protocol UDP -LocalPort $Port -Profile Any -Enabled True -ErrorAction SilentlyContinue | Out-Null
    }
} catch {}

$files = @(Save-RemoteAppRdpFiles)

if ($Restart) {
    Restart-Service -Name TermService -Force -ErrorAction SilentlyContinue
}

Write-Output ([pscustomobject]@{
    Success = $true
    Port    = $Port
    Files   = $files
})
