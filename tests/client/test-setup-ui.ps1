<#
.SYNOPSIS
    Pester 5 unit tests for SetupUI.ps1 (client wizard).

.DESCRIPTION
    The main script imports WinForms at dot-source time. We extract pure
    helper functions (validation, palette, language table, wizard state)
    via the AST so the tests can run on any platform without a desktop.

.NOTES
    Author : Rdp Virtual Box App - Test Coverage Agent
    Module  : tests/client/test-setup-ui.ps1
    Engine  : Pester 5
#>

BeforeAll {
    $scriptPath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\powershell\client\SetupUI.ps1'
    $scriptPath = (Resolve-Path -LiteralPath $scriptPath).Path

    . (Join-Path -Path $PSScriptRoot -ChildPath '..\test-helpers.ps1')

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
    $funcNames = @(
        'New-SetupUiStrings',
        'Write-SetupLog',
        'Test-IpAddress',
        'Test-Port',
        'Test-UsernameFormat',
        'Get-SetupPalette',
        'New-WizardState'
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
}

Describe 'SetupUI helpers' {

    Context 'New-SetupUiStrings' {

        It 'should return the Turkish default when no language is supplied' {
            $s = New-SetupUiStrings
            $s.FormTitle | Should -Be 'Rdp Virtual Box App - Kurulum'
            $s.ServerIpLabel | Should -Be 'Sunucu IP:'
        }

        It 'should return the English bundle when -Language en is supplied' {
            $s = New-SetupUiStrings -Language en
            $s.FormTitle | Should -Be 'Rdp Virtual Box App - Setup'
            $s.ServerIpLabel | Should -Be 'Server IP:'
        }

        It 'should fail validation when an unknown language is supplied' {
            { New-SetupUiStrings -Language fr -ErrorAction Stop } | Should -Throw
        }
    }

    Context 'Test-IpAddress' {

        It 'should accept a valid IPv4 address' {
            Test-IpAddress -Value '192.168.1.10' | Should -BeTrue
        }

        It 'should reject an empty string' {
            Test-IpAddress -Value '' | Should -BeFalse
        }

        It 'should reject an IP out of range' {
            Test-IpAddress -Value '256.10.10.10' | Should -BeFalse
        }

        It 'should accept a simple hostname' {
            Test-IpAddress -Value 'server01' | Should -BeTrue
        }

        It 'should accept a FQDN' {
            Test-IpAddress -Value 'server.example.com' | Should -BeTrue
        }

        It 'should reject a value with spaces' {
            Test-IpAddress -Value 'bad host' | Should -BeFalse
        }
    }

    Context 'Test-Port' {

        It 'should accept 3389' {
            Test-Port -Value 3389 | Should -BeTrue
        }

        It 'should accept 1' {
            Test-Port -Value 1 | Should -BeTrue
        }

        It 'should accept 65535' {
            Test-Port -Value 65535 | Should -BeTrue
        }

        It 'should reject 0' {
            Test-Port -Value 0 | Should -BeFalse
        }

        It 'should reject 65536' {
            Test-Port -Value 65536 | Should -BeFalse
        }

        It 'should reject negative numbers' {
            Test-Port -Value -1 | Should -BeFalse
        }
    }

    Context 'Test-UsernameFormat' {

        It 'should accept DOMAIN\user style' {
            Test-UsernameFormat -Value 'CONTOSO\alice' | Should -BeTrue
        }

        It 'should accept user@domain.tld style' {
            Test-UsernameFormat -Value 'alice@contoso.com' | Should -BeTrue
        }

        It 'should reject bare usernames' {
            Test-UsernameFormat -Value 'alice' | Should -BeFalse
        }

        It 'should reject empty strings' {
            Test-UsernameFormat -Value '' | Should -BeFalse
        }

        It 'should reject whitespace' {
            Test-UsernameFormat -Value '   ' | Should -BeFalse
        }

        It 'should reject backslashes inside either side' {
            Test-UsernameFormat -Value 'a\\b\\c' | Should -BeFalse
        }
    }

    Context 'Get-SetupPalette' {

        It 'should return a hashtable with the expected keys' {
            $p = Get-SetupPalette
            $p.ContainsKey('Accent')    | Should -BeTrue
            $p.ContainsKey('Success')   | Should -BeTrue
            $p.ContainsKey('Warning')   | Should -BeTrue
            $p.ContainsKey('Danger')    | Should -BeTrue
            $p.ContainsKey('FontBody')  | Should -BeTrue
            $p.ContainsKey('FontTitle') | Should -BeTrue
        }
    }

    Context 'New-WizardState' {

        It 'should build a fresh state container withsensible defaults' {
            $state = New-WizardState
            $state.CurrentStep | Should -Be 1
            $state.AccessType  | Should -Be 'Native'
            $state.CredentialMode | Should -Be 'Ask'
            $state.Server.Port | Should -Be 3389
            $state.SelectedApps.Count | Should -Be 0
            $state.OutputDir | Should -Match 'RdpVirtualBoxApp'
        }
    }

    Context 'Write-SetupLog' {

        It 'should append a line to the configured log file' {
            $temp = New-RdsTestLogPath -BaseName 'setup-ui-log'
            Mock -CommandName 'Join-Path' -MockWith {
                param($Path, $ChildPath)
                if ($Path -like '*RdpVirtualBoxApp*' -and $ChildPath -eq 'Logs') { return $temp }
                if ($Path -eq $temp -and $ChildPath -eq 'setup.log') { return $temp }
                Microsoft.PowerShell.Management\Join-Path -Path $Path -ChildPath $ChildPath
            }
            Mock -CommandName 'Test-Path' -MockWith { param($LiteralPath) $true }
            Mock -CommandName 'New-Item' -MockWith { $null }
            Mock -CommandName 'Add-Content' -MockWith {
                param($LiteralPath, $Value, $Encoding, $ErrorAction)
                $script:lastLogLine = $Value
            }

            $script:lastLogLine = ''
            Write-SetupLog -Message 'sample-message' -Level Info
            $script:lastLogLine | Should -Match 'sample-message'
            $script:lastLogLine | Should -Match 'Info'
        }
    }
}
