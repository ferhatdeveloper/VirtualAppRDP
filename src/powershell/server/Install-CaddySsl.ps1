#requires -Version 5.1
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script = Join-Path $PSScriptRoot 'CaddySslInstaller.ps1'
if (-not (Test-Path -LiteralPath $script)) { throw "CaddySslInstaller.ps1 bulunamadi: $script" }
& $script
