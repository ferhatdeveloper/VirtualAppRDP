<#
.SYNOPSIS
    Pester 5 unit tests for SqlBridgeClient.ps1 helpers (connection hint / config).

.NOTES
    Author : Rdp Virtual Box App
    Module : tests/client/test-sql-bridge-client.ps1
    Engine : Pester 5
#>

BeforeAll {
    $scriptPath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\powershell\client\SqlBridgeClient.ps1'
    $scriptPath = (Resolve-Path -LiteralPath $scriptPath).Path

    # Extract helper functions without running Listen/Install CLI.
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
    $funcNames = @(
        'Write-SqlBridgeClientLog',
        'Get-SqlBridgeClientConfig',
        'Save-SqlBridgeClientConfig',
        'Write-SqlBridgeConnectionHint',
        'Get-SqlBridgeClientStatus'
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

    # Script-scoped paths used by helpers
    $script:ConfigDir  = Join-Path ([System.IO.Path]::GetTempPath()) ("rdpvb-sqlc-{0}" -f [guid]::NewGuid().ToString('N'))
    $script:ConfigFile = Join-Path $script:ConfigDir 'sql-bridge-client.json'
    $script:LogFile    = Join-Path $script:ConfigDir 'sql-bridge-client.log'
    $script:PidFile    = Join-Path $script:ConfigDir 'sql-bridge-client.pid'
    $script:StopFile   = Join-Path $script:ConfigDir 'sql-bridge-client.stop'
    $script:ConnFile   = Join-Path $script:ConfigDir 'sql-bridge-connection.txt'
    $script:TaskName   = 'RdpVirtualBoxApp-SqlBridge-Test'
    New-Item -ItemType Directory -Path $script:ConfigDir -Force | Out-Null
}

AfterAll {
    if ($script:ConfigDir -and (Test-Path -LiteralPath $script:ConfigDir)) {
        Remove-Item -LiteralPath $script:ConfigDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'SqlBridgeClient helpers' {

    Context 'Write-SqlBridgeConnectionHint' {

        It 'writes Server=127.0.0.1,port into the hint file' {
            $path = Write-SqlBridgeConnectionHint -Port 1433 -ServerHost '10.0.0.5'
            $path | Should -Be $script:ConnFile
            $text = Get-Content -LiteralPath $path -Raw -Encoding UTF8
            $text | Should -Match 'Server=127\.0\.0\.1,1433'
            $text | Should -Match '10\.0\.0\.5'
            $text | Should -Match 'CONNECT /sql-bridge'
        }
    }

    Context 'Save / Get client config' {

        It 'round-trips server and ports' {
            $cfg = [ordered]@{
                server    = '192.168.1.50'
                probePort = 8444
                token     = 'secret'
                localPort = 1433
                localBind = '127.0.0.1'
                enabled   = $true
            }
            Save-SqlBridgeClientConfig -Config $cfg
            $loaded = Get-SqlBridgeClientConfig
            $loaded.server | Should -Be '192.168.1.50'
            [int]$loaded.probePort | Should -Be 8444
            [bool]$loaded.enabled | Should -BeTrue
        }
    }

    Context 'Get-SqlBridgeClientStatus' {

        It 'reports missing task when not installed' {
            $st = Get-SqlBridgeClientStatus
            $st.Keys | Should -Contain 'listening'
            $st.Keys | Should -Contain 'localPort'
            $st.configPath | Should -Be $script:ConfigFile
        }
    }
}

Describe 'SetupUI SQL Bridge strings' {

    BeforeAll {
        $uiPath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\powershell\client\SetupUI.ps1'
        $uiPath = (Resolve-Path -LiteralPath $uiPath).Path
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($uiPath, [ref]$tokens, [ref]$errors)
        $funcAst = $ast.FindAll({
            param($n)
            $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'New-SetupUiStrings'
        }, $true) | Select-Object -First 1
        Invoke-Expression $funcAst.Extent.Text
    }

    It 'includes SQL Bridge labels in Turkish and English' {
        $tr = New-SetupUiStrings
        $en = New-SetupUiStrings -Language en
        $tr.SqlBridgeLabel | Should -Match 'SQL Bridge'
        $en.SqlBridgeLabel | Should -Match 'SQL Bridge'
        $tr.SqlBridgeHint  | Should -Match '127\.0\.0\.1'
    }
}
