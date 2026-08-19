<#
.SYNOPSIS
    Pester 5 unit tests for RDGatewayInstaller.ps1.

.DESCRIPTION
    Covers Install-RDGateway, Uninstall-RDGateway and Get-RDGatewayStatus
    with all RDS / WMI / cert store cmdlets mocked.

.NOTES
    Author : Rdp Virtual Box App - Test Coverage Agent
    Module  : tests/server/test-rd-gateway-installer.ps1
    Engine  : Pester 5
#>

BeforeAll {
    $scriptPath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\powershell\server\RDGatewayInstaller.ps1'
    $scriptPath = (Resolve-Path -LiteralPath $scriptPath).Path
    . $scriptPath

    . (Join-Path -Path $PSScriptRoot -ChildPath '..\test-helpers.ps1')
}

Describe 'RDGatewayInstaller' {

    BeforeEach {
        $script:rdgLogPath = New-RdsTestLogPath -BaseName 'rd-gateway'
    }

    Context 'Install-RDGateway' {

        It 'should report success when all roles are installed' {
            Mock -CommandName 'Install-WindowsFeature' -MockWith {
                param($Name, $IncludeManagementTools, $ErrorAction)
                [pscustomobject]@{
                    Name          = $Name
                    Success       = $true
                    ExitCode      = 0
                    RestartNeeded = $false
                }
            }
            Mock -CommandName 'Get-RDConnectionAuthorizationPolicy' -MockWith {
                param($Name, $ErrorAction)
                # First call: "does CAP exist?" answer no. Second call: "fetch it to bind" answer yes.
                if ($script:capCallCount -eq 0) {
                    $script:capCallCount++
                    return $null
                }
                return [pscustomobject]@{ Name = 'RdpVirtualBoxApp-CAP' }
            }
            Mock -CommandName 'New-RDAuthorizationPolicy' -MockWith { }
            Mock -CommandName 'Get-RDResourceAuthorizationPolicy' -MockWith {
                param($Name, $ErrorAction)
                if ($script:rapCallCount -eq 0) {
                    $script:rapCallCount++
                    return $null
                }
                return [pscustomobject]@{ Name = 'RdpVirtualBoxApp-RAP' }
            }
            Mock -CommandName 'Set-RDGatewayConfiguration' -MockWith { }
            Mock -CommandName 'Get-ChildItem' -MockWith {
                [pscustomobject]@{ HasPrivateKey = $true }
            }
            Mock -CommandName 'Set-ItemProperty' -MockWith { }

            $script:capCallCount = 0
            $script:rapCallCount = 0

            $result = Install-RDGateway `
                -GatewayHostname 'gateway.example.com' `
                -CertificateThumbprint 'AA:BB:CC' `
                -LogPath $script:rdgLogPath `
                -WhatIf:$false

            $result.Endpoint                | Should -Be 'https://gateway.example.com:443'
            $result.CapName                 | Should -Be 'RdpVirtualBoxApp-CAP'
            $result.RapName                 | Should -Be 'RdpVirtualBoxApp-RAP'
            $result.AllowedUserGroup        | Should -Be 'Domain Users'
            Should -Invoke 'Install-WindowsFeature' -Times 1 -Exactly -Scope It
        }

        It 'should throw when the underlying Install-WindowsFeature reports failure' {
            Mock -CommandName 'Install-WindowsFeature' -MockWith {
                [pscustomobject]@{
                    Name          = 'RDS-Gateway'
                    Success       = $false
                    ExitCode      = 2
                    RestartNeeded = $false
                }
            }

            { Install-RDGateway -GatewayHostname 'gw' -LogPath $script:rdgLogPath -WhatIf:$false -ErrorAction Stop } |
                Should -Throw '*RDS-Gateway installation failed*'
        }

        It 'should assign a certificate when -CertificateThumbprint is supplied' {
            Mock -CommandName 'Install-WindowsFeature' -MockWith {
                [pscustomobject]@{ Name=$Name; Success=$true; ExitCode=0; RestartNeeded=$false }
            }
            Mock -CommandName 'Get-ChildItem' -MockWith {
                [pscustomobject]@{ HasPrivateKey = $true }
            }
            Mock -CommandName 'Set-ItemProperty' -MockWith { }
            Mock -CommandName 'Get-RDConnectionAuthorizationPolicy' -MockWith { $null }
            Mock -CommandName 'New-RDAuthorizationPolicy' -MockWith { }
            Mock -CommandName 'Get-RDResourceAuthorizationPolicy' -MockWith { $null }
            Mock -CommandName 'Set-RDGatewayConfiguration' -MockWith { }

            Install-RDGateway -GatewayHostname 'gw' -CertificateThumbprint 'AA' -LogPath $script:rdgLogPath -WhatIf:$false
            Should -Invoke 'Set-ItemProperty' -Times 1 -Exactly -Scope It
        }

        It 'should skip cert assignment when the certificate has no private key' {
            Mock -CommandName 'Install-WindowsFeature' -MockWith {
                [pscustomobject]@{ Name=$Name; Success=$true; ExitCode=0; RestartNeeded=$false }
            }
            Mock -CommandName 'Get-ChildItem' -MockWith {
                [pscustomobject]@{ HasPrivateKey = $false }
            }
            Mock -CommandName 'Get-RDConnectionAuthorizationPolicy' -MockWith { $null }
            Mock -CommandName 'New-RDAuthorizationPolicy' -MockWith { }
            Mock -CommandName 'Get-RDResourceAuthorizationPolicy' -MockWith { $null }
            Mock -CommandName 'Set-RDGatewayConfiguration' -MockWith { }

            { Install-RDGateway -GatewayHostname 'gw' -CertificateThumbprint 'AA' -LogPath $script:rdgLogPath -WhatIf:$false -ErrorAction Stop } |
                Should -Throw '*private key*'
        }

        It 'should skip CAP/RAP creation when they already exist' {
            Mock -CommandName 'Install-WindowsFeature' -MockWith {
                [pscustomobject]@{ Name=$Name; Success=$true; ExitCode=0; RestartNeeded=$false }
            }
            Mock -CommandName 'Get-RDConnectionAuthorizationPolicy' -MockWith {
                [pscustomobject]@{ Name = 'RdpVirtualBoxApp-CAP' }
            }
            Mock -CommandName 'Get-RDResourceAuthorizationPolicy' -MockWith {
                [pscustomobject]@{ Name = 'RdpVirtualBoxApp-RAP' }
            }
            Mock -CommandName 'New-RDAuthorizationPolicy' -MockWith { }
            Mock -CommandName 'Set-RDGatewayConfiguration' -MockWith { }

            Install-RDGateway -GatewayHostname 'gw' -LogPath $script:rdgLogPath -WhatIf:$false
            Should -Invoke 'New-RDAuthorizationPolicy' -Times 0 -Exactly -Scope It
        }

        It 'should honour custom GatewayPort and AllowedUserGroup' {
            Mock -CommandName 'Install-WindowsFeature' -MockWith {
                [pscustomobject]@{ Name=$Name; Success=$true; ExitCode=0; RestartNeeded=$false }
            }
            Mock -CommandName 'Get-RDConnectionAuthorizationPolicy' -MockWith { $null }
            Mock -CommandName 'New-RDAuthorizationPolicy' -MockWith { }
            Mock -CommandName 'Get-RDResourceAuthorizationPolicy' -MockWith { $null }
            Mock -CommandName 'Set-RDGatewayConfiguration' -MockWith { }

            $result = Install-RDGateway `
                -GatewayHostname 'gw' `
                -GatewayPort 8443 `
                -AllowedUserGroup 'RDP-Users' `
                -AllowedResourceGroup 'RDP-Computers' `
                -LogPath $script:rdgLogPath `
                -WhatIf:$false

            $result.Endpoint | Should -Be 'https://gw:8443'
            $result.AllowedUserGroup    | Should -Be 'RDP-Users'
            $result.AllowedResourceGroup | Should -Be 'RDP-Computers'
        }
    }

    Context 'Uninstall-RDGateway' {

        It 'should remove CAP/RAP and the feature' {
            Mock -CommandName 'Get-RDConnectionAuthorizationPolicy' -MockWith {
                [pscustomobject]@{ Name = 'RdpVirtualBoxApp-CAP' }
            }
            Mock -CommandName 'Get-RDResourceAuthorizationPolicy' -MockWith {
                [pscustomobject]@{ Name = 'RdpVirtualBoxApp-RAP' }
            }
            Mock -CommandName 'Remove-RDAuthorizationPolicy' -MockWith { }
            Mock -CommandName 'Uninstall-WindowsFeature' -MockWith {
                param($Name, $Remove, $ErrorAction)
                [pscustomobject]@{ Name=$Name; Success=$true; ExitCode=0 }
            }

            $ok = Uninstall-RDGateway -LogPath $script:rdgLogPath -WhatIf:$false
            $ok | Should -BeTrue
            Should -Invoke 'Remove-RDAuthorizationPolicy' -Times 2 -Exactly -Scope It
            Should -Invoke 'Uninstall-WindowsFeature' -Times 1 -Exactly -Scope It
        }

        It 'should return $false when uninstall reports failure' {
            Mock -CommandName 'Get-RDConnectionAuthorizationPolicy' -MockWith { $null }
            Mock -CommandName 'Get-RDResourceAuthorizationPolicy' -MockWith { $null }
            Mock -CommandName 'Uninstall-WindowsFeature' -MockWith {
                [pscustomobject]@{ Name=$Name; Success=$false; ExitCode=2 }
            }

            $ok = Uninstall-RDGateway -LogPath $script:rdgLogPath -WhatIf:$false
            $ok | Should -BeFalse
        }
    }

    Context 'Get-RDGatewayStatus' {

        It 'should report Installed=True when the feature is present' {
            Mock -CommandName 'Get-WindowsFeature' -MockWith {
                [pscustomobject]@{ Name='RDS-Gateway'; InstallState='Installed' }
            }
            Mock -CommandName 'Get-RDConnectionAuthorizationPolicy' -MockWith {
                [pscustomobject]@{ Name = 'RdpVirtualBoxApp-CAP' }
            }
            Mock -CommandName 'Get-RDResourceAuthorizationPolicy' -MockWith {
                [pscustomobject]@{ Name = 'RdpVirtualBoxApp-RAP' }
            }

            $status = Get-RDGatewayStatus
            $status.Installed | Should -BeTrue
            $status.CapExists | Should -BeTrue
            $status.RapExists | Should -BeTrue
            $status.RestartNeeded | Should -BeFalse
        }

        It 'should report RestartNeeded when feature is pending' {
            Mock -CommandName 'Get-WindowsFeature' -MockWith {
                [pscustomobject]@{ Name='RDS-Gateway'; InstallState='InstallPending' }
            }
            Mock -CommandName 'Get-RDConnectionAuthorizationPolicy' -MockWith { $null }
            Mock -CommandName 'Get-RDResourceAuthorizationPolicy' -MockWith { $null }

            $status = Get-RDGatewayStatus
            $status.RestartNeeded | Should -BeTrue
        }

        It 'should report Installed=False and CapExists=False when nothing is installed' {
            Mock -CommandName 'Get-WindowsFeature' -MockWith { $null }
            Mock -CommandName 'Get-RDConnectionAuthorizationPolicy' -MockWith { $null }
            Mock -CommandName 'Get-RDResourceAuthorizationPolicy' -MockWith { $null }

            $status = Get-RDGatewayStatus
            $status.Installed | Should -BeFalse
            $status.CapExists | Should -BeFalse
            $status.RapExists | Should -BeFalse
        }
    }
}
