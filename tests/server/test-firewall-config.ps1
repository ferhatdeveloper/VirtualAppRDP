<#
.SYNOPSIS
    Pester 5 unit tests for FirewallConfig.ps1.

.DESCRIPTION
    Mocks the NetSecurity cmdlets (Get-NetFirewallRule, New-NetFirewallRule,
    Enable/Disable/Remove-NetFirewallRule, Get-NetFirewallProfile) so the
    tests can run on any platform.

.NOTES
    Author : Rdp Virtual Box App - Test Coverage Agent
    Module  : tests/server/test-firewall-config.ps1
    Engine  : Pester 5
#>

BeforeAll {
    $scriptPath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\powershell\server\FirewallConfig.ps1'
    $scriptPath = (Resolve-Path -LiteralPath $scriptPath).Path
    . $scriptPath

    . (Join-Path -Path $PSScriptRoot -ChildPath '..\test-helpers.ps1')
}

Describe 'FirewallConfig' {

    BeforeEach {
        $script:fwLogPath = New-RdsTestLogPath -BaseName 'firewall'
    }

    Context 'Set-RdpVirtualBoxAppFirewall' {

        It 'should create the five default rules when none exist' {
            Mock -CommandName 'Get-NetFirewallRule' -MockWith { $null }
            $script:newCalls = New-Object System.Collections.Generic.List[object]
            Mock -CommandName 'New-NetFirewallRule' -MockWith {
                param($DisplayName, $Direction, $Action, $Protocol, $LocalPort, $Profile, $Enabled, $Description, $RemoteAddress, $ErrorAction)
                $script:newCalls.Add([pscustomobject]@{
                    DisplayName = $DisplayName
                    Port        = $LocalPort
                })
            }

            $result = Set-RdpVirtualBoxAppFirewall -LogPath $script:fwLogPath -WhatIf:$false

            $script:newCalls.Count | Should -Be 5
            ($script:newCalls | ForEach-Object Port) | Should -Contain 3389
            ($script:newCalls | ForEach-Object Port) | Should -Contain 443
            ($script:newCalls | ForEach-Object Port) | Should -Contain 8443
            ($script:newCalls | ForEach-Object Port) | Should -Contain 5985
            ($script:newCalls | ForEach-Object Port) | Should -Contain 5986
            $result.Created.Count   | Should -Be 5
            $result.Existing.Count  | Should -Be 0
        }

        It 'should skip rules that already exist' {
            $script:existsCalls = 0
            Mock -CommandName 'Get-NetFirewallRule' -MockWith {
                param($DisplayName, $ErrorAction)
                # First call returns an "existing" rule, the rest null.
                $script:existsCalls++
                if ($script:existsCalls -eq 1) {
                    return [pscustomobject]@{ DisplayName = $DisplayName; Name = 'rule1' }
                }
                return $null
            }
            Mock -CommandName 'New-NetFirewallRule' -MockWith { }

            $result = Set-RdpVirtualBoxAppFirewall -LogPath $script:fwLogPath -WhatIf:$false

            $result.Existing.Count | Should -Be 1
            $result.Created.Count  | Should -Be 4
        }

        It 'should enable all profiles when -EnableFirewall is supplied' {
            Mock -CommandName 'Get-NetFirewallRule' -MockWith { $null }
            Mock -CommandName 'New-NetFirewallRule' -MockWith { }
            Mock -CommandName 'Set-NetFirewallProfile' -MockWith {
                param($All, $Enabled, $ErrorAction)
                $script:profilesEnabled = $true
            }

            Set-RdpVirtualBoxAppFirewall -EnableFirewall -LogPath $script:fwLogPath -WhatIf:$false
            Should -Invoke 'Set-NetFirewallProfile' -Times 1 -Exactly -Scope It
        }

        It 'should pass AllowedRemoteAddresses to New-NetFirewallRule' {
            Mock -CommandName 'Get-NetFirewallRule' -MockWith { $null }
            $script:passedRemote = $null
            Mock -CommandName 'New-NetFirewallRule' -MockWith {
                param($DisplayName, $Direction, $Action, $Protocol, $LocalPort, $Profile, $Enabled, $Description, $RemoteAddress, $ErrorAction)
                $script:passedRemote = $RemoteAddress
            }

            Set-RdpVirtualBoxAppFirewall -AllowedRemoteAddresses '10.0.0.4','192.168.1.0/24' -LogPath $script:fwLogPath -WhatIf:$false
            $script:passedRemote | Should -Contain '10.0.0.4'
            $script:passedRemote | Should -Contain '192.168.1.0/24'
        }

        It 'should throw when the underlying cmdlet fails' {
            Mock -CommandName 'Get-NetFirewallRule' -MockWith { $null }
            Mock -CommandName 'New-NetFirewallRule' -MockWith { throw 'boom' }

            { Set-RdpVirtualBoxAppFirewall -LogPath $script:fwLogPath -WhatIf:$false -ErrorAction Stop } | Should -Throw '*boom*'
        }
    }

    Context 'Enable/Disable/Remove-RdpVirtualBoxAppRule' {

        It 'should enable all rules when no display name is supplied' {
            Mock -CommandName 'Get-NetFirewallRule' -MockWith {
                @(
                    [pscustomobject]@{ DisplayName = 'RdpVirtualBoxApp - RDP 3389'; Name = 'rule1' },
                    [pscustomobject]@{ DisplayName = 'RdpVirtualBoxApp - HTTPS 443'; Name = 'rule2' }
                )
            }
            Mock -CommandName 'Enable-NetFirewallRule' -MockWith { $script:enableCalls = ($script:enableCalls + 1) }

            $script:enableCalls = 0
            Enable-RdpVirtualBoxAppRule -WhatIf:$false
            $script:enableCalls | Should -Be 2
        }

        It 'should warn when no rule matches the filter' {
            Mock -CommandName 'Get-NetFirewallRule' -MockWith { $null }
            { Enable-RdpVirtualBoxAppRule -DisplayName 'RdpVirtualBoxApp - Unknown' -WhatIf:$false -WarningAction SilentlyContinue } | Should -Not -Throw
        }

        It 'should disable a rule by display name' {
            Mock -CommandName 'Get-NetFirewallRule' -MockWith {
                [pscustomobject]@{ DisplayName = 'RdpVirtualBoxApp - RDP 3389'; Name = 'rule1' }
            }
            Mock -CommandName 'Disable-NetFirewallRule' -MockWith { $script:hit = $true }

            $script:hit = $false
            Disable-RdpVirtualBoxAppRule -DisplayName 'RdpVirtualBoxApp - RDP 3389' -WhatIf:$false
            $script:hit | Should -BeTrue
        }

        It 'should remove all rules when no display name is supplied' {
            Mock -CommandName 'Get-NetFirewallRule' -MockWith {
                @(
                    [pscustomobject]@{ DisplayName = 'RdpVirtualBoxApp - RDP 3389'; Name = 'r1' },
                    [pscustomobject]@{ DisplayName = 'RdpVirtualBoxApp - HTTPS 443'; Name = 'r2' }
                )
            }
            Mock -CommandName 'Remove-NetFirewallRule' -MockWith { $script:removedCalls = ($script:removedCalls + 1) }

            $script:removedCalls = 0
            Remove-RdpVirtualBoxAppRule -WhatIf:$false
            $script:removedCalls | Should -Be 2
        }

        It 'should be a no-op when no rules match' {
            Mock -CommandName 'Get-NetFirewallRule' -MockWith { $null }
            Mock -CommandName 'Remove-NetFirewallRule' -MockWith { throw 'should not be called' }

            { Remove-RdpVirtualBoxAppRule -WhatIf:$false -WarningAction SilentlyContinue } | Should -Not -Throw
        }
    }

    Context 'Get-RdpVirtualBoxAppFirewallStatus' {

        It 'should report the existing profile and rule set' {
            Mock -CommandName 'Get-NetFirewallRule' -MockWith {
                @(
                    [pscustomobject]@{
                        DisplayName = 'RdpVirtualBoxApp - RDP 3389'
                        Direction   = 'Inbound'
                        Action      = 'Allow'
                        Enabled     = 'True'
                        Profile     = 'Any'
                    }
                )
            }
            Mock -CommandName 'Get-NetFirewallPortFilter' -MockWith {
                [pscustomobject]@{ Protocol = 'TCP'; LocalPort = 3389 }
            }
            Mock -CommandName 'Get-NetFirewallProfile' -MockWith {
                @(
                    [pscustomobject]@{ Name='Domain'; Enabled='True'; DefaultInboundAction='Allow'; DefaultOutboundAction='Allow' }
                )
            }

            $status = Get-RdpVirtualBoxAppFirewallStatus
            $status.Rules.Count | Should -Be 1
            $status.Rules[0].LocalPort | Should -Be 3389
            $status.Profiles.Count | Should -Be 1
        }
    }

    Context 'Test-RdpVirtualBoxAppRule' {

        It 'should return $true when a matching rule exists' {
            Mock -CommandName 'Get-NetFirewallRule' -MockWith {
                param($DisplayName, $ErrorAction)
                [pscustomobject]@{ DisplayName = $DisplayName }
            }
            Test-RdpVirtualBoxAppRule -DisplayName 'some' | Should -BeTrue
        }

        It 'should return $false when no rule exists' {
            Mock -CommandName 'Get-NetFirewallRule' -MockWith {
                param($DisplayName, $ErrorAction)
                $null
            }
            Test-RdpVirtualBoxAppRule -DisplayName 'missing' | Should -BeFalse
        }
    }
}
