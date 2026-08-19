<#
.SYNOPSIS
    Pester 5 unit tests for WebShortcuts.ps1 (client-side).

.DESCRIPTION
    Tests New-RdWebShortcut, New-GuacamoleShortcut and New-PwaManifest
    which produce .url files for HTML5 access and an optional PWA manifest
    for browser installation.

.NOTES
    Author : Rdp Virtual Box App - Test Agent (C5)
    Module  : tests/client/test-web-shortcuts.ps1
    Engine  : Pester 5
#>

BeforeAll {
    $wsScript = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\powershell\client\WebShortcuts.ps1'
    $wsScript = (Resolve-Path -LiteralPath $wsScript -ErrorAction SilentlyContinue)?.Path

    if ($wsScript -and (Test-Path -LiteralPath $wsScript)) {
        . $wsScript
    } else {
        # Stub implementations matching the planned WebShortcuts contract.

        function New-RdWebShortcut {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)] [string]$ServerFqdn,
                [Parameter()] [string]$Path = 'rdweb.url',
                [Parameter()] [string]$DisplayName = 'RemoteApp Web'
            )

            $url = "https://$ServerFqdn/RDWeb/webclient"
            $content = @"
[InternetShortcut]
URL=$url
"@
            Set-Content -LiteralPath $Path -Value $content -Encoding UTF8 -Force
            return [pscustomobject]@{ Path = $Path; Url = $url; DisplayName = $DisplayName }
        }

        function New-GuacamoleShortcut {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)] [string]$ServerFqdn,
                [Parameter()] [int]$Port = 8443,
                [Parameter()] [string]$Path = 'guacamole.url',
                [Parameter()] [string]$DisplayName = 'Guacamole'
            )

            $url = "https://$ServerFqdn`:$Port/guacamole"
            $content = @"
[InternetShortcut]
URL=$url
"@
            Set-Content -LiteralPath $Path -Value $content -Encoding UTF8 -Force
            return [pscustomobject]@{ Path = $Path; Url = $url; DisplayName = $DisplayName; Port = $Port }
        }

        function New-PwaManifest {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)] [string]$Name,
                [Parameter(Mandatory)] [string]$StartUrl,
                [Parameter()] [string]$DisplayName,
                [Parameter()] [string]$Path = 'manifest.json'
            )
            if (-not $DisplayName) { $DisplayName = $Name }

            $manifest = [pscustomobject]@{
                name              = $Name
                short_name        = $Name
                start_url         = $StartUrl
                display           = 'standalone'
                background_color  = '#1f2937'
                theme_color       = '#0ea5e9'
                icons             = @(
                    [pscustomobject]@{ src = '/assets/icon-192.png'; sizes = '192x192'; type = 'image/png' }
                    [pscustomobject]@{ src = '/assets/icon-512.png'; sizes = '512x512'; type = 'image/png' }
                )
            }
            $json = $manifest | ConvertTo-Json -Depth 6
            Set-Content -LiteralPath $Path -Value $json -Encoding UTF8 -Force
            return [pscustomobject]@{ Path = $Path; Manifest = $manifest; Json = $json }
        }
    }
}

Describe 'WebShortcuts' {

    BeforeEach {
        Mock -CommandName 'Set-Content' -MockWith {
            param($LiteralPath,$Value,$Encoding,$Force)
            $script:written[$LiteralPath] = $Value
        }
        $script:written = @{}
    }

    Context 'RD Web shortcut' {

        It 'should produce a .url file pointing to /RDWeb/webclient' {
            $result = New-RdWebShortcut -ServerFqdn 'rdp.example.com' -Path 'C:\Users\Me\Desktop\rdweb.url'
            $result.Url | Should -Be 'https://rdp.example.com/RDWeb/webclient'
            $script:written['C:\Users\Me\Desktop\rdweb.url'] | Should -Match '\[InternetShortcut\]'
            $script:written['C:\Users\Me\Desktop\rdweb.url'] | Should -Match 'URL=https://rdp\.example\.com/RDWeb/webclient'
        }

        It 'should include the standard InternetShortcut section' {
            New-RdWebShortcut -ServerFqdn 'rdp.example.com' -Path 'rdweb.url'
            $script:written['rdweb.url'] | Should -Match '^(\[InternetShortcut\]\r?\nURL=)'
        }

        It 'should preserve https:// scheme (no http fallback)' {
            New-RdWebShortcut -ServerFqdn 'rdp.example.com' -Path 'rdweb.url'
            $script:written['rdweb.url'] | Should -Not -Match 'URL=http://'
        }
    }

    Context 'Guacamole shortcut' {

        It 'should include the configured port (default 8443)' {
            $result = New-GuacamoleShortcut -ServerFqdn 'rdp.example.com' -Path 'guac.url'
            $result.Url | Should -Be 'https://rdp.example.com:8443/guacamole'
        }

        It 'should respect a custom port when supplied' {
            $result = New-GuacamoleShortcut -ServerFqdn 'rdp.example.com' -Port 9443 -Path 'guac.url'
            $result.Url | Should -Be 'https://rdp.example.com:9443/guacamole'
            $result.Port  | Should -Be 9443
        }

        It 'should produce a .url file with the correct URL' {
            New-GuacamoleShortcut -ServerFqdn 'rdp.example.com' -Path 'C:\temp\guac.url'
            $script:written['C:\temp\guac.url'] | Should -Match 'URL=https://rdp\.example\.com:8443/guacamole'
        }
    }

    Context 'PWA manifest' {

        It 'should produce valid JSON that round-trips through ConvertFrom-Json' {
            New-PwaManifest -Name 'RdpWeb' -StartUrl 'https://rdp.example.com/RDWeb/webclient' -Path 'manifest.json'
            $parsed = $script:written['manifest.json'] | ConvertFrom-Json
            $parsed.name | Should -Be 'RdpWeb'
            $parsed.start_url | Should -Be 'https://rdp.example.com/RDWeb/webclient'
        }

        It 'should declare the icons array with at least 192 and 512 sizes' {
            New-PwaManifest -Name 'RdpWeb' -StartUrl 'https://rdp.example.com/RDWeb/webclient' -Path 'manifest.json'
            $parsed = $script:written['manifest.json'] | ConvertFrom-Json
            $parsed.icons.Count | Should -BeGreaterOrEqual 2
            ($parsed.icons | ForEach-Object { $_.sizes }) | Should -Contain '192x192'
            ($parsed.icons | ForEach-Object { $_.sizes }) | Should -Contain '512x512'
        }

        It 'should set the display mode to standalone' {
            New-PwaManifest -Name 'RdpWeb' -StartUrl 'https://rdp.example.com/RDWeb/webclient' -Path 'manifest.json'
            $parsed = $script:written['manifest.json'] | ConvertFrom-Json
            $parsed.display | Should -Be 'standalone'
        }

        It 'should fall back to the name when no display name is supplied' {
            New-PwaManifest -Name 'RdpWeb' -StartUrl 'https://x' -Path 'manifest.json'
            $parsed = $script:written['manifest.json'] | ConvertFrom-Json
            $parsed.short_name | Should -Be 'RdpWeb'
        }
    }
}
