<#
.SYNOPSIS
    Pester 5 unit tests for RemoteAppPublisher.ps1.

.DESCRIPTION
    The script's "main" block runs at dot-source time and forwards through
    the RDS cmdlets. To exercise the testable units on any platform we
    extract the orchestration helpers via the AST and stub the RDS
    cmdlets (New-RDRemoteApp / Set-RDRemoteApp / Get-RDRemoteApp /
    Get-RDCollection / Get-RDSessionHost / Set-RDSessionHostConfiguration
    / Remove-RDRemoteApp) globally so no real RDS role is required.

.NOTES
    Author : Rdp Virtual Box App - Test Coverage Agent
    Module  : tests/server/test-remote-app-publisher.ps1
    Engine  : Pester 5
#>

BeforeAll {
    $scriptPath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\powershell\server\RemoteAppPublisher.ps1'
    $scriptPath = (Resolve-Path -LiteralPath $scriptPath).Path

    . (Join-Path -Path $PSScriptRoot -ChildPath '..\test-helpers.ps1')

    # Inject stub RDS cmdlets in the global scope *before* dot-sourcing
    # the script. The script's main block will then call these no-ops
    # instead of throwing because the RemoteDesktop module is missing.
    $stubCmdlets = @(
        'New-RDRemoteApp','Set-RDRemoteApp','Get-RDRemoteApp','Remove-RDRemoteApp',
        'Get-RDCollection','Get-RDSessionHost','Set-RDSessionHostConfiguration'
    )
    foreach ($name in $stubCmdlets) {
        if (-not (Get-Command -Name $name -ErrorAction SilentlyContinue)) {
            Set-Item -Path "Function:Global:\$name" -Value { param() }
        }
    }

    # Also stub the global Import-Module so the script's Test-RemoteDesktopModule
    # + Import-RemoteDesktopModule don't try to load a real module during
    # dot-source-time main-block execution.
    function Global:Import-Module {
        param([Parameter(Mandatory)][string]$Name, $ErrorAction)
        return
    }

    # Now safely dot-source the script. The main block will run, fail
    # silently (caught and Write-Error'd) and the functions we test
    # below will be available in the current scope.
    . $scriptPath

    # Restore a real Import-Module so other tests / modules aren't broken.
    Remove-Item -Path 'Function:Global:Import-Module' -Force -ErrorAction SilentlyContinue
}

Describe 'RemoteAppPublisher' {

    Context 'Resolve-RemoteAppAlias' {

        It 'should strip the .exe extension' {
            Resolve-RemoteAppAlias -Executable 'notepad.exe' | Should -Be 'notepad'
        }

        It 'should return the input unchanged when no .exe suffix is present' {
            Resolve-RemoteAppAlias -Executable 'logo' | Should -Be 'logo'
        }

        It 'should return empty for empty input' {
            Resolve-RemoteAppAlias -Executable '' | Should -Be ''
        }
    }

    Context 'ConvertTo-AppObject' {

        It 'should parse a JSON string into an array' {
            $json = '[{"path":"C:\\app.exe","name":"App"}]'
            $result = @(ConvertTo-AppObject -InputObject $json)
            $result.Count | Should -Be 1
            $result[0].path | Should -Be 'C:\app.exe'
        }

        It 'should return an empty array for an empty JSON string' {
            ConvertTo-AppObject -InputObject '' | Should -BeNullOrEmpty
            @(ConvertTo-AppObject -InputObject '').Count | Should -Be 0
        }

        It 'should pass through an existing array' {
            $input = @([pscustomobject]@{ path='C:\a.exe' })
            $result = @(ConvertTo-AppObject -InputObject $input)
            $result.Count | Should -Be 1
            $result[0].path | Should -Be 'C:\a.exe'
        }

        It 'should wrap a single object into an array' {
            $obj = [pscustomobject]@{ path='C:\single.exe' }
            $result = @(ConvertTo-AppObject -InputObject $obj)
            $result.Count | Should -Be 1
        }
    }

    Context 'Publish-RemoteAppFromApp' {

        It 'should create a RemoteApp when none exists' {
            Mock -CommandName 'Get-RDRemoteApp' -MockWith { $null }
            $script:created = $null
            Mock -CommandName 'New-RDRemoteApp' -MockWith {
                param($CollectionName, $FilePath, $Alias, $DisplayName, $FriendlyName, $IconPath, $ShowInWebAccess, $CommandLineSetting, $RequiredCommandLine, $ConnectionBroker, $ErrorAction)
                $script:created = [pscustomobject]@{ Alias = $Alias; Status = 'Created' }
                return $script:created
            }

            $apps = @([pscustomobject]@{ path = 'C:\Windows\System32\notepad.exe'; name = 'Notepad' })
            $results = @(Publish-RemoteAppFromApp -ApplicationList $apps -Collection 'RdpVirtualBoxApp')

            $results.Count | Should -Be 1
            $results[0].Status | Should -Be 'Created'
            $results[0].Alias  | Should -Be 'notepad'
        }

        It 'should update an existing RemoteApp when one already exists' {
            Mock -CommandName 'Get-RDRemoteApp' -MockWith {
                [pscustomobject]@{ Alias = 'notepad'; DisplayName = 'Old' }
            }
            Mock -CommandName 'Set-RDRemoteApp' -MockWith {
                param($CollectionName, $Alias, $FilePath, $DisplayName, $ErrorAction)
                [pscustomobject]@{ Alias = $Alias; Status = 'Updated' }
            }

            $apps = @([pscustomobject]@{ path = 'C:\Windows\System32\notepad.exe'; name = 'Notepad' })
            $results = @(Publish-RemoteAppFromApp -ApplicationList $apps -Collection 'RdpVirtualBoxApp')

            $results[0].Status | Should -Be 'Updated'
        }

        It 'should skip apps without a path' {
            $results = @(Publish-RemoteAppFromApp -ApplicationList @([pscustomobject]@{ name='NoPath' }) -Collection 'C')
            $results[0].Status | Should -Be 'Skipped'
        }

        It 'should pass an empty array when the catalogue is empty' {
            $results = @(Publish-RemoteAppFromApp -ApplicationList @() -Collection 'C')
            $results.Count | Should -Be 0
        }

        It 'should pass the ConnectionBroker to New-RDRemoteApp when supplied' {
            Mock -CommandName 'Get-RDRemoteApp' -MockWith { $null }
            $script:broker = $null
            Mock -CommandName 'New-RDRemoteApp' -MockWith {
                param($CollectionName, $FilePath, $Alias, $DisplayName, $FriendlyName, $IconPath, $ShowInWebAccess, $CommandLineSetting, $RequiredCommandLine, $ConnectionBroker, $ErrorAction)
                $script:broker = $ConnectionBroker
                return [pscustomobject]@{ Alias = $Alias; Status='Created' }
            }

            $apps = @([pscustomobject]@{ path = 'C:\a.exe' })
            Publish-RemoteAppFromApp -ApplicationList $apps -Collection 'C' -Broker 'broker.local'
            $script:broker | Should -Be 'broker.local'
        }
    }

    Context 'Remove-RemoteAppRollback' {

        It 'should call Remove-RDRemoteApp with the right parameters' {
            Mock -CommandName 'Remove-RDRemoteApp' -MockWith {
                param($CollectionName, $Alias, $Force, $ConnectionBroker, $ErrorAction)
                $script:rb = [pscustomobject]@{ Collection = $CollectionName; Alias = $Alias }
            }

            Remove-RemoteAppRollback -Alias 'notepad' -Collection 'RdpVirtualBoxApp'
            $script:rb.Alias | Should -Be 'notepad'
            $script:rb.Collection | Should -Be 'RdpVirtualBoxApp'
        }
    }

    Context 'Get-RemoteAppCollectionStatus' {

        It 'should report CollectionExists=False when the collection is missing' {
            Mock -CommandName 'Get-RDCollection' -MockWith { $null }
            $status = Get-RemoteAppCollectionStatus -Collection 'Missing'
            $status.CollectionExists | Should -BeFalse
        }

        It 'should populate SessionHosts and PublishedRemoteApps when the collection exists' {
            Mock -CommandName 'Get-RDCollection' -MockWith {
                [pscustomobject]@{ Name = 'RdpVirtualBoxApp' }
            }
            Mock -CommandName 'Get-RDSessionHost' -MockWith {
                @(
                    [pscustomobject]@{ SessionHost = 'sh1.local' },
                    [pscustomobject]@{ SessionHost = 'sh2.local' }
                )
            }
            Mock -CommandName 'Get-RDRemoteApp' -MockWith {
                @(
                    [pscustomobject]@{ Alias = 'notepad' },
                    [pscustomobject]@{ Alias = 'calc' }
                )
            }
            $status = Get-RemoteAppCollectionStatus -Collection 'RdpVirtualBoxApp'
            $status.CollectionExists | Should -BeTrue
            $status.SessionHosts.Count | Should -Be 2
            $status.PublishedRemoteApps | Should -Contain 'notepad'
            $status.PublishedRemoteApps | Should -Contain 'calc'
        }
    }

    Context 'Test-RemoteDesktopModule' {

        It 'should return $true when the module is listable' {
            Mock -CommandName 'Get-Module' -MockWith {
                [pscustomobject]@{ Name = 'RemoteDesktop' }
            }
            Test-RemoteDesktopModule | Should -BeTrue
        }

        It 'should return $false when the module is not available' {
            Mock -CommandName 'Get-Module' -MockWith { $null }
            Test-RemoteDesktopModule | Should -BeFalse
        }
    }
}
