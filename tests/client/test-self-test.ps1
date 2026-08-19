<#
.SYNOPSIS
    Pester 5 unit tests for SelfTest.ps1.

.DESCRIPTION
    The four exposed functions (Test-ServerConnection, Test-WebEndpoint,
    Test-Credential, Start-DiagnosticReport) need real network calls to
    run end-to-end. We mock the network cmdlets so the assertions can
    run on any platform.

.NOTES
    Author : Rdp Virtual Box App - Test Coverage Agent
    Module  : tests/client/test-self-test.ps1
    Engine  : Pester 5
#>

BeforeAll {
    $scriptPath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\powershell\client\SelfTest.ps1'
    $scriptPath = (Resolve-Path -LiteralPath $scriptPath).Path
    . $scriptPath

    . (Join-Path -Path $PSScriptRoot -ChildPath '..\test-helpers.ps1')
}

Describe 'SelfTest' {

    Context 'Test-ServerConnection' {

        It 'should report unreachable when the TCP connection fails' {
            Mock -CommandName 'New-Object' -MockWith {
                param([Type] $Type, [object[]] $Args)
                if ($Type.FullName -eq 'System.Net.Sockets.TcpClient') {
                    return [pscustomobject]@{
                        BeginConnect = { param($s, $p, $cb, $state) return [pscustomobject]@{ AsyncWaitHandle = [pscustomobject]@{ WaitOne = { param($m, $e) return $false } } } }
                        EndConnect   = { }
                        Close        = { }
                        GetStream    = { return [pscustomobject]@{} }
                    }
                }
                if ($Args) {
                    return [System.Activator]::CreateInstance($Type, $Args)
                }
                return [System.Activator]::CreateInstance($Type)
            }

            $result = Test-ServerConnection -Server 'unreachable.invalid' -Port 3389 -TimeoutSeconds 1
            $result.Reachable | Should -BeFalse
            $result.Error     | Should -Match 'timed out'
        }

        It 'should report reachable when the TCP connection succeeds' {
            Mock -CommandName 'New-Object' -MockWith {
                param([Type] $Type, [object[]] $Args)
                if ($Type.FullName -eq 'System.Net.Sockets.TcpClient') {
                    return [pscustomobject]@{
                        BeginConnect = { param($s, $p, $cb, $state) return [pscustomobject]@{ AsyncWaitHandle = [pscustomobject]@{ WaitOne = { param($m, $e) return $true } } } }
                        EndConnect   = { }
                        Close        = { }
                        GetStream    = { return [pscustomobject]@{
                            ReadTimeout = 0
                            Read = { param($buf, $off, $len) return 0 }
                            Close = { }
                        } }
                    }
                }
                if ($Args) {
                    return [System.Activator]::CreateInstance($Type, $Args)
                }
                return [System.Activator]::CreateInstance($Type)
            }

            $result = Test-ServerConnection -Server '127.0.0.1' -Port 3389 -TimeoutSeconds 1
            $result.Reachable | Should -BeTrue
        }

        It 'should record the SocketException message and not throw' {
            Mock -CommandName 'New-Object' -MockWith {
                param([Type] $Type, [object[]] $Args)
                throw [System.Net.Sockets.SocketException]::new()
            }

            $result = Test-ServerConnection -Server 'broken' -Port 3389 -TimeoutSeconds 1
            $result.Reachable | Should -BeFalse
            $result.Error     | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Test-WebEndpoint' {

        It 'should default to https when the URL has no scheme' {
            Mock -CommandName 'New-Object' -MockWith {
                param([Type] $Type, [object[]] $Args)
                if ($Type.FullName -eq 'System.Net.HttpWebRequest') {
                    return [pscustomobject]@{
                        Method = 'GET'
                        Timeout = 1
                        ReadWriteTimeout = 1
                        UserAgent = ''
                        AllowAutoRedirect = $false
                        ServerCertificateValidationCallback = $null
                        GetResponse = { throw [System.Net.WebException]::new('not found') }
                    }
                }
                if ($Args) {
                    return [System.Activator]::CreateInstance($Type, $Args)
                }
                return [System.Activator]::CreateInstance($Type)
            }

            $result = Test-WebEndpoint -Url 'no-scheme.example.com' -TimeoutSeconds 1
            $result.Url | Should -Be 'https://no-scheme.example.com'
            $result.Error | Should -Not -BeNullOrEmpty
        }

        It 'should treat 401 as reachable (auth required)' {
            Mock -CommandName 'New-Object' -MockWith {
                param([Type] $Type, [object[]] $Args)
                if ($Type.FullName -eq 'System.Net.HttpWebRequest') {
                    return [pscustomobject]@{
                        Method = 'GET'
                        Timeout = 1
                        ReadWriteTimeout = 1
                        UserAgent = ''
                        AllowAutoRedirect = $false
                        ServerCertificateValidationCallback = $null
                        GetResponse = {
                            $ex = [System.Net.WebException]::new('Unauthorized')
                            $resp = [pscustomobject]@{ StatusCode = 401 }
                            $ex | Add-Member -NotePropertyName Response -NotePropertyValue $resp -Force
                            throw $ex
                        }
                    }
                }
                if ($Args) {
                    return [System.Activator]::CreateInstance($Type, $Args)
                }
                return [System.Activator]::CreateInstance($Type)
            }

            $result = Test-WebEndpoint -Url 'https://auth.example.com' -TimeoutSeconds 1
            $result.StatusCode | Should -Be 401
            $result.Reachable | Should -BeTrue
            $result.IsExpected | Should -BeTrue
        }
    }

    Context 'Test-Credential' {

        It 'should report success when WinRM accepts the credentials' {
            Mock -CommandName 'New-PSSession' -MockWith {
                [pscustomobject]@{ Id = 1; ComputerName = 'srv' }
            }
            Mock -CommandName 'Remove-PSSession' -MockWith { }

            $pw = ConvertTo-SecureString 'p' -AsPlainText -Force
            $result = Test-Credential -Server 'srv' -UserName 'admin' -Password $pw -Method WinRM
            $result.Success | Should -BeTrue
            $result.Method | Should -Be 'WinRM'
        }

        It 'should report failure when WinRM rejects the credentials' {
            Mock -CommandName 'New-PSSession' -MockWith { throw 'access denied' }

            $pw = ConvertTo-SecureString 'p' -AsPlainText -Force
            $result = Test-Credential -Server 'srv' -UserName 'admin' -Password $pw -Method WinRM
            $result.Success | Should -BeFalse
            $result.Error | Should -Match 'access denied'
        }

        It 'should use Get-WmiObject to probe the SMB path' {
            Mock -CommandName 'Get-WmiObject' -MockWith {
                [pscustomobject]@{ Caption = 'Microsoft Windows Server' }
            }

            $pw = ConvertTo-SecureString 'p' -AsPlainText -Force
            $result = Test-Credential -Server 'srv' -UserName 'admin' -Password $pw -Method SMB
            $result.Success | Should -BeTrue
            $result.Method | Should -Be 'SMB'
        }
    }

    Context 'Start-DiagnosticReport' {

        It 'should produce a summary object with the right booleans' {
            Mock -CommandName 'Test-ServerConnection' -MockWith {
                [pscustomobject]@{ Server='srv'; Port=3389; Reachable=$true; LatencyMs=10; RdpBanner=''; Error='' }
            }
            Mock -CommandName 'Test-WebEndpoint' -MockWith {
                [pscustomobject]@{ Url='https://x'; Reachable=$true; StatusCode=200; ServerHeader='s'; Title=''; Error=''; IsExpected=$true }
            }
            Mock -CommandName 'Test-Credential' -MockWith {
                [pscustomobject]@{ Server='srv'; User='u'; Method='WinRM'; Success=$true; Error='' }
            }

            $pw = ConvertTo-SecureString 'p' -AsPlainText -Force
            $report = Start-DiagnosticReport -Server 'srv' -WebUrl 'https://x' -Username 'u' -Password $pw
            $report.summary.tcpOk | Should -BeTrue
            $report.summary.webOk | Should -BeTrue
            $report.summary.credentialOk | Should -BeTrue
            $report.summary.overall | Should -BeTrue
        }

        It 'should write a JSON file when -OutputPath is supplied' {
            $temp = New-RdsTestLogPath -BaseName 'diagnostic'
            Mock -CommandName 'Test-ServerConnection' -MockWith {
                [pscustomobject]@{ Server='srv'; Port=3389; Reachable=$true; LatencyMs=0; RdpBanner=''; Error='' }
            }
            Mock -CommandName 'Out-File' -MockWith { $script:outWritten = $true }

            $script:outWritten = $false
            Start-DiagnosticReport -Server 'srv' -OutputPath $temp
            $script:outWritten | Should -BeTrue
        }

        It 'should treat the absence of Web/Credential inputs as a pass' {
            Mock -CommandName 'Test-ServerConnection' -MockWith {
                [pscustomobject]@{ Server='srv'; Port=3389; Reachable=$true; LatencyMs=0; RdpBanner=''; Error='' }
            }
            $report = Start-DiagnosticReport -Server 'srv'
            $report.summary.overall | Should -BeTrue
            $report.summary.webOk | Should -BeTrue
            $report.summary.credentialOk | Should -BeTrue
        }
    }
}
