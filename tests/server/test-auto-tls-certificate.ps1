<#
.SYNOPSIS
    Pester tests for Install-AutoTlsCertificate / Get-AutoTlsDnsNames.
#>

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\..\src\powershell\server\CertificateManager.ps1'
    $scriptPath = (Resolve-Path -LiteralPath $scriptPath).Path
    $env:ProgramData = Join-Path ([System.IO.Path]::GetTempPath()) ("rdpvb-autotls-{0}" -f [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $env:ProgramData -Force | Out-Null
    . $scriptPath
}

AfterAll {
    if ($env:ProgramData -and $env:ProgramData -match 'rdpvb-autotls-') {
        Remove-Item -LiteralPath $env:ProgramData -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Auto TLS certificate helpers' {

    It 'Get-AutoTlsDnsNames includes localhost and computer name' {
        $names = Get-AutoTlsDnsNames
        $names | Should -Contain 'localhost'
        $names | Should -Contain '127.0.0.1'
    }

    It 'Get-AutoTlsDnsNames merges ExtraNames and customers.json public IP' {
        $cfgDir = Join-Path $env:ProgramData 'RdpVirtualBoxApp\Config'
        New-Item -ItemType Directory -Path $cfgDir -Force | Out-Null
        @{
            customers = @(@{ id = 'default'; publicIp = '198.51.100.20'; hostname = 'SQLHOST' })
        } | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $cfgDir 'customers.json') -Encoding UTF8

        $names = Get-AutoTlsDnsNames -ExtraNames @('extra.local')
        $names | Should -Contain '198.51.100.20'
        $names | Should -Contain 'SQLHOST'
        $names | Should -Contain 'extra.local'
    }

    It 'Install-AutoTlsCertificate creates cert metadata when New-SelfSignedCertificate is mocked' {
        # Linux CI: cmdlet yok; stub ile Mock edilebilir hale getir.
        if (-not (Get-Command -Name New-SelfSignedCertificate -ErrorAction SilentlyContinue)) {
            function global:New-SelfSignedCertificate {
                param($DnsName, $CertStoreLocation, $NotAfter, $KeyUsage, $KeyAlgorithm, $KeyLength, $FriendlyName, $ErrorAction)
                [pscustomobject]@{ Thumbprint = 'AABBCCDDEEFF00112233445566778899AABBCCDD'; Subject = 'CN=localhost'; NotAfter = (Get-Date).AddYears(5) }
            }
        }
        if (-not (Get-Command -Name Export-Certificate -ErrorAction SilentlyContinue)) {
            function global:Export-Certificate {
                [CmdletBinding()]
                param($Cert, $FilePath, [switch]$Force)
            }
        }
        if (-not (Get-Command -Name Import-Certificate -ErrorAction SilentlyContinue)) {
            function global:Import-Certificate {
                [CmdletBinding()]
                param($FilePath, $CertStoreLocation)
            }
        }

        Mock New-SelfSignedCertificate {
            [pscustomobject]@{
                Thumbprint = 'AABBCCDDEEFF00112233445566778899AABBCCDD'
                Subject    = 'CN=localhost'
                NotAfter   = (Get-Date).AddYears(5)
            }
        }
        Mock Export-Certificate { }
        Mock Import-Certificate { }
        Mock Copy-Item { }
        Mock Set-RdpTcpCertificateBinding { }

        $r = Install-AutoTlsCertificate -DnsNames @('localhost', '10.0.0.1') -BindRdpTcp -ForceNew
        $r.Thumbprint | Should -Be 'AABBCCDDEEFF00112233445566778899AABBCCDD'
        $r.DownloadPath | Should -Be '/sql-bridge.cer'
        $meta = Join-Path $env:ProgramData 'RdpVirtualBoxApp\Config\auto-tls.json'
        Test-Path -LiteralPath $meta | Should -BeTrue
    }
}
