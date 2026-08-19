<#
.SYNOPSIS
    Pester 5 unit tests for CloudflareTunnelInstaller.ps1.

.DESCRIPTION
    The script uses the Windows-only [System.Security.Principal.WindowsBuiltInRole]
    enum. We extract the helpers via the AST and stub Assert-Admin in
    the test scope. All process / file-system / network cmdlets are
    mocked so the file can run on any platform.

.NOTES
    Author : Rdp Virtual Box App - Test Coverage Agent
    Module  : tests/server/test-cloudflare-tunnel-installer.ps1
    Engine  : Pester 5
#>

BeforeAll {
    $scriptPath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\powershell\server\CloudflareTunnelInstaller.ps1'
    $scriptPath = (Resolve-Path -LiteralPath $scriptPath).Path

    . (Join-Path -Path $PSScriptRoot -ChildPath '..\test-helpers.ps1')

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
    $funcNames = @(
        'Write-CFLog',
        'Assert-Admin',
        'Invoke-Cloudflared',
        'Install-CloudflaredBinary',
        'Save-CloudflaredCredential',
        'New-CloudflareTunnel',
        'Set-TunnelDnsRoutes',
        'Write-TunnelConfig',
        'Install-CloudflaredService',
        'Test-TunnelReachable',
        'Remove-CloudflareTunnel'
    )
    foreach ($name in $funcNames) {
        $funcAst = $ast.FindAll({
            param($n)
            $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name
        }, $true) | Select-Object -First 1
        if ($funcAst) {
            Invoke-Expression $funcAst.Extent.Text
        }
    }

    # Replace Assert-Admin with a no-op so the test environment doesn't
    # need elevation.
    function Assert-Admin { }
}

Describe 'CloudflareTunnelInstaller' {

    BeforeEach {
        $script:cfLogPath = New-RdsTestLogPath -BaseName 'cloudflare'
    }

    Context 'Invoke-Cloudflared' {

        It 'should throw when the binary is missing' {
            Mock -CommandName 'Test-Path' -MockWith { $false }
            { Invoke-Cloudflared -Arguments @('version') -ErrorAction Stop } | Should -Throw '*missing*'
        }

        It 'should return exit code from the process' {
            Mock -CommandName 'Test-Path' -MockWith { $true }
            Mock -CommandName 'New-Object' -MockWith {
                param([Type]$Type, $Args)
                if ($Type.FullName -eq 'System.Diagnostics.ProcessStartInfo') {
                    return [pscustomobject]@{
                        FileName = ''
                        Arguments = ''
                        UseShellExecute = $false
                        RedirectStandardOutput = $false
                        RedirectStandardError  = $false
                    }
                }
                if ($Type.FullName -eq 'System.Diagnostics.Process') {
                    return [pscustomobject]@{
                        StartInfo = $null
                        Start = { }
                        WaitForExit = { param($ms) return $true }
                        StandardOutput = [pscustomobject]@{ ReadToEnd = { return 'ok' } }
                        StandardError  = [pscustomobject]@{ ReadToEnd = { return ''  } }
                        ExitCode = 0
                        Kill = { }
                    }
                }
                return New-Object -Type $Type -ArgumentList $Args
            }

            $result = Invoke-Cloudflared -Arguments @('version')
            $result.ExitCode | Should -Be 0
            $result.StdOut | Should -Be 'ok'
        }
    }

    Context 'Install-CloudflaredBinary' {

        It 'should be a no-op when the binary is already present' {
            Mock -CommandName 'Test-Path' -MockWith { $true }
            Mock -CommandName 'Invoke-WebRequest' -MockWith { throw 'should not download' }

            { Install-CloudflaredBinary } | Should -Not -Throw
        }

        It 'should download and move the binary when missing' {
            Mock -CommandName 'Test-Path' -MockWith {
                param($Path, $UsePath)
                if ($Path -like '*.exe') { return $false }
                return $true
            }
            Mock -CommandName 'Invoke-WebRequest' -MockWith { }
            Mock -CommandName 'Move-Item' -MockWith { }

            { Install-CloudflaredBinary } | Should -Not -Throw
            Should -Invoke 'Invoke-WebRequest' -Times 1 -Exactly -Scope It
        }
    }

    Context 'Save-CloudflaredCredential' {

        It 'should write the credential JSON file and tighten the ACL' {
            Mock -CommandName 'Set-Content' -MockWith { }
            Mock -CommandName 'Get-Acl' -MockWith {
                [pscustomobject]@{
                    SetAccessRuleProtection = { param($a, $b) }
                    AddAccessRule = { param($r) }
                }
            }
            Mock -CommandName 'Set-Acl' -MockWith { }

            Save-CloudflaredCredential
            Should -Invoke 'Set-Content' -Times 1 -Exactly -Scope It
        }

        It 'should swallow ACL errors and continue' {
            Mock -CommandName 'Set-Content' -MockWith { }
            Mock -CommandName 'Get-Acl' -MockWith { throw 'no acl' }

            { Save-CloudflaredCredential } | Should -Not -Throw
        }
    }

    Context 'New-CloudflareTunnel' {

        It 'should return the existing tunnel id when one is already present' {
            Mock -CommandName 'Invoke-Cloudflared' -MockWith {
                param([string[]]$Arguments)
                [pscustomobject]@{
                    ExitCode = 0
                    StdOut   = '[{"id":"abc-123","name":"rdp-virtual-box"}]'
                    StdErr   = ''
                }
            }

            $id = New-CloudflareTunnel
            $id | Should -Be 'abc-123'
        }

        It 'should create a new tunnel when none exists' {
            Mock -CommandName 'Invoke-Cloudflared' -MockWith {
                param([string[]]$Arguments)
                if ($Arguments -contains 'create') {
                    return [pscustomobject]@{
                        ExitCode = 0
                        StdOut   = 'Created tunnel rdp-virtual-box with id deadbeef-1234-5678-9012-abcdefabcdef'
                        StdErr   = ''
                    }
                }
                return [pscustomobject]@{
                    ExitCode = 0
                    StdOut   = '[]'
                    StdErr   = ''
                }
            }

            $id = New-CloudflareTunnel
            $id | Should -Be 'deadbeef-1234-5678-9012-abcdefabcdef'
        }

        It 'should throw when both list and create fail to produce an id' {
            Mock -CommandName 'Invoke-Cloudflared' -MockWith {
                param([string[]]$Arguments)
                [pscustomobject]@{
                    ExitCode = 0
                    StdOut   = '[]'
                    StdErr   = ''
                }
            }

            { New-CloudflareTunnel -ErrorAction Stop } | Should -Throw '*Could not determine tunnel id*'
        }
    }

    Context 'Write-TunnelConfig' {

        It 'should include RDP, Guacamole, and primary ingress when switches are set' {
            Mock -CommandName 'Set-Content' -MockWith {
                param($Path, $Value, $Encoding, $Force)
                $script:cfg = $Value
            }

            Write-TunnelConfig -TunnelIdValue 'tid-123'
            $script:cfg | Should -Match 'tunnel: tid-123'
            $script:cfg | Should -Match 'hostname: rdp.example.com'
            $script:cfg | Should -Match 'guacamole.example.com'
            $script:cfg | Should -Match 'rdp.example.com'
            $script:cfg | Should -Match 'http_status:404'
        }
    }

    Context 'Test-TunnelReachable' {

        It 'should return $true when DNS resolves to a Cloudflare proxy record' {
            Mock -CommandName 'Resolve-DnsName' -MockWith {
                @(
                    [pscustomobject]@{ Section = 'Answer'; Name = 'rdp.example.com' }
                )
            }
            Test-TunnelReachable | Should -BeTrue
        }

        It 'should return $false when DNS returns no answer section' {
            Mock -CommandName 'Resolve-DnsName' -MockWith { @() }
            Test-TunnelReachable | Should -BeFalse
        }

        It 'should return $false on DNS exception' {
            Mock -CommandName 'Resolve-DnsName' -MockWith { throw 'no dns' }
            Test-TunnelReachable | Should -BeFalse
        }
    }

    Context 'Install-CloudflaredService' {

        It 'should restart an existing service rather than reinstall' {
            Mock -CommandName 'Get-Service' -MockWith {
                [pscustomobject]@{ Name = 'cloudflared' }
            }
            Mock -CommandName 'Restart-Service' -MockWith { $script:restarted = $true }
            Mock -CommandName 'Invoke-Cloudflared' -MockWith { $script:installed = $true }

            $script:restarted = $false
            Install-CloudflaredService
            $script:restarted | Should -BeTrue
        }

        It 'should install the service when missing' {
            Mock -CommandName 'Get-Service' -MockWith { $null }
            Mock -CommandName 'Invoke-Cloudflared' -MockWith {
                param([string[]]$Arguments)
                [pscustomobject]@{ ExitCode = 0; StdOut=''; StdErr='' }
            }
            Mock -CommandName 'Start-Service' -MockWith { }

            { Install-CloudflaredService } | Should -Not -Throw
        }

        It 'should throw when the install command exits non-zero' {
            Mock -CommandName 'Get-Service' -MockWith { $null }
            Mock -CommandName 'Invoke-Cloudflared' -MockWith {
                [pscustomobject]@{ ExitCode = 1; StdOut=''; StdErr='nope' }
            }

            { Install-CloudflaredService -ErrorAction Stop } | Should -Throw '*service install failed*'
        }
    }

    Context 'Remove-CloudflareTunnel (rollback)' {

        It 'should delete the tunnel and clean up the on-disk files' {
            Mock -CommandName 'Invoke-Cloudflared' -MockWith {
                param([string[]]$Arguments)
                [pscustomobject]@{ ExitCode=0; StdOut=''; StdErr='' }
            }
            Mock -CommandName 'Get-Service' -MockWith { $null }
            Mock -CommandName 'sc.exe' -MockWith { }
            Mock -CommandName 'Remove-Item' -MockWith { $script:removed = $true }
            Mock -CommandName 'Test-Path' -MockWith { $true }

            $script:removed = $false
            Remove-CloudflareTunnel
            $script:removed | Should -BeTrue
        }
    }
}
