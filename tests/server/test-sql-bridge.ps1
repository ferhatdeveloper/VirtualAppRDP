<#
.SYNOPSIS
    Pester 5 unit tests for SqlBridge.ps1 (server SQL localhost tunnel).

.NOTES
    Author : Rdp Virtual Box App
    Module : tests/server/test-sql-bridge.ps1
    Engine : Pester 5
#>

BeforeAll {
    $script:TestConfigDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("rdpvb-sqlbridge-{0}" -f [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:TestConfigDir -Force | Out-Null
    $script:OldProgramData = $env:ProgramData
    $env:ProgramData = $script:TestConfigDir

    $scriptPath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\powershell\server\SqlBridge.ps1'
    $scriptPath = (Resolve-Path -LiteralPath $scriptPath).Path
    . $scriptPath
}

AfterAll {
    if ($null -ne $script:OldProgramData) { $env:ProgramData = $script:OldProgramData }
    if ($script:TestConfigDir -and (Test-Path -LiteralPath $script:TestConfigDir)) {
        Remove-Item -LiteralPath $script:TestConfigDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'SqlBridge' {

    Context 'Get-SqlBridgeDefaultConfig' {

        It 'returns disabled bridge on port 1433' {
            $cfg = Get-SqlBridgeDefaultConfig
            $cfg.enabled | Should -BeFalse
            $cfg.sqlPort | Should -Be 1433
            $cfg.sqlHost | Should -Be '127.0.0.1'
            $cfg.requireBearer | Should -BeTrue
            $cfg.allowDirectLan | Should -BeFalse
        }
    }

    Context 'Test-LocalTcpPortListening' {

        It 'returns false for a closed high port' {
            Test-LocalTcpPortListening -HostName '127.0.0.1' -Port 59999 -TimeoutMs 200 | Should -BeFalse
        }
    }

    Context 'Find-SqlServerTcpPort' {

        It 'always includes 1433 as a candidate' {
            $d = Find-SqlServerTcpPort
            $d.candidates | Should -Contain 1433
            $d.port | Should -BeOfType [int]
            $d.Keys | Should -Contain 'reachable'
            $d.Keys | Should -Contain 'listening'
        }
    }

    Context 'Get-SqlBridgeStatus' {

        It 'returns tunnel metadata even when disabled' {
            $s = Get-SqlBridgeStatus
            $s.tunnelPath | Should -Be '/sql-bridge'
            $s.tunnelMethod | Should -Be 'CONNECT'
            $s.clientHint | Should -Match '127\.0\.0\.1,'
            $s.connectionString | Should -Match 'Server=127\.0\.0\.1,'
        }
    }

    Context 'Test-SqlBridgeConnectAllowed' {

        It 'rejects when bridge is disabled' {
            $cfg = Get-SqlBridgeDefaultConfig
            $cfg.enabled = $false
            # Write to real path only if we can; otherwise call with mocked status via disabled default config
            $path = Get-SqlBridgeConfigPath
            $dir = Split-Path -Parent $path
            $hadDir = Test-Path -LiteralPath $dir
            $backup = $null
            if (Test-Path -LiteralPath $path) {
                $backup = Get-Content -LiteralPath $path -Raw -Encoding UTF8
            }
            try {
                if (-not $hadDir) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
                Save-SqlBridgeConfig -Config $cfg
                $gate = Test-SqlBridgeConnectAllowed -ProvidedToken 'x'
                $gate.ok | Should -BeFalse
                $gate.status | Should -Be 403
                $gate.error | Should -Be 'sql_bridge_disabled'
            } finally {
                if ($null -ne $backup) {
                    Set-Content -LiteralPath $path -Value $backup -Encoding UTF8
                } elseif (Test-Path -LiteralPath $path) {
                    Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
}

Describe 'ProbeApi sql-bridge route' {

    BeforeAll {
        $probePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\powershell\server\ProbeApi.ps1'
        $probePath = (Resolve-Path -LiteralPath $probePath).Path
        . $probePath
    }

    It 'lists sql-bridge in catalog' {
        $cat = Get-ProbeCatalog
        $paths = @($cat.endpoints | ForEach-Object { $_.path })
        $paths | Should -Contain '/api/sql-bridge'
        $paths | Should -Contain '/sql-bridge'
    }

    It 'serves /api/sql-bridge with bearer when token configured' {
        $env:RDPVB_PROBE_TOKEN = 'sql-bridge-unit-token'
        try {
            $req = [pscustomobject]@{
                Method  = 'GET'
                Path    = '/api/sql-bridge'
                Headers = @{ Authorization = 'Bearer sql-bridge-unit-token' }
                Query   = @{}
            }
            $resp = Invoke-ProbeApiRequest -Request $req
            $resp.status | Should -Be 200
            $resp.body   | Should -Match 'tunnelPath'
            $resp.body   | Should -Match 'sql-bridge'
        } finally {
            $env:RDPVB_PROBE_TOKEN = ''
        }
    }

    It 'rejects /api/sql-bridge without token when configured' {
        $env:RDPVB_PROBE_TOKEN = 'sql-bridge-unit-token'
        try {
            $req = [pscustomobject]@{
                Method  = 'GET'
                Path    = '/api/sql-bridge'
                Headers = @{}
                Query   = @{}
            }
            $resp = Invoke-ProbeApiRequest -Request $req
            $resp.status | Should -Be 401
        } finally {
            $env:RDPVB_PROBE_TOKEN = ''
        }
    }
}
