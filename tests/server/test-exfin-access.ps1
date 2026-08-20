<#
.SYNOPSIS
    Pester 5 tests for EXFIN RemoteAPP TOTP, client approval, icon/file APIs.

.NOTES
    Author : EXFIN RemoteAPP
    Module : tests/server/test-exfin-access.ps1
    Engine : Pester 5
#>

BeforeAll {
    $scriptPath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\powershell\server\ProbeApi.ps1'
    $scriptPath = (Resolve-Path -LiteralPath $scriptPath).Path
    . $scriptPath
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\test-helpers.ps1')
}

Describe 'ExfinAccess' {

    BeforeEach {
        $script:exfinCfg = Join-Path -Path (Get-RdsTestScratchDir -Prefix 'ExfinAccessTests') -ChildPath ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:exfinCfg -Force | Out-Null
        $env:RDPVB_EXFIN_CONFIG = $script:exfinCfg
        $env:RDPVB_PROBE_TOKEN = 'unit-test-token'
    }

    AfterEach {
        $env:RDPVB_EXFIN_CONFIG = ''
        $env:RDPVB_PROBE_TOKEN = ''
        if ($script:exfinCfg -and (Test-Path -LiteralPath $script:exfinCfg)) {
            Remove-Item -LiteralPath $script:exfinCfg -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'ExfinTotp (Google Authenticator)' {

        It 'generates a 32-char Base32 secret and verifies the current code on PS 5.1' {
            $secret = [ExfinTotp]::NewSecret()
            $secret.Length | Should -Be 32
            $secret | Should -Match '^[A-Z2-7]+$'
            $code = [ExfinTotp]::CodeAt($secret, [ExfinTotp]::UnixSeconds())
            $code | Should -Match '^\d{6}$'
            [ExfinTotp]::Verify($secret, $code, 1) | Should -Be $true
            [ExfinTotp]::Verify($secret, '000000', 1) | Should -Be $false
            [ExfinTotp]::Verify($secret, ('{0} {1}' -f $code.Substring(0, 3), $code.Substring(3)), 1) | Should -Be $true
        }

        It 'GET /api/totp returns enabled, enrolled, issuer EXFIN RemoteAPP, account' {
            $resp = Invoke-ExfinAccessRequest -Request ([pscustomobject]@{ Method = 'GET' }) -Method 'GET' -PathNorm '/api/totp' -Query @{}
            $resp.status | Should -Be 200
            $body = $resp.body | ConvertFrom-Json
            $body.enabled | Should -Be $false
            $body.enrolled | Should -Be $false
            $body.issuer | Should -Be 'EXFIN RemoteAPP'
            $body.account | Should -Be $env:COMPUTERNAME
        }

        It 'enroll returns otpauth://totp/EXFIN RemoteAPP:HOST with encoded issuer' {
            $resp = Invoke-ExfinAccessRequest -Request ([pscustomobject]@{ Method = 'POST'; Body = '{"action":"enroll"}' }) -Method 'POST' -PathNorm '/api/totp' -Query @{}
            $resp.status | Should -Be 200
            $body = $resp.body | ConvertFrom-Json
            $body.secret | Should -Not -BeNullOrEmpty
            $body.issuer | Should -Be 'EXFIN RemoteAPP'
            $body.account | Should -Be $env:COMPUTERNAME
            $body.otpauth | Should -Match ('^otpauth://totp/EXFIN RemoteAPP:{0}\?secret=' -f [regex]::Escape($env:COMPUTERNAME))
            $body.otpauth | Should -Match 'issuer=EXFIN%20RemoteAPP'
            $body.otpauth | Should -Match 'period=30'
            $body.otpauth | Should -Match 'digits=6'
        }

        It 'confirm enables TOTP; verify returns 200/401; disable clears' {
            $enroll = Invoke-ExfinAccessRequest -Request ([pscustomobject]@{ Method = 'POST'; Body = '{"action":"enroll"}' }) -Method 'POST' -PathNorm '/api/totp' -Query @{}
            $enroll.status | Should -Be 200
            $secret = ($enroll.body | ConvertFrom-Json).secret
            $code = [ExfinTotp]::CodeAt($secret, [ExfinTotp]::UnixSeconds())

            $bad = Invoke-ExfinAccessRequest -Request ([pscustomobject]@{ Method = 'POST'; Body = '{"action":"confirm","code":"000000"}' }) -Method 'POST' -PathNorm '/api/totp' -Query @{}
            $bad.status | Should -Be 401

            $confirmBody = ('{{"action":"confirm","code":"{0}"}}' -f $code)
            $ok = Invoke-ExfinAccessRequest -Request ([pscustomobject]@{ Method = 'POST'; Body = $confirmBody }) -Method 'POST' -PathNorm '/api/totp' -Query @{}
            $ok.status | Should -Be 200
            $state = $ok.body | ConvertFrom-Json
            $state.enabled | Should -Be $true
            $state.enrolled | Should -Be $true

            $vBad = Invoke-ExfinAccessRequest -Request ([pscustomobject]@{ Method = 'POST'; Body = '{"action":"verify","code":"111111"}' }) -Method 'POST' -PathNorm '/api/totp' -Query @{}
            $vBad.status | Should -Be 401

            $fresh = [ExfinTotp]::CodeAt($secret, [ExfinTotp]::UnixSeconds())
            $vOk = Invoke-ExfinAccessRequest -Request ([pscustomobject]@{ Method = 'POST'; Body = ('{{"action":"verify","code":"{0}"}}' -f $fresh) }) -Method 'POST' -PathNorm '/api/totp' -Query @{}
            $vOk.status | Should -Be 200

            $off = Invoke-ExfinAccessRequest -Request ([pscustomobject]@{ Method = 'POST'; Body = '{"action":"disable"}' }) -Method 'POST' -PathNorm '/api/totp' -Query @{}
            $off.status | Should -Be 200
            $cleared = $off.body | ConvertFrom-Json
            $cleared.enabled | Should -Be $false
            $cleared.enrolled | Should -Be $false
        }
    }

    Context 'Client login permission' {

        It 'anonymous POST register creates pending; GET requires LAN or Bearer' {
            $payload = '{"machineId":"mid-1","hostname":"PC1","username":"ali","apps":[{"id":"tiger","name":"Tiger","alias":"Tiger3Ent"}]}'
            $reg = Invoke-ProbeApiRequest -Request ([pscustomobject]@{
                    Method   = 'POST'
                    Path     = '/api/clients'
                    Headers  = @{}
                    Query    = @{}
                    Body     = $payload
                    RemoteIp = '8.8.8.8'
                })
            $reg.status | Should -Be 200
            $regBody = $reg.body | ConvertFrom-Json
            $clients = @($regBody.clients)
            $clients.Count | Should -Be 1
            $clients[0].status | Should -Be 'pending'
            $clients[0].machineId | Should -Be 'mid-1'

            $denied = Invoke-ProbeApiRequest -Request ([pscustomobject]@{
                    Method   = 'GET'
                    Path     = '/api/clients'
                    Headers  = @{}
                    Query    = @{}
                    RemoteIp = '8.8.8.8'
                })
            $denied.status | Should -Be 401

            $listed = Invoke-ProbeApiRequest -Request ([pscustomobject]@{
                    Method   = 'GET'
                    Path     = '/api/clients'
                    Headers  = @{ Authorization = 'Bearer unit-test-token' }
                    Query    = @{}
                    RemoteIp = '8.8.8.8'
                })
            $listed.status | Should -Be 200
        }

        It 'admin approve/deny and requireApproval need LAN or Bearer' {
            $payload = '{"machineId":"mid-2","hostname":"PC2","username":"veli"}'
            $null = Invoke-ProbeApiRequest -Request ([pscustomobject]@{
                    Method   = 'POST'
                    Path     = '/api/clients'
                    Headers  = @{}
                    Query    = @{}
                    Body     = $payload
                    RemoteIp = '8.8.8.8'
                })
            $id = 'mid-2|veli'
            $wanDeny = Invoke-ProbeApiRequest -Request ([pscustomobject]@{
                    Method   = 'POST'
                    Path     = '/api/clients'
                    Headers  = @{}
                    Query    = @{}
                    Body     = ('{{"id":"{0}","action":"approve"}}' -f $id)
                    RemoteIp = '8.8.8.8'
                })
            $wanDeny.status | Should -Be 401

            $approved = Invoke-ProbeApiRequest -Request ([pscustomobject]@{
                    Method   = 'POST'
                    Path     = '/api/clients'
                    Headers  = @{ Authorization = 'Bearer unit-test-token' }
                    Query    = @{}
                    Body     = ('{{"id":"{0}","action":"approve"}}' -f $id)
                    RemoteIp = '8.8.8.8'
                })
            $approved.status | Should -Be 200
            @( ($approved.body | ConvertFrom-Json).clients )[0].status | Should -Be 'approved'

            $flag = Invoke-ProbeApiRequest -Request ([pscustomobject]@{
                    Method   = 'POST'
                    Path     = '/api/clients'
                    Headers  = @{ Authorization = 'Bearer unit-test-token' }
                    Query    = @{}
                    Body     = '{"requireApproval":true}'
                    RemoteIp = '8.8.8.8'
                })
            $flag.status | Should -Be 200
            ($flag.body | ConvertFrom-Json).requireApproval | Should -Be $true
        }

        It 'blocks public /rdp/*.rdp with 403 until client is approved; LAN always allowed' {
            $null = Invoke-ExfinAccessRequest -Request ([pscustomobject]@{
                    Method = 'POST'
                    Body   = '{"machineId":"box-9","hostname":"BOX","username":"user"}'
                }) -Method 'POST' -PathNorm '/api/clients' -Query @{}
            $null = Invoke-ExfinAccessRequest -Request ([pscustomobject]@{
                    Method = 'POST'
                    Body   = '{"requireApproval":true}'
                }) -Method 'POST' -PathNorm '/api/clients' -Query @{}

            Test-ExfinClientMayDownload -ClientId '' | Should -Be $false
            Test-ExfinClientMayDownload -ClientId 'box-9' | Should -Be $false

            $blocked = Invoke-ProbeApiRequest -Request ([pscustomobject]@{
                    Method   = 'GET'
                    Path     = '/rdp/public.rdp'
                    Headers  = @{}
                    Query    = @{}
                    RemoteIp = '1.2.3.4'
                })
            $blocked.status | Should -Be 403

            $lan = Invoke-ProbeApiRequest -Request ([pscustomobject]@{
                    Method   = 'GET'
                    Path     = '/rdp/public.rdp'
                    Headers  = @{}
                    Query    = @{}
                    RemoteIp = '192.168.10.20'
                })
            $lan.status | Should -Be 200

            $id = 'box-9|user'
            $null = Invoke-ExfinAccessRequest -Request ([pscustomobject]@{
                    Method = 'POST'
                    Body   = ('{{"id":"{0}","action":"approve"}}' -f $id)
                }) -Method 'POST' -PathNorm '/api/clients' -Query @{}

            Test-ExfinClientMayDownload -ClientId 'box-9' | Should -Be $true
            Test-ExfinClientMayDownload -ClientId $id | Should -Be $true

            $viaMachine = Invoke-ProbeApiRequest -Request ([pscustomobject]@{
                    Method   = 'GET'
                    Path     = '/rdp/public.rdp?client=box-9'
                    Headers  = @{}
                    Query    = @{}
                    RemoteIp = '1.2.3.4'
                })
            $viaMachine.status | Should -Be 200
        }
    }

    Context 'Icon, file preview, browse' {

        It 'GET /api/icon returns alias, path, png' {
            $notepad = Join-Path $env:SystemRoot 'System32\notepad.exe'
            $resp = Invoke-ExfinAccessRequest -Request ([pscustomobject]@{ Method = 'GET' }) -Method 'GET' -PathNorm '/api/icon' -Query @{
                alias = 'Notepad'
                path  = $notepad
            }
            $resp.status | Should -Be 200
            $body = $resp.body | ConvertFrom-Json
            $body.alias | Should -Be 'Notepad'
            $body.path | Should -Be $notepad
            $body.PSObject.Properties['png'] | Should -Not -BeNullOrEmpty
        }

        It 'GET /api/file returns text preview' {
            $file = Join-Path $script:exfinCfg 'hello.txt'
            Set-Content -LiteralPath $file -Value 'exfin-preview' -Encoding ASCII
            $resp = Invoke-ExfinAccessRequest -Request ([pscustomobject]@{ Method = 'GET' }) -Method 'GET' -PathNorm '/api/file' -Query @{ path = $file }
            $resp.status | Should -Be 200
            $body = $resp.body | ConvertFrom-Json
            $body.content | Should -Match 'exfin-preview'
            $body.extension | Should -Be '.txt'
        }

        It 'GET /api/browse marks text extensions as previewable' {
            $txt = Join-Path $script:exfinCfg 'note.md'
            Set-Content -LiteralPath $txt -Value '# hi' -Encoding ASCII
            $resp = Invoke-ProbeApiRequest -Request ([pscustomobject]@{
                    Method   = 'GET'
                    Path     = ('/api/browse?path={0}' -f [Uri]::EscapeDataString($script:exfinCfg))
                    Headers  = @{ Authorization = 'Bearer unit-test-token' }
                    Query    = @{}
                    RemoteIp = '8.8.8.8'
                })
            $resp.status | Should -Be 200
            $body = $resp.body | ConvertFrom-Json
            $entry = @($body.entries) | Where-Object { $_.name -eq 'note.md' }
            $entry | Should -Not -BeNullOrEmpty
            $entry.previewable | Should -Be $true
        }
    }
}
