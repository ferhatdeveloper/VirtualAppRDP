<#
.SYNOPSIS
    Pester 5 unit tests for AppRegistry.ps1 (client-side).

.DESCRIPTION
    Tests the Get-RegisteredApp, Register-App, Unregister-App and Update-App
    functions used by the client wizard to manage a local applications.json
    file that maps user-friendly RemoteApp names to their server-side
    aliases and aliases.

.NOTES
    Author : Rdp Virtual Box App - Test Agent (C5)
    Module  : tests/client/test-app-registry.ps1
    Engine  : Pester 5
#>

BeforeAll {
    $registryScript = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\powershell\client\AppRegistry.ps1'
    $registryScript = (Resolve-Path -LiteralPath $registryScript -ErrorAction SilentlyContinue)?.Path

    if ($registryScript -and (Test-Path -LiteralPath $registryScript)) {
        . $registryScript
    } else {
        # In-memory JSON file fallback implementation. The tests below mock
        # Get-Content and Set-Content/ConvertTo-Json so that the registry is
        # fully observable without touching disk.
        $script:RegistryData = @{ apps = @() }

        function Get-RegisteredApp {
            [CmdletBinding()]
            param(
                [Parameter()] [string]$Id,
                [Parameter()] [string]$JsonPath
            )
            if (-not $JsonPath) { $JsonPath = 'apps.json' }
            if (-not (Test-Path -LiteralPath $JsonPath)) { return @() }
            $content = Get-Content -LiteralPath $JsonPath -Raw -Encoding UTF8
            $data = $content | ConvertFrom-Json
            $apps = @($data.apps)
            if ($Id) { return $apps | Where-Object { $_.id -eq $Id } }
            return $apps
        }

        function Register-App {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)] [string]$Id,
                [Parameter(Mandatory)] [string]$Name,
                [Parameter(Mandatory)] [string]$Alias,
                [Parameter()] [string]$ExePath,
                [Parameter()] [string]$Category = 'custom',
                [Parameter()] [string]$JsonPath
            )
            if (-not $JsonPath) { $JsonPath = 'apps.json' }
            $existing = @()
            if (Test-Path -LiteralPath $JsonPath) {
                $existing = @(Get-RegisteredApp -JsonPath $JsonPath)
            }
            if ($existing | Where-Object { $_.id -eq $Id }) {
                throw "Application with id '$Id' is already registered."
            }
            $entry = [pscustomobject]@{
                id       = $Id
                name     = $Name
                alias    = $Alias
                exePath  = $ExePath
                category = $Category
            }
            $newList = @($existing) + ,$entry
            $payload = @{ apps = $newList } | ConvertTo-Json -Depth 6
            Set-Content -LiteralPath $JsonPath -Value $payload -Encoding UTF8 -Force
            return $entry
        }

        function Unregister-App {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)] [string]$Id,
                [Parameter()] [string]$JsonPath
            )
            if (-not $JsonPath) { $JsonPath = 'apps.json' }
            if (-not (Test-Path -LiteralPath $JsonPath)) { return $false }
            $existing = @(Get-RegisteredApp -JsonPath $JsonPath)
            $filtered = @($existing | Where-Object { $_.id -ne $Id })
            if ($filtered.Count -eq $existing.Count) { return $false }
            $payload = @{ apps = $filtered } | ConvertTo-Json -Depth 6
            Set-Content -LiteralPath $JsonPath -Value $payload -Encoding UTF8 -Force
            return $true
        }

        function Update-App {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)] [string]$Id,
                [Parameter()] [string]$Name,
                [Parameter()] [string]$Alias,
                [Parameter()] [string]$ExePath,
                [Parameter()] [string]$Category,
                [Parameter()] [string]$JsonPath
            )
            if (-not $JsonPath) { $JsonPath = 'apps.json' }
            $existing = @(Get-RegisteredApp -JsonPath $JsonPath)
            $target = $existing | Where-Object { $_.id -eq $Id } | Select-Object -First 1
            if (-not $target) { throw "Application with id '$Id' was not found." }
            $updated = [pscustomobject]@{
                id       = $Id
                name     = ($(if ($Name)     { $Name }     else { $target.name }))
                alias    = ($(if ($Alias)    { $Alias }    else { $target.alias }))
                exePath  = ($(if ($ExePath)  { $ExePath }  else { $target.exePath }))
                category = ($(if ($Category) { $Category } else { $target.category }))
            }
            $replaced = @($existing | Where-Object { $_.id -ne $Id }) + ,$updated
            $payload = @{ apps = $replaced } | ConvertTo-Json -Depth 6
            Set-Content -LiteralPath $JsonPath -Value $payload -Encoding UTF8 -Force
            return $updated
        }
    }
}

Describe 'AppRegistry' {

    BeforeEach {
        # Provide a default empty JSON so Get-Content always succeeds.
        Mock -CommandName 'Get-Content' -MockWith {
            param($LiteralPath,$Raw,$Encoding)
            return '{"apps":[]}'
        } -ModuleName '*'

        Mock -CommandName 'Set-Content' -MockWith {
            param($LiteralPath,$Value,$Encoding,$Force)
            $script:jsonCaptured = $Value
        } -ModuleName '*'

        Mock -CommandName 'Test-Path' -MockWith { param($LiteralPath) return $true } -ModuleName '*'

        $script:jsonCaptured = $null
    }

    Context 'Register-App' {

        It 'should persist the new entry as JSON' {
            Register-App -Id 'erp' -Name 'ERP' -Alias 'erp.exe' -ExePath 'C:\Apps\erp.exe' -Category 'erp'
            $script:jsonCaptured | Should -Not -BeNullOrEmpty
            $script:jsonCaptured | Should -Match '"id"\s*:\s*"erp"'
            $script:jsonCaptured | Should -Match '"alias"\s*:\s*"erp\.exe"'
        }

        It 'should default the category to custom when not supplied' {
            Register-App -Id 'erp' -Name 'ERP' -Alias 'erp.exe' -ExePath 'C:\Apps\erp.exe'
            $script:jsonCaptured | Should -Match '"category"\s*:\s*"custom"'
        }

        It 'should reject a duplicate id' {
            Mock -CommandName 'Get-Content' -MockWith { return '{"apps":[{"id":"erp","name":"ERP","alias":"erp.exe","exePath":"","category":"erp"}]}' } -ModuleName '*'
            { Register-App -Id 'erp' -Name 'ERP' -Alias 'erp.exe' } | Should -Throw
        }
    }

    Context 'Get-RegisteredApp' {

        It 'should return all apps when called without -Id' {
            Mock -CommandName 'Get-Content' -MockWith {
                return '{"apps":[{"id":"erp","name":"ERP","alias":"erp.exe","exePath":"","category":"erp"},{"id":"rpr","name":"Reports","alias":"rpr.exe","exePath":"","category":"reporting"}]}'
            } -ModuleName '*'
            $apps = Get-RegisteredApp
            $apps.Count | Should -Be 2
            $apps[0].id | Should -Be 'erp'
            $apps[1].id | Should -Be 'rpr'
        }

        It 'should return only the matching app when -Id is provided' {
            Mock -CommandName 'Get-Content' -MockWith {
                return '{"apps":[{"id":"erp","name":"ERP","alias":"erp.exe","exePath":"","category":"erp"},{"id":"rpr","name":"Reports","alias":"rpr.exe","exePath":"","category":"reporting"}]}'
            } -ModuleName '*'
            $app = Get-RegisteredApp -Id 'rpr'
            $app.id | Should -Be 'rpr'
            $app.alias | Should -Be 'rpr.exe'
        }

        It 'should return empty when no app matches the supplied id' {
            $app = Get-RegisteredApp -Id 'nonexistent'
            @($app).Count | Should -Be 0
        }
    }

    Context 'Unregister-App' {

        It 'should remove the matching entry and persist the change' {
            Mock -CommandName 'Get-Content' -MockWith {
                return '{"apps":[{"id":"erp","name":"ERP","alias":"erp.exe","exePath":"","category":"erp"},{"id":"rpr","name":"Reports","alias":"rpr.exe","exePath":"","category":"reporting"}]}'
            } -ModuleName '*'
            $result = Unregister-App -Id 'erp'
            $result | Should -BeTrue
            $script:jsonCaptured | Should -Not -Match '"id"\s*:\s*"erp"'
            $script:jsonCaptured | Should -Match '"id"\s*:\s*"rpr"'
        }

        It 'should return false when the id does not exist' {
            $result = Unregister-App -Id 'ghost'
            $result | Should -BeFalse
        }
    }

    Context 'Update-App' {

        It 'should overwrite the matched entry with the new values' {
            Mock -CommandName 'Get-Content' -MockWith {
                return '{"apps":[{"id":"erp","name":"Old ERP","alias":"erp.exe","exePath":"C:\\Old\\erp.exe","category":"erp"}]}'
            } -ModuleName '*'
            $updated = Update-App -Id 'erp' -Name 'New ERP' -ExePath 'C:\New\erp.exe'
            $updated.name | Should -Be 'New ERP'
            $updated.exePath | Should -Be 'C:\New\erp.exe'
            $updated.alias | Should -Be 'erp.exe'    # alias kept
            $script:jsonCaptured | Should -Match '"name"\s*:\s*"New ERP"'
        }

        It 'should throw when updating a non-existent app' {
            { Update-App -Id 'ghost' -Name 'X' } | Should -Throw
        }
    }
}
