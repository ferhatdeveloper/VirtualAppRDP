<#
.SYNOPSIS
    Pester 5 unit tests for RdsInstaller.ps1 (server-side).

.DESCRIPTION
    Verifies Install-RdsRole, Uninstall-RdsRole and Get-RdsRoleState using
    Mocked Install-WindowsFeature and Uninstall-WindowsFeature cmdlets.

    Scenarios:
      * Happy path (all features install successfully)
      * Partial install + automatic rollback when a later feature fails
      * Rollback failure does not abort the parent function

.NOTES
    Author : Rdp Virtual Box App - Test Agent (C5)
    Module  : tests/server/test-rds-installer.ps1
    Engine  : Pester 5
#>

BeforeAll {
    # Always dot-source the real implementation under test.
    $scriptPath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\powershell\server\RdsInstaller.ps1'
    $scriptPath = (Resolve-Path -LiteralPath $scriptPath).Path
    . $scriptPath

    # The script writes logs to %ProgramData. Provide a writable log dir
    # for the test process and override the default through -LogPath later.
    $script:TestLogRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath 'RdpVbaTests'
    if (-not (Test-Path -LiteralPath $script:TestLogRoot)) {
        New-Item -Path $script:TestLogRoot -ItemType Directory -Force | Out-Null
    }
}

Describe 'RdsInstaller' {

    BeforeEach {
        $script:TestLogFile = Join-Path -Path $script:TestLogRoot -ChildPath ('rds-installer-{0}.log' -f ([guid]::NewGuid()))

        # Provide a default Install-WindowsFeature result so tests can override
        # it on a per-case basis. Mocks are global because RdsInstaller.ps1
        # is dot-sourced (no module scope).
        Mock -CommandName 'Install-WindowsFeature' -MockWith {
            param($Name,$IncludeManagementTools,$ErrorAction)
            [pscustomobject]@{
                Name          = $Name
                Success       = $true
                ExitCode      = 0
                RestartNeeded = $false
            }
        }

        Mock -CommandName 'Uninstall-WindowsFeature' -MockWith {
            param($Name,$Remove,$ErrorAction)
            [pscustomobject]@{
                Name     = $Name
                Success  = $true
                ExitCode = 0
            }
        }

        Mock -CommandName 'Get-WindowsFeature' -MockWith {
            param($Name,$ErrorAction)
            [pscustomobject]@{
                Name         = $Name
                DisplayName  = $Name
                InstallState = 'Installed'
            }
        }

        Mock -CommandName 'Restart-Computer' -MockWith { }
    }

    Context 'Install-RdsRole - happy path' {

        It 'should return a Success summary when all features install' {
            $result = Install-RdsRole `
                -Features 'RDS-RD-Server','RDS-Web-Access' `
                -IncludeManagementTools `
                -LogPath $script:TestLogFile `
                -WhatIf:$false

            $result.Success | Should -BeTrue
            $result.Installed.Count | Should -Be 2
            $result.Failed.Count    | Should -Be 0
        }

        It 'should call Install-WindowsFeature once per requested feature' {
            $calls = New-Object System.Collections.Generic.List[string]
            Mock -CommandName 'Install-WindowsFeature' -MockWith {
                param($Name,$IncludeManagementTools,$ErrorAction)
                $calls.Add($Name)
                [pscustomobject]@{ Name=$Name; Success=$true; ExitCode=0; RestartNeeded=$false }
            }

            Install-RdsRole -Features 'RDS-RD-Server','RDS-Web-Access','RDS-Gateway' -LogPath $script:TestLogFile
            $calls.Count | Should -Be 3
            $calls | Should -Contain 'RDS-RD-Server'
            $calls | Should -Contain 'RDS-Web-Access'
            $calls | Should -Contain 'RDS-Gateway'
        }

        It 'should write a log file even on success' {
            Install-RdsRole -Features 'RDS-RD-Server' -LogPath $script:TestLogFile
            Test-Path -LiteralPath $script:TestLogFile | Should -BeTrue
            (Get-Content -LiteralPath $script:TestLogFile -Raw) | Should -Match 'Installing feature'
        }
    }

    Context 'Install-RdsRole - rollback on failure' {

        It 'should roll back already installed features when a later one fails' {
            $script:callIndex = 0
            Mock -CommandName 'Install-WindowsFeature' -MockWith {
                param($Name,$IncludeManagementTools,$ErrorAction)
                $script:callIndex++
                # First feature ok, second ok, third fails.
                if ($script:callIndex -eq 3) {
                    return [pscustomobject]@{
                        Name=$Name; Success=$false; ExitCode=2; RestartNeeded=$false
                    }
                }
                return [pscustomobject]@{
                    Name=$Name; Success=$true;  ExitCode=0; RestartNeeded=$false
                }
            }

            $script:rollbackCalls = New-Object System.Collections.Generic.List[string]
            Mock -CommandName 'Uninstall-WindowsFeature' -MockWith {
                param($Name,$Remove,$ErrorAction)
                $script:rollbackCalls.Add($Name)
                [pscustomobject]@{ Name=$Name; Success=$true; ExitCode=0 }
            }

            { Install-RdsRole `
                -Features 'RDS-RD-Server','RDS-Web-Access','RDS-Gateway' `
                -LogPath $script:TestLogFile `
                -ErrorAction Stop } | Should -Throw -ExpectedMessage '*RDS installation failed*'

            # The two features that succeeded should have been rolled back.
            $script:rollbackCalls.Count | Should -Be 2
            $script:rollbackCalls | Should -Contain 'RDS-RD-Server'
            $script:rollbackCalls | Should -Contain 'RDS-Web-Access'
            $script:rollbackCalls | Should -Not -Contain 'RDS-Gateway'
        }

        It 'should not propagate a rollback failure' {
            $script:callIndex = 0
            Mock -CommandName 'Install-WindowsFeature' -MockWith {
                $script:callIndex++
                if ($script:callIndex -eq 2) {
                    return [pscustomobject]@{
                        Name=$null; Success=$false; ExitCode=5; RestartNeeded=$false
                    }
                }
                return [pscustomobject]@{
                    Name=$null; Success=$true; ExitCode=0; RestartNeeded=$false
                }
            }

            Mock -CommandName 'Uninstall-WindowsFeature' -MockWith {
                throw 'Simulated rollback failure'
            }

            # The outer function should still throw "RDS installation failed"
            # rather than "rollback failed".
            { Install-RdsRole -Features 'A','B' -LogPath $script:TestLogFile -ErrorAction Stop } | Should -Throw -ExpectedMessage '*RDS installation failed*'
        }
    }

    Context 'Uninstall-RdsRole' {

        It 'should invoke Uninstall-WindowsFeature for each feature' {
            $script:uninstallCalls = New-Object System.Collections.Generic.List[string]
            Mock -CommandName 'Uninstall-WindowsFeature' -MockWith {
                param($Name,$Remove,$ErrorAction)
                $script:uninstallCalls.Add($Name)
                [pscustomobject]@{ Name=$Name; Success=$true; ExitCode=0 }
            }

            $results = Uninstall-RdsRole -Features 'RDS-RD-Server','RDS-Gateway' -LogPath $script:TestLogFile -WhatIf:$false

            $script:uninstallCalls.Count | Should -Be 2
            $results.Count | Should -Be 2
            ($results | Where-Object { -not $_.Success }).Count | Should -Be 0
        }
    }

    Context 'Get-RdsRoleState' {

        It 'should return a state object for each requested feature' {
            Mock -CommandName 'Get-WindowsFeature' -MockWith {
                param($Name,$ErrorAction)
                [pscustomobject]@{
                    Name         = $Name
                    DisplayName  = $Name
                    InstallState = 'Installed'
                }
            }

            $state = Get-RdsRoleState -Features 'RDS-RD-Server','RDS-Gateway'
            $state.Count | Should -Be 2
            ($state | Where-Object { $_.Installed }).Count | Should -Be 2
        }

        It 'should report NotInstalled when the feature is Available' {
            Mock -CommandName 'Get-WindowsFeature' -MockWith {
                param($Name,$ErrorAction)
                [pscustomobject]@{
                    Name         = $Name
                    DisplayName  = $Name
                    InstallState = 'Available'
                }
            }

            $state = Get-RdsRoleState -Features 'RDS-Gateway'
            $state[0].InstallState | Should -Be 'Available'
            $state[0].Installed    | Should -BeFalse
        }
    }
}
