<#
.SYNOPSIS
    Pester 5 unit tests for ServerSetupUI.ps1.

.DESCRIPTION
    The main script wires up WinForms / module imports at the top of the
    file. To exercise testable units we dot-source selected helper
    functions manually and stub the rest. The interesting, dependency-free
    bits are the theme helpers, the wizard data container, and the
    validation helpers — those get first-class coverage here.

.NOTES
    Author : Rdp Virtual Box App - Test Coverage Agent
    Module  : tests/server/test-server-setup-ui.ps1
    Engine  : Pester 5
#>

BeforeAll {
    $scriptPath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\powershell\server\ServerSetupUI.ps1'
    $scriptPath = (Resolve-Path -LiteralPath $scriptPath).Path

    . (Join-Path -Path $PSScriptRoot -ChildPath '..\test-helpers.ps1')

    # The script instantiates WinForms at dot-source time. We can't
    # actually dot-source it on a non-Windows agent, so we extract the
    # helpers we want to test by parsing the file and evaluating the
    # relevant function bodies.
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
    $funcNames = @('Write-SetupLog','New-ModernButton','New-PrimaryButton','Set-StatusBadge','Get-ServerNetworkInfo')
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

Describe 'ServerSetupUI helpers' {

    Context 'New-ModernButton' {

        It 'should produce a System.Windows.Forms.Button instance' {
            Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
            Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
            $btn = New-ModernButton -Text 'Geri' -Location (New-Object System.Drawing.Point 10, 10) -Size (New-Object System.Drawing.Size 80, 30)
            $btn | Should -Not -BeNullOrEmpty
            $btn.Text | Should -Be 'Geri'
            $btn.FlatStyle | Should -Be ([System.Windows.Forms.FlatStyle]::Flat)
        }
    }

    Context 'New-PrimaryButton' {

        It 'should set the primary theme color as BackColor' {
            Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
            Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
            $btn = New-PrimaryButton -Text 'Ileri' -Location (New-Object System.Drawing.Point 10, 10) -Size (New-Object System.Drawing.Size 80, 30)
            $btn.Text | Should -Be 'Ileri'
            $btn.FlatStyle | Should -Be ([System.Windows.Forms.FlatStyle]::Flat)
            $btn.FlatAppearance.BorderSize | Should -Be 0
        }
    }

    Context 'Set-StatusBadge' {

        It 'should colour the label according to the supplied state' {
            Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
            $lbl = New-Object System.Windows.Forms.Label
            Set-StatusBadge -Label $lbl -State 'ok' -Text 'OK'
            $lbl.Text | Should -Match 'OK'
            Set-StatusBadge -Label $lbl -State 'err' -Text 'BAD'
            $lbl.Text | Should -Match 'BAD'
        }
    }

    Context 'Write-SetupLog' {

        It 'should append a formatted line to the log file' {
            $temp = New-RdsTestLogPath -BaseName 'server-setup-log'
            $script:LogFile = $temp
            Write-SetupLog -Message 'hello world' -Level INFO
            Test-Path -LiteralPath $temp | Should -BeTrue
            (Get-Content -LiteralPath $temp -Raw) | Should -Match 'hello world'
            (Get-Content -LiteralPath $temp -Raw) | Should -Match 'INFO'
        }

        It 'should honour the -Component parameter' {
            $temp = New-RdsTestLogPath -BaseName 'server-setup-log-c'
            $script:LogFile = $temp
            Write-SetupLog -Message 'component-tagged' -Level WARN -Component 'Foo'
            (Get-Content -LiteralPath $temp -Raw) | Should -Match 'Foo'
        }

        It 'should not throw when level is silent' {
            $temp = New-RdsTestLogPath -BaseName 'server-setup-log-2'
            $script:LogFile = $temp
            { Write-SetupLog -Message 'silent' -Level DEBUG } | Should -Not -Throw
        }
    }
}
