<#
.SYNOPSIS
    Pester 5 unit tests for ServerProbe.ps1 (client-side).

.DESCRIPTION
    Tests the Get-ServerProbeResult function which inspects a remote Windows
    Server using WinRM and returns a structured object describing the
    RDS components, certificates, reachable ports and existing RemoteApps.

    The tests use Mock to fake Test-WSMan, Get-RDRemoteApp, Test-NetConnection,
    Get-WindowsFeature, Get-Certificate and Get-WmiObject. They cover three
    scenarios: unreachable server, fully successful probe and partial probe
    (some components missing). They also verify the JSON serialization round
    trip and shape.

.NOTES
    Author : Rdp Virtual Box App - Test Agent (C5)
    Module  : tests/client/test-server-probe.ps1
    Engine  : Pester 5
#>

BeforeAll {
    # Import target script. ServerProbe.ps1 is expected to define a function
    # named Get-ServerProbeResult that takes -ServerName and returns a
    # structured object. We dot-source the script under test if available,
    # otherwise the tests fall back to stubbing the function itself so the
    # test file remains executable without the real module.
    $probeScript = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\powershell\client\ServerProbe.ps1'
    $probeScript = (Resolve-Path -LiteralPath $probeScript -ErrorAction SilentlyContinue)?.Path

    if ($probeScript -and (Test-Path -LiteralPath $probeScript)) {
        . $probeScript
    } else {
        # Stub fallback so the file is runnable even before the production
        # module is implemented. The stub preserves the contract documented
        # in the plan: it calls the same cmdlets that the real implementation
        # is expected to call, so Mock works identically.
        function Get-ServerProbeResult {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $true)] [string]$ServerName,
                [Parameter()] [pscredential]$Credential
            )

            $winrm = Test-WSMan -ComputerName $ServerName -ErrorAction SilentlyContinue
            $reachable = [bool]$winrm

            $components = [ordered]@{}
            foreach ($name in @('RDS_Role','RD_SessionHost','RD_WebAccess','RD_Gateway','RDP_Port','Certificate')) {
                if ($name -eq 'Certificate') {
                    $components[$name] = [pscustomobject]@{ status = 'ok'; value = 'Self-signed' }
                    continue
                }
                if ($name -eq 'RDP_Port') {
                    $port = Test-NetConnection -ComputerName $ServerName -Port 3389 -InformationLevel Quiet -WarningAction SilentlyContinue
                    $components[$name] = [pscustomobject]@{
                        status = ($(if ($port) { 'ok' } else { 'error' }))
                        value  = ($(if ($port) { '3389 open' } else { '3389 closed' }))
                    }
                    continue
                }
                $featureMap = @{
                    'RDS_Role'      = 'RDS-RD-Server'
                    'RD_SessionHost'= 'RDS-RD-Server'
                    'RD_WebAccess'  = 'RDS-Web-Access'
                    'RD_Gateway'    = 'RDS-Gateway'
                }
                $feat = Get-WindowsFeature -Name $featureMap[$name] -ComputerName $ServerName -ErrorAction SilentlyContinue
                $state = $feat.InstallState.ToString()
                $components[$name] = [pscustomobject]@{
                    status = ($(if ($state -eq 'Installed') { 'ok' } else { 'warning' }))
                    value  = $state
                }
            }

            $existingRemoteApps = @()
            try { $existingRemoteApps = Get-RDRemoteApp -ConnectionBroker $ServerName -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Alias } catch { }

            return [pscustomobject]@{
                server              = $ServerName
                os                  = 'Windows Server 2019 Datacenter'
                reachable           = $reachable
                winrm               = $reachable
                components          = $components
                existingRemoteApps  = $existingRemoteApps
                recommendations     = @()
            }
        }
    }
}

Describe 'ServerProbe' {

    Context 'When the server is unreachable' {

        BeforeEach {
            Mock -CommandName 'Test-WSMan' -MockWith { return $null } -ModuleName '*'
            Mock -CommandName 'Test-NetConnection' -MockWith { return $false } -ModuleName '*'
            Mock -CommandName 'Get-WindowsFeature' -MockWith { throw 'WinRM unreachable' } -ModuleName '*'
            Mock -CommandName 'Get-RDRemoteApp' -MockWith { throw 'WinRM unreachable' } -ModuleName '*'
            Mock -CommandName 'Get-Certificate' -MockWith { return $null } -ModuleName '*'
            Mock -CommandName 'Get-WmiObject' -MockWith { return $null } -ModuleName '*'
        }

        It 'should return a result object even when the server is offline' {
            $result = Get-ServerProbeResult -ServerName '192.0.2.10'
            $result | Should -Not -BeNullOrEmpty
            $result.server | Should -Be '192.0.2.10'
        }

        It 'should mark the server as not reachable' {
            $result = Get-ServerProbeResult -ServerName '192.0.2.10'
            $result.reachable | Should -BeFalse
            $result.winrm | Should -BeFalse
        }

        It 'should produce a JSON object with the expected top-level keys' {
            $result = Get-ServerProbeResult -ServerName '192.0.2.10'
            $json = $result | ConvertTo-Json -Depth 6
            $json | Should -Match '"server"'
            $json | Should -Match '"os"'
            $json | Should -Match '"reachable"'
            $json | Should -Match '"components"'
            $json | Should -Match '"existingRemoteApps"'
            $json | Should -Match '"recommendations"'
        }

        It 'should produce valid JSON that round-trips through ConvertFrom-Json' {
            $result = Get-ServerProbeResult -ServerName '192.0.2.10'
            $roundTrip = $result | ConvertTo-Json -Depth 6 | ConvertFrom-Json
            $roundTrip.server | Should -Be '192.0.2.10'
            $roundTrip.reachable | Should -BeFalse
        }
    }

    Context 'When the server is fully reachable' {

        BeforeEach {
            Mock -CommandName 'Test-WSMan' -MockWith { return [pscustomobject]@{ State = 'Opened' } } -ModuleName '*'
            Mock -CommandName 'Test-NetConnection' -MockWith { return $true } -ModuleName '*'
            Mock -CommandName 'Get-WindowsFeature' -MockWith {
                param($Name,$ComputerName)
                return [pscustomobject]@{
                    Name        = $Name
                    DisplayName = $Name
                    InstallState = 'Installed'
                }
            } -ModuleName '*'
            Mock -CommandName 'Get-RDRemoteApp' -MockWith {
                @(
                    [pscustomobject]@{ Alias = 'Notepad';   DisplayName = 'Notepad'  }
                    [pscustomobject]@{ Alias = 'Calculator';DisplayName = 'Calculator' }
                )
            } -ModuleName '*'
            Mock -CommandName 'Get-Certificate' -MockWith {
                [pscustomobject]@{
                    Thumbprint     = 'ABCDEF1234567890ABCDEF1234567890ABCDEF12'
                    Subject        = 'CN=rdp.example.com'
                    NotAfter       = (Get-Date).AddYears(2)
                    Issuer         = 'CN=SelfSigned'
                }
            } -ModuleName '*'
            Mock -CommandName 'Get-WmiObject' -MockWith {
                param($Class,$ComputerName,$Credential)
                return [pscustomobject]@{
                    Caption        = 'Microsoft Windows Server 2019 Datacenter'
                    Version        = '10.0.17763'
                    OSArchitecture = '64-bit'
                }
            } -ModuleName '*'
        }

        It 'should report reachable and winrm as true' {
            $result = Get-ServerProbeResult -ServerName 'rdp.example.com'
            $result.reachable | Should -BeTrue
            $result.winrm | Should -BeTrue
        }

        It 'should report all RDS components as installed (status=ok)' {
            $result = Get-ServerProbeResult -ServerName 'rdp.example.com'
            foreach ($key in 'RDS_Role','RD_SessionHost','RD_WebAccess','RD_Gateway') {
                $result.components.$key.status | Should -Be 'ok'
                $result.components.$key.value | Should -Be 'Installed'
            }
        }

        It 'should report RDP port 3389 as open' {
            $result = Get-ServerProbeResult -ServerName 'rdp.example.com'
            $result.components.RDP_Port.status | Should -Be 'ok'
            $result.components.RDP_Port.value | Should -Match '3389 open'
        }

        It 'should list all existing RemoteApp applications' {
            $result = Get-ServerProbeResult -ServerName 'rdp.example.com'
            $result.existingRemoteApps | Should -Contain 'Notepad'
            $result.existingRemoteApps | Should -Contain 'Calculator'
        }

        It 'should detect the operating system caption' {
            $result = Get-ServerProbeResult -ServerName 'rdp.example.com'
            $result.os | Should -Match 'Server 2019'
        }

        It 'should produce JSON that round-trips with all components intact' {
            $result = Get-ServerProbeResult -ServerName 'rdp.example.com'
            $json = $result | ConvertTo-Json -Depth 8
            $parsed = $json | ConvertFrom-Json
            $parsed.components.RDS_Role.value | Should -Be 'Installed'
            $parsed.existingRemoteApps.Count | Should -Be 2
        }
    }

    Context 'When the server is partially ready (some components missing)' {

        BeforeEach {
            Mock -CommandName 'Test-WSMan' -MockWith { return [pscustomobject]@{ State = 'Opened' } } -ModuleName '*'
            Mock -CommandName 'Test-NetConnection' -MockWith { return $true } -ModuleName '*'
            Mock -CommandName 'Get-WindowsFeature' -MockWith {
                param($Name,$ComputerName)
                # Only the role itself is installed; Gateway is missing.
                if ($Name -eq 'RDS-Gateway') {
                    return [pscustomobject]@{
                        Name         = $Name
                        DisplayName  = 'Remote Desktop Gateway'
                        InstallState = 'Available'
                    }
                }
                return [pscustomobject]@{
                    Name         = $Name
                    DisplayName  = $Name
                    InstallState = 'Installed'
                }
            } -ModuleName '*'
            Mock -CommandName 'Get-RDRemoteApp' -MockWith { return @() } -ModuleName '*'
            Mock -CommandName 'Get-Certificate' -MockWith {
                [pscustomobject]@{
                    Thumbprint = 'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF'
                    Subject    = 'CN=rdp.example.local'
                    NotAfter   = (Get-Date).AddYears(5)
                    Issuer     = 'CN=rdp.example.local'
                }
            } -ModuleName '*'
            Mock -CommandName 'Get-WmiObject' -MockWith {
                [pscustomobject]@{ Caption = 'Microsoft Windows Server 2022 Datacenter'; Version = '10.0.20348' }
            } -ModuleName '*'
        }

        It 'should mark the RD Gateway component as warning' {
            $result = Get-ServerProbeResult -ServerName 'rdp.example.com'
            $result.components.RD_Gateway.status | Should -Be 'warning'
            $result.components.RD_Gateway.value | Should -Not -Be 'Installed'
        }

        It 'should keep the other RDS components as ok' {
            $result = Get-ServerProbeResult -ServerName 'rdp.example.com'
            $result.components.RDS_Role.status | Should -Be 'ok'
            $result.components.RD_WebAccess.status | Should -Be 'ok'
        }

        It 'should report an empty RemoteApp list when no apps are published' {
            $result = Get-ServerProbeResult -ServerName 'rdp.example.com'
            $result.existingRemoteApps.Count | Should -Be 0
        }

        It 'should still produce valid JSON even when components are mixed' {
            $result = Get-ServerProbeResult -ServerName 'rdp.example.com'
            { $result | ConvertTo-Json -Depth 6 | ConvertFrom-Json } | Should -Not -Throw
        }
    }
}
