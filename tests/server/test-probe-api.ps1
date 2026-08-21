<#
.SYNOPSIS
    Pester 5 unit tests for ProbeApi.ps1 request dispatcher and token auth.

.NOTES
    Author : Rdp Virtual Box App
    Module : tests/server/test-probe-api.ps1
    Engine : Pester 5
#>

BeforeAll {
    $scriptPath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\powershell\server\ProbeApi.ps1'
    $scriptPath = (Resolve-Path -LiteralPath $scriptPath).Path
    . $scriptPath
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\test-helpers.ps1')
}

Describe 'ProbeApi' {

    Context 'Test-ProbeApiToken' {

        It 'allows any token when no configured token is set' {
            $env:RDPVB_PROBE_TOKEN = ''
            Test-ProbeApiToken -ProvidedToken '' -ConfiguredToken '' | Should -Be $true
            Test-ProbeApiToken -ProvidedToken 'anything' -ConfiguredToken '' | Should -Be $true
        }

        It 'rejects a missing bearer when a token is configured' {
            Test-ProbeApiToken -ProvidedToken '' -ConfiguredToken 'secret-token' | Should -Be $false
        }

        It 'accepts a matching token case-insensitively' {
            Test-ProbeApiToken -ProvidedToken 'SeCrEt' -ConfiguredToken 'secret' | Should -Be $true
        }

        It 'rejects a mismatched token' {
            Test-ProbeApiToken -ProvidedToken 'nope' -ConfiguredToken 'secret' | Should -Be $false
        }
    }

    Context 'Test-ProbeApiAnonymousPath' {

        It 'treats health and root as anonymous' {
            Test-ProbeApiAnonymousPath -Path '/' | Should -Be $true
            Test-ProbeApiAnonymousPath -Path '/health' | Should -Be $true
            Test-ProbeApiAnonymousPath -Path '/api/health' | Should -Be $true
            Test-ProbeApiAnonymousPath -Path '/probe/api/health' | Should -Be $true
        }

        It 'treats download and rdp files as anonymous' {
            Test-ProbeApiAnonymousPath -Path '/download' | Should -Be $true
            Test-ProbeApiAnonymousPath -Path '/rdp' | Should -Be $true
            Test-ProbeApiAnonymousPath -Path '/rdp/public.rdp' | Should -Be $true
            Test-ProbeApiAnonymousPath -Path '/rdp/Tiger3Ent-lan.rdp' | Should -Be $true
        }

        It 'requires auth for probe/manifest/apps' {
            Test-ProbeApiAnonymousPath -Path '/probe/api/probe' | Should -Be $false
            Test-ProbeApiAnonymousPath -Path '/api/manifest' | Should -Be $false
            Test-ProbeApiAnonymousPath -Path '/api/apps' | Should -Be $false
        }
    }

    Context 'Invoke-ProbeApiRequest' {

        BeforeEach {
            $env:RDPVB_PROBE_TOKEN = 'unit-test-token'
        }

        AfterEach {
            $env:RDPVB_PROBE_TOKEN = ''
        }

        It 'returns 405 for POST' {
            $req = [pscustomobject]@{
                Method  = 'POST'
                Path    = '/health'
                Headers = @{}
                Query   = @{}
            }
            $resp = Invoke-ProbeApiRequest -Request $req
            $resp.status | Should -Be 405
        }

        It 'returns health without a token' {
            $req = [pscustomobject]@{
                Method  = 'GET'
                Path    = '/health'
                Headers = @{}
                Query   = @{}
            }
            $resp = Invoke-ProbeApiRequest -Request $req
            $resp.status | Should -Be 200
            $resp.body   | Should -Match '"status":\s*"ok"'
        }

        It 'returns 401 for probe without a token' {
            $req = [pscustomobject]@{
                Method  = 'GET'
                Path    = '/probe/api/probe'
                Headers = @{}
                Query   = @{}
            }
            $resp = Invoke-ProbeApiRequest -Request $req
            $resp.status | Should -Be 401
            $resp.body   | Should -Match 'unauthorized'
        }

        It 'returns 404 for an unknown path' {
            $req = [pscustomobject]@{
                Method  = 'GET'
                Path    = '/no-such-route'
                Headers = @{ Authorization = 'Bearer unit-test-token' }
                Query   = @{}
            }
            $resp = Invoke-ProbeApiRequest -Request $req
            $resp.status | Should -Be 404
        }

        It 'returns catalog at /' {
            $req = [pscustomobject]@{
                Method  = 'GET'
                Path    = '/'
                Headers = @{}
                Query   = @{}
            }
            $resp = Invoke-ProbeApiRequest -Request $req
            $resp.status | Should -Be 200
            $resp.body   | Should -Match 'RdpVirtualBoxApp-ProbeApi'
            $resp.body   | Should -Match '/probe/api/probe'
            $resp.body   | Should -Match '/download'
        }

        It 'serves the download page without a token' {
            $req = [pscustomobject]@{
                Method  = 'GET'
                Path    = '/download'
                Headers = @{}
                Query   = @{}
            }
            $resp = Invoke-ProbeApiRequest -Request $req
            $resp.status | Should -Be 200
            $resp.body   | Should -Match 'RemoteApp'
            $resp.headers['Content-Type'] | Should -Match 'text/html'
        }

        It 'serves a public rdp file without a token' {
            $req = [pscustomobject]@{
                Method  = 'GET'
                Path    = '/rdp/public.rdp'
                Headers = @{}
                Query   = @{}
            }
            $resp = Invoke-ProbeApiRequest -Request $req
            $resp.status | Should -Be 200
            $resp.body   | Should -Match 'remoteapplicationmode:i:1'
            $resp.body   | Should -Match 'remoteapplicationprogram:s:\|\|'
            $resp.body   | Should -Match 'server port:i:'
            $resp.body   | Should -Not -Match 'use multimon:i:1'
        }

        It 'android download uses RemoteApp exe shell not full desktop' {
            $req = [pscustomobject]@{
                Method  = 'GET'
                Path    = '/rdp/tiger3ent-gateway.rdp'
                Headers = @{ 'User-Agent' = 'EXFIN-RemoteAPP-Android/1.1.5' }
                Query   = @{ platform = 'android' }
            }
            $resp = Invoke-ProbeApiRequest -Request $req
            $resp.status | Should -Be 200
            $resp.body   | Should -Match 'remoteapplicationmode:i:1'
            $resp.body   | Should -Match 'Tiger3Enterprise.exe'
            $resp.body   | Should -Match 'use multimon:i:0'
        }

        It 'honors RDPVB_RDP_PORT in generated rdp' {
            $env:RDPVB_RDP_PORT = '3399'
            try {
                Get-ConfiguredRdpPort | Should -Be 3399
                $req = [pscustomobject]@{
                    Method  = 'GET'
                    Path    = '/rdp/lan.rdp'
                    Headers = @{}
                    Query   = @{}
                }
                $resp = Invoke-ProbeApiRequest -Request $req
                $resp.status | Should -Be 200
                $resp.body   | Should -Match 'server port:i:3399'
            } finally {
                $env:RDPVB_RDP_PORT = ''
            }
        }

        It 'returns 204 for CORS preflight' {
            $req = [pscustomobject]@{
                Method  = 'OPTIONS'
                Path    = '/probe/api/probe'
                Headers = @{}
                Query   = @{}
            }
            $resp = Invoke-ProbeApiRequest -Request $req
            $resp.status | Should -Be 204
        }
    }

    Context 'Get-LocalServerProbeResult' {

        It 'returns the Swift-compatible probe shape' {
            $probe = Get-LocalServerProbeResult -ServerName $env:COMPUTERNAME
            $probe.server | Should -Not -BeNullOrEmpty
            $probe.components | Should -Not -BeNullOrEmpty
            $probe.components.Keys | Should -Contain 'RDS_Role'
            $probe.components.Keys | Should -Contain 'RDP_Port'
            $probe.webEndpoint['rdWebAvailable'] | Should -BeOfType [bool]
            $probe.generatedAt | Should -Not -BeNullOrEmpty
            $null -ne $probe.existingRemoteApps | Should -Be $true
        }
    }

    Context 'ConvertTo-ProbeJson' {

        It 'serializes nested ordered hashtables' {
            $obj = [ordered]@{ a = [ordered]@{ b = 1 }; list = @('x') }
            $json = ConvertTo-ProbeJson -InputObject $obj
            $json | Should -Match '"a"'
            $json | Should -Match '"b"'
        }
    }
}
