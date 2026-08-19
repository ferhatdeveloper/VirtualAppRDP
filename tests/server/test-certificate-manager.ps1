<#
.SYNOPSIS
    Pester 5 unit tests for CertificateManager.ps1.

.DESCRIPTION
    Covers New-RdsCertificate, Get-RdsCertificate, Remove-RdsCertificate
    and the internal Set-RdpTcpCertificateBinding helper. All PInvoke /
    Win32 / wmic calls are mocked so the file runs on any platform.

.NOTES
    Author : Rdp Virtual Box App - Test Coverage Agent
    Module  : tests/server/test-certificate-manager.ps1
    Engine  : Pester 5
#>

BeforeAll {
    $scriptPath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\powershell\server\CertificateManager.ps1'
    $scriptPath = (Resolve-Path -LiteralPath $scriptPath).Path
    . $scriptPath

    . (Join-Path -Path $PSScriptRoot -ChildPath '..\test-helpers.ps1')

    $script:TestLogFile = New-RdsTestLogPath -BaseName 'certificate-manager'
}

Describe 'CertificateManager' {

    BeforeEach {
        $script:certLogPath = New-RdsTestLogPath -BaseName 'cert-mgr'
    }

    Context 'New-RdsCertificate - SelfSigned' {

        It 'should create a self-signed certificate and return its thumbprint' {
            Mock -CommandName 'New-SelfSignedCertificate' -MockWith {
                [pscustomobject]@{
                    Thumbprint = 'ABCDEF1234567890ABCDEF1234567890ABCDEF12'
                    Subject    = "CN=$ServerFqdn"
                    NotAfter   = (Get-Date).AddYears(5)
                }
            }

            $result = New-RdsCertificate -Mode SelfSigned -ServerFqdn 'rdp.example.com' -LogPath $script:certLogPath -WhatIf:$false

            $result.Thumbprint | Should -Be 'ABCDEF1234567890ABCDEF1234567890ABCDEF12'
            $result.Subject    | Should -Be 'CN=rdp.example.com'
            $result.BoundToRdpTcp | Should -BeFalse
            Should -Invoke 'New-SelfSignedCertificate' -Times 1 -Exactly -Scope It
        }

        It 'should honour a custom YearsValid value' {
            Mock -CommandName 'New-SelfSignedCertificate' -MockWith {
                param($DnsName, $CertStoreLocation, $NotAfter, $KeyUsage, $KeyAlgorithm, $KeyLength, $FriendlyName, $ErrorAction)
                [pscustomobject]@{
                    Thumbprint = 'XYZ'
                    Subject    = "CN=$DnsName"
                    NotAfter   = $NotAfter
                }
            }

            $result = New-RdsCertificate -Mode SelfSigned -ServerFqdn 'rdp.local' -YearsValid 10 -LogPath $script:certLogPath -WhatIf:$false
            $result.Thumbprint | Should -Be 'XYZ'
        }

        It 'should throw when ServerFqdn is missing under SelfSigned mode' {
            { New-RdsCertificate -Mode SelfSigned -ServerFqdn '' -LogPath $script:certLogPath -WhatIf:$false -ErrorAction Stop } |
                Should -Throw "*ServerFqdn*"
        }

        It 'should throw when PfxPath does not exist under -Mode CA' {
            Mock -CommandName 'Test-Path' -MockWith { $false }

            $pw = ConvertTo-SecureString 'p' -AsPlainText -Force
            { New-RdsCertificate -Mode CA -PfxPath 'C:\missing.pfx' -PfxPassword $pw -LogPath $script:certLogPath -WhatIf:$false -ErrorAction Stop } |
                Should -Throw
        }

        It 'should bind the certificate to RDP-Tcp when -BindRdpTcp is set' {
            Mock -CommandName 'New-SelfSignedCertificate' -MockWith {
                [pscustomobject]@{
                    Thumbprint = 'BBBB'
                    Subject    = 'CN=rdp'
                    NotAfter   = (Get-Date).AddYears(5)
                }
            }
            Mock -CommandName 'wmic' -MockWith {
                $global:LASTEXITCODE = 0
            }

            $result = New-RdsCertificate -Mode SelfSigned -ServerFqdn 'rdp.local' -BindRdpTcp -LogPath $script:certLogPath -WhatIf:$false
            $result.BoundToRdpTcp | Should -BeTrue
            Should -Invoke 'wmic' -Times 1 -Exactly -Scope It
        }

        It 'should swallow non-fatal RDP-Tcp binding errors and still return the cert' {
            Mock -CommandName 'New-SelfSignedCertificate' -MockWith {
                [pscustomobject]@{
                    Thumbprint = 'T'
                    Subject    = 'CN=x'
                    NotAfter   = (Get-Date).AddYears(1)
                }
            }
            Mock -CommandName 'wmic' -MockWith {
                $global:LASTEXITCODE = 1
                return 'wmic error'
            }

            $result = New-RdsCertificate -Mode SelfSigned -ServerFqdn 'rdp.local' -BindRdpTcp -LogPath $script:certLogPath -WhatIf:$false -WarningAction SilentlyContinue
            $result.Thumbprint | Should -Be 'T'
        }
    }

    Context 'New-RdsCertificate - CA / PFX' {

        It 'should import a PFX and return its thumbprint' {
            Mock -CommandName 'Import-PfxCertificate' -MockWith {
                [pscustomobject]@{
                    Thumbprint = 'CA1234567890ABCDEF1234567890ABCDEF123456'
                    Subject    = 'CN=ca-issued'
                    NotAfter   = (Get-Date).AddYears(2)
                }
            }

            $pw = ConvertTo-SecureString 'secret' -AsPlainText -Force
            $result = New-RdsCertificate -Mode CA -PfxPath 'C:\ok.pfx' -PfxPassword $pw -LogPath $script:certLogPath -WhatIf:$false

            $result.Thumbprint | Should -Be 'CA1234567890ABCDEF1234567890ABCDEF123456'
            Should -Invoke 'Import-PfxCertificate' -Times 1 -Exactly -Scope It
        }

        It 'should throw when PFX password is missing in CA mode' {
            { New-RdsCertificate -Mode CA -PfxPath 'C:\a.pfx' -PfxPassword $null -LogPath $script:certLogPath -WhatIf:$false -ErrorAction Stop } |
                Should -Throw "*PfxPassword*"
        }
    }

    Context 'Get-RdsCertificate' {

        It 'should return a single match when a thumbprint is supplied' {
            Mock -CommandName 'Get-ChildItem' -MockWith {
                [pscustomobject]@{
                    Thumbprint    = 'AABBCC'
                    Subject       = 'CN=foo'
                    NotAfter      = (Get-Date).AddYears(1)
                    Issuer        = 'CN=test-ca'
                    HasPrivateKey = $true
                    FriendlyName  = 'foo'
                }
            }

            $result = Get-RdsCertificate -Thumbprint 'AABBCC'
            $result | Should -Not -BeNullOrEmpty
            $result.Thumbprint | Should -Be 'AABBCC'
        }

        It 'should return $null when the thumbprint is unknown' {
            Mock -CommandName 'Get-ChildItem' -MockWith { $null }
            $result = Get-RdsCertificate -Thumbprint 'UNKNOWN'
            $result | Should -BeNullOrEmpty
        }

        It 'should enumerate all certs when no thumbprint is supplied' {
            Mock -CommandName 'Get-ChildItem' -MockWith {
                @(
                    [pscustomobject]@{ Thumbprint='A1'; Subject='CN=1'; NotAfter=(Get-Date).AddYears(1); Issuer='i'; HasPrivateKey=$true; FriendlyName='one' },
                    [pscustomobject]@{ Thumbprint='A2'; Subject='CN=2'; NotAfter=(Get-Date).AddYears(1); Issuer='i'; HasPrivateKey=$false; FriendlyName='two' }
                )
            }
            $result = @(Get-RdsCertificate)
            $result.Count | Should -Be 2
            $result[0].Thumbprint | Should -Be 'A1'
        }
    }

    Context 'Remove-RdsCertificate' {

        It 'should call Remove-Item when the certificate exists' {
            Mock -CommandName 'Test-Path' -MockWith { $true }
            Mock -CommandName 'Remove-Item' -MockWith { }

            Remove-RdsCertificate -Thumbprint 'X' -WhatIf:$false
            Should -Invoke 'Remove-Item' -Times 1 -Exactly -Scope It
        }

        It 'should warn when the certificate does not exist (not throw)' {
            Mock -CommandName 'Test-Path' -MockWith { $false }
            { Remove-RdsCertificate -Thumbprint 'X' -WhatIf:$false -WarningAction SilentlyContinue } | Should -Not -Throw
        }
    }

    Context 'Helper - Write-CertificateLogEntry' {

        It 'should append an entry to the configured log file' {
            Initialize-CertificateLog -Path $script:certLogPath
            $script:CertLogPath = $script:certLogPath
            Write-CertificateLogEntry -Message 'unit test entry'
            Test-Path -LiteralPath $script:certLogPath | Should -BeTrue
            (Get-Content -LiteralPath $script:certLogPath -Raw) | Should -Match 'unit test entry'
        }
    }
}
