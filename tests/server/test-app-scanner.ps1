<#
.SYNOPSIS
    Pester 5 unit tests for AppScanner.ps1.

.DESCRIPTION
    The module's main block orchestrates Get-ChildItem + per-file
    enrichment. We mock Get-ChildItem to return a fixed set of executables
    and verify the resulting catalogue and the JSON serialisation.

.NOTES
    Author : Rdp Virtual Box App - Test Coverage Agent
    Module  : tests/server/test-app-scanner.ps1
    Engine  : Pester 5
#>

BeforeAll {
    $scriptPath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\powershell\server\AppScanner.ps1'
    $scriptPath = (Resolve-Path -LiteralPath $scriptPath).Path
    . $scriptPath

    . (Join-Path -Path $PSScriptRoot -ChildPath '..\test-helpers.ps1')
}

Describe 'AppScanner' {

    Context 'Resolve-AppCategory' {

        It 'should classify ERP-related executables' {
            Resolve-AppCategory -Path 'C:\erp\logo.exe' -Name 'logo.exe' | Should -Be 'erp'
        }

        It 'should classify Office binaries' {
            Resolve-AppCategory -Path 'C:\Office\WINWORD.EXE' -Name 'WINWORD.EXE' | Should -Be 'office'
        }

        It 'should classify browsers' {
            Resolve-AppCategory -Path 'C:\Chrome\chrome.exe' -Name 'chrome.exe' | Should -Be 'browser'
        }

        It 'should classify tools' {
            Resolve-AppCategory -Path 'C:\Tools\7z.exe' -Name '7z.exe' | Should -Be 'tools'
        }

        It 'should default to "custom" for unrecognised executables' {
            Resolve-AppCategory -Path 'C:\MyApp\app.exe' -Name 'app.exe' | Should -Be 'custom'
        }
    }

    Context 'Get-AppIdentifier' {

        It 'should produce a stable SHA-1 hash for the same path+size' {
            $a = Get-AppIdentifier -Path 'C:\Foo\bar.exe' -Size 12345
            $b = Get-AppIdentifier -Path 'c:\foo\BAR.EXE' -Size 12345
            $a | Should -Be $b
        }

        It 'should produce a different id for a different size' {
            $a = Get-AppIdentifier -Path 'C:\Foo\bar.exe' -Size 12345
            $b = Get-AppIdentifier -Path 'C:\Foo\bar.exe' -Size 12346
            $a | Should -Not -Be $b
        }

        It 'should return a 40-character hex string' {
            $id = Get-AppIdentifier -Path 'C:\foo.exe' -Size 1
            $id.Length | Should -Be 40
            $id | Should -Match '^[0-9a-f]{40}$'
        }
    }

    Context 'Get-AppMetadata' {

        It 'should extract version, publisher and icon from FileInfo' {
            $file = [pscustomobject]@{
                FullName = 'C:\app.exe'
                VersionInfo = [pscustomobject]@{
                    FileVersion = '1.2.3.4'
                    CompanyName = 'ACME Corp'
                    IconPath    = 'C:\app.exe,0'
                }
            }
            $meta = Get-AppMetadata -File $file
            $meta.Version   | Should -Be '1.2.3.4'
            $meta.Publisher | Should -Be 'ACME Corp'
            $meta.Icon      | Should -Be 'C:\app.exe,0'
        }

        It 'should return nulls when VersionInfo is missing' {
            $file = [pscustomobject]@{
                FullName = 'C:\nope.exe'
                VersionInfo = $null
            }
            $meta = Get-AppMetadata -File $file
            $meta.Version | Should -BeNullOrEmpty
            $meta.Publisher | Should -BeNullOrEmpty
            $meta.Icon | Should -BeNullOrEmpty
        }
    }

    Context 'Invoke-AppScan' {

        It 'should scan a path and return scanned app objects' {
            Mock -CommandName 'Test-Path' -MockWith { $true }
            Mock -CommandName 'Get-ChildItem' -MockWith {
                @(
                    [pscustomobject]@{
                        FullName = 'C:\App\foo.exe'
                        Name     = 'foo.exe'
                        BaseName = 'foo'
                        Extension = '.exe'
                        Length = 1024
                        VersionInfo = [pscustomobject]@{ FileVersion='1.0'; CompanyName='x'; IconPath='C:\foo.exe,0' }
                    },
                    [pscustomobject]@{
                        FullName = 'C:\App\readme.txt'
                        Name     = 'readme.txt'
                        BaseName = 'readme'
                        Extension = '.txt'
                        Length = 100
                        VersionInfo = $null
                    }
                )
            }

            $result = @(Invoke-AppScan -Paths 'C:\App' -Depth 1 -Excludes @())
            $result.Count | Should -Be 1
            $result[0].path | Should -Be 'C:\App\foo.exe'
            $result[0].name | Should -Be 'foo'
            $result[0].category | Should -Not -BeNullOrEmpty
        }

        It 'should skip files in the exclude list' {
            Mock -CommandName 'Test-Path' -MockWith { $true }
            Mock -CommandName 'Get-ChildItem' -MockWith {
                @(
                    [pscustomobject]@{
                        FullName = 'C:\install.exe'
                        Name     = 'install.exe'
                        BaseName = 'install'
                        Extension = '.exe'
                        Length = 1
                        VersionInfo = $null
                    }
                )
            }

            $result = @(Invoke-AppScan -Paths 'C:\App' -Depth 1 -Excludes @('install.exe'))
            $result.Count | Should -Be 0
        }

        It 'should skip non-existent paths silently' {
            Mock -CommandName 'Test-Path' -MockWith { $false }
            Mock -CommandName 'Get-ChildItem' -MockWith { throw 'should not be called' }

            $result = @(Invoke-AppScan -Paths 'C:\missing' -Depth 1 -Excludes @())
            $result.Count | Should -Be 0
        }

        It 'should only include .exe files' {
            Mock -CommandName 'Test-Path' -MockWith { $true }
            Mock -CommandName 'Get-ChildItem' -MockWith {
                @(
                    [pscustomobject]@{
                        FullName = 'C:\app.exe'
                        Name     = 'app.exe'
                        BaseName = 'app'
                        Extension = '.exe'
                        Length = 1
                        VersionInfo = $null
                    },
                    [pscustomobject]@{
                        FullName = 'C:\app.dll'
                        Name     = 'app.dll'
                        BaseName = 'app'
                        Extension = '.dll'
                        Length = 1
                        VersionInfo = $null
                    }
                )
            }
            $result = @(Invoke-AppScan -Paths 'C:\App' -Depth 1 -Excludes @())
            $result.Count | Should -Be 1
        }
    }

    Context 'ConvertTo-AppJson' {

        It 'should serialise to a compact JSON array' {
            $apps = @([pscustomobject]@{ id='abc'; name='x'; path='C:\x.exe' })
            $json = ConvertTo-AppJson -Apps $apps
            $json | Should -Match '"id":"abc"'
            $json | Should -Match '"name":"x"'
        }

        It 'should produce an empty array for no apps' {
            $json = ConvertTo-AppJson -Apps @()
            $json | Should -Be '[]'
        }
    }

    Context 'Show-AppSummary' {

        It 'should not throw with a populated catalogue' {
            $apps = @(
                [pscustomobject]@{ id='1'; name='a'; path='C:\a.exe'; category='erp' },
                [pscustomobject]@{ id='2'; name='b'; path='C:\b.exe'; category='office' }
            )
            { Show-AppSummary -Apps $apps } | Should -Not -Throw
        }

        It 'should not throw with an empty catalogue' {
            { Show-AppSummary -Apps @() } | Should -Not -Throw
        }
    }
}
