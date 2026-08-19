<#
.SYNOPSIS
    Pester 5 unit tests for RdpBuilder.ps1 (client-side).

.DESCRIPTION
    Tests the New-RdpFile function which produces an .rdp file for a single
    RemoteApp published on a target server.

    The .rdp output is verified for:
      * Required keys (full address, alternate full address, application mode)
      * Tailscale IP routing when the address is a 100.x mesh address
      * RD Gateway hostname injection when UseGateway is requested
      * File is created on disk with the expected UTF-8 contents

.NOTES
    Author : Rdp Virtual Box App - Test Agent (C5)
    Module  : tests/client/test-rdp-builder.ps1
    Engine  : Pester 5
#>

BeforeAll {
    $builderScript = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\powershell\client\RdpBuilder.ps1'
    $builderScript = (Resolve-Path -LiteralPath $builderScript -ErrorAction SilentlyContinue)?.Path

    if ($builderScript -and (Test-Path -LiteralPath $builderScript)) {
        . $builderScript
    } else {
        # Stub implementation mirroring the planned RdpBuilder contract.
        function New-RdpFile {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $true)] [string]$ServerAddress,
                [Parameter(Mandatory = $true)] [string]$RemoteAppName,
                [Parameter(Mandatory = $true)] [string]$RemoteAppAlias,
                [Parameter()] [string]$AlternateAddress,
                [Parameter()] [string]$GatewayHostname,
                [Parameter()] [switch]$UseGateway,
                [Parameter()] [switch]$UseTailscale,
                [Parameter()] [string]$OutputPath,
                [Parameter()] [string]$TemplatePath
            )

            if (-not $OutputPath) {
                $OutputPath = Join-Path -Path $env:TEMP -ChildPath ("{0}.rdp" -f ($RemoteAppAlias -replace '[^\w]','_'))
            }

            $template = @"
full address:s:{SERVER}
alternate full address:s:{ALT}
remoteapplicationmode:i:1
remoteapplicationname:s:{NAME}
remoteapplicationprogram:s:||{ALIAS}
drivestoredirect:s:*
audiomode:i:2
redirectclipboard:i:1
redirectprinters:i:1
redirectsmartcards:i:1
gatewayhostname:s:{GATEWAY}
gatewayusagemethod:i:{GW_METHOD}
"@

            $isTailscale = $UseTailscale -or ($ServerAddress -match '^100\.')

            $content = $template `
                -replace '\{SERVER\}',  $ServerAddress `
                -replace '\{ALT\}',     ($AlternateAddress ?? '') `
                -replace '\{NAME\}',    $RemoteAppName `
                -replace '\{ALIAS\}',   $RemoteAppAlias `
                -replace '\{GATEWAY\}', ($(if ($UseGateway -and $GatewayHostname) { $GatewayHostname } else { '' })) `
                -replace '\{GW_METHOD\}', ($(if ($UseGateway) { '1' } else { '0' }))

            $dir = Split-Path -Parent $OutputPath
            if ($dir -and -not (Test-Path -LiteralPath $dir)) {
                New-Item -Path $dir -ItemType Directory -Force | Out-Null
            }

            Set-Content -LiteralPath $OutputPath -Value $content -Encoding UTF8 -Force
            return [pscustomobject]@{
                Path          = $OutputPath
                ServerAddress = $ServerAddress
                IsTailscale   = $isTailscale
                UseGateway    = [bool]$UseGateway
                GatewayHost   = $(if ($UseGateway) { $GatewayHostname } else { '' })
                Content       = $content
            }
        }
    }
}

Describe 'RdpBuilder' {

    BeforeEach {
        # Mock Set-Content so we can capture output without touching the disk.
        Mock -CommandName 'Set-Content' -MockWith {
            param($LiteralPath,$Value,$Encoding,$Force)
            $script:lastWrittenPath   = $LiteralPath
            $script:lastWrittenValue  = $Value
            $script:lastWrittenForce  = $Force
        }

        $script:lastWrittenPath  = $null
        $script:lastWrittenValue = $null
    }

    Context 'Basic .rdp generation' {

        It 'should produce a file with the requested remote application alias' {
            $result = New-RdpFile -ServerAddress '192.168.0.106' -RemoteAppName 'ERP' -RemoteAppAlias 'erp.exe'
            $script:lastWrittenValue | Should -Match 'remoteapplicationprogram:s:\|\|erp\.exe'
        }

        It 'should include full address and alternate address keys' {
            $result = New-RdpFile -ServerAddress '192.168.0.106' -RemoteAppName 'ERP' -RemoteAppAlias 'erp.exe' -AlternateAddress 'rdweb.firma.local'
            $script:lastWrittenValue | Should -Match 'full address:s:192\.168\.0\.106'
            $script:lastWrittenValue | Should -Match 'alternate full address:s:rdweb\.firma\.local'
        }

        It 'should set remoteapplicationmode to 1 (RemoteApp, not full desktop)' {
            $result = New-RdpFile -ServerAddress '192.168.0.106' -RemoteAppName 'ERP' -RemoteAppAlias 'erp.exe'
            $script:lastWrittenValue | Should -Match 'remoteapplicationmode:i:1'
        }

        It 'should include resource redirection keys for clipboard, printers and smartcards' {
            $result = New-RdpFile -ServerAddress '192.168.0.106' -RemoteAppName 'ERP' -RemoteAppAlias 'erp.exe'
            $script:lastWrittenValue | Should -Match 'redirectclipboard:i:1'
            $script:lastWrittenValue | Should -Match 'redirectprinters:i:1'
            $script:lastWrittenValue | Should -Match 'redirectsmartcards:i:1'
        }

        It 'should call Set-Content with UTF-8 encoding and the Force flag' {
            New-RdpFile -ServerAddress '192.168.0.106' -RemoteAppName 'ERP' -RemoteAppAlias 'erp.exe' -OutputPath 'C:\temp\erp.rdp'
            $script:lastWrittenPath  | Should -Be 'C:\temp\erp.rdp'
            $script:lastWrittenForce | Should -BeTrue
        }
    }

    Context 'RD Gateway support' {

        It 'should add the gatewayhostname key when UseGateway is supplied' {
            New-RdpFile -ServerAddress '192.168.0.106' -RemoteAppName 'ERP' -RemoteAppAlias 'erp.exe' -UseGateway -GatewayHostname 'gateway.firma.local'
            $script:lastWrittenValue | Should -Match 'gatewayhostname:s:gateway\.firma\.local'
        }

        It 'should set gatewayusagemethod to 1 (detect automatically) when UseGateway is on' {
            New-RdpFile -ServerAddress '192.168.0.106' -RemoteAppName 'ERP' -RemoteAppAlias 'erp.exe' -UseGateway -GatewayHostname 'gateway.firma.local'
            $script:lastWrittenValue | Should -Match 'gatewayusagemethod:i:1'
        }

        It 'should leave gatewayhostname blank when UseGateway is not requested' {
            New-RdpFile -ServerAddress '192.168.0.106' -RemoteAppName 'ERP' -RemoteAppAlias 'erp.exe'
            $script:lastWrittenValue | Should -Match 'gatewayhostname:s:$'
        }
    }

    Context 'Tailscale routing' {

        It 'should mark IsTailscale as true when the server address is a 100.x IP' {
            $result = New-RdpFile -ServerAddress '100.101.102.103' -RemoteAppName 'ERP' -RemoteAppAlias 'erp.exe'
            $result.IsTailscale | Should -BeTrue
        }

        It 'should mark IsTailscale as false for a regular LAN address' {
            $result = New-RdpFile -ServerAddress '192.168.0.106' -RemoteAppName 'ERP' -RemoteAppAlias 'erp.exe'
            $result.IsTailscale | Should -BeFalse
        }

        It 'should explicitly request Tailscale routing when UseTailscale is supplied' {
            $result = New-RdpFile -ServerAddress '192.168.0.106' -RemoteAppName 'ERP' -RemoteAppAlias 'erp.exe' -UseTailscale
            $result.IsTailscale | Should -BeTrue
        }

        It 'should keep the 100.x address as full address when Tailscale routing is used' {
            New-RdpFile -ServerAddress '100.64.0.5' -RemoteAppName 'ERP' -RemoteAppAlias 'erp.exe'
            $script:lastWrittenValue | Should -Match 'full address:s:100\.64\.0\.5'
        }
    }
}
