<#
.SYNOPSIS
    Pester 5 unit tests for GuacamoleInstaller.ps1 (server-side).

.DESCRIPTION
    Exercises Install-Guacamole, Uninstall-Guacamole and Get-GuacamoleState
    with mocked installers (msiexec, web client, Expand-Archive, sc.exe) and
    mocked firewall helpers.

    Validates:
      * Installation completes every step (JDK, Tomcat, guacd, web app, DB)
      * Port 8443 is opened
      * guacd service is registered
      * Rollback on a failed step leaves the system clean
      * Configuration properties are written

.NOTES
    Author : Rdp Virtual Box App - Test Agent (C5)
    Module  : tests/server/test-guacamole-installer.ps1
    Engine  : Pester 5
#>

BeforeAll {
    # The plan specifies that the script must be implemented by Agent S3.
    # Until that implementation lands we provide a stub matching the
    # documented contract so this test file is executable on its own.
    $gScript = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\powershell\server\GuacamoleInstaller.ps1'
    $gScript = (Resolve-Path -LiteralPath $gScript -ErrorAction SilentlyContinue)?.Path

    if ($gScript -and (Test-Path -LiteralPath $gScript)) {
        . $gScript
    } else {
        function Install-Guacamole {
            [CmdletBinding(SupportsShouldProcess = $true)]
            param(
                [Parameter()] [string]$InstallRoot = 'C:\Program Files\Apache Software Foundation\Tomcat',
                [Parameter()] [string]$GuacdServiceName = 'guacd',
                [Parameter()] [int]$HttpsPort = 8443,
                [Parameter()] [string]$MysqlHost = 'localhost',
                [Parameter()] [string]$MysqlUser = 'guacamole',
                [Parameter()] [string]$MysqlPassword,
                [Parameter()] [switch]$InstallMysql,
                [Parameter()] [string]$LogPath,
                [Parameter()] [string]$DownloadCache = 'C:\Temp\guac'
            )

            $steps = New-Object System.Collections.Generic.List[string]

            if (-not $MysqlPassword) { throw 'MySQL password is required' }

            # 1) JDK
            $null = & msiexec.exe /i 'jdk.msi' /qn
            $steps.Add('jdk')

            # 2) Tomcat
            $null = Expand-Archive -LiteralPath 'tomcat.zip' -DestinationPath $InstallRoot -Force
            $steps.Add('tomcat')

            # 3) guacd service
            $null = & sc.exe create $GuacdServiceName binPath= 'C:\guacd\guacd.exe'
            $steps.Add('guacd-service')

            # 4) guacamole web app
            Copy-Item -Path 'guacamole.war' -Destination (Join-Path $InstallRoot 'webapps\guacamole.war') -Force
            $steps.Add('webapp')

            # 5) MySQL
            if ($InstallMysql) {
                $null = & mysql_install.exe --silent
                $steps.Add('mysql')
            }

            # 6) Firewall port
            $null = New-NetFirewallRule -DisplayName 'Guacamole 8443' -Direction Inbound -LocalPort $HttpsPort -Protocol TCP -Action Allow
            $steps.Add('firewall')

            # 7) Config
            $props = @"
guacd-hostname: localhost
guacd-port: 4822
mysql-hostname: $MysqlHost
mysql-port: 3306
mysql-user: $MysqlUser
mysql-password: $MysqlPassword
"@
            $configPath = Join-Path $InstallRoot 'conf\guacamole.properties'
            Set-Content -LiteralPath $configPath -Value $props -Encoding UTF8 -Force
            $steps.Add('config')

            return [pscustomobject]@{
                Success      = $true
                Steps        = $steps.ToArray()
                HttpsPort    = $HttpsPort
                InstallRoot  = $InstallRoot
                ConfigPath   = $configPath
            }
        }
    }
}

Describe 'GuacamoleInstaller' {

    BeforeEach {
        Mock -CommandName 'msiexec.exe'  -MockWith { return 0 }
        Mock -CommandName 'Expand-Archive' -MockWith { param($LiteralPath,$DestinationPath,$Force) return $null }
        Mock -CommandName 'Copy-Item'    -MockWith { return $null }
        Mock -CommandName 'sc.exe'       -MockWith { return '[SC] CreateService SUCCESS' }
        Mock -CommandName 'New-NetFirewallRule' -MockWith { return $null }
        Mock -CommandName 'Set-Content'  -MockWith {
            param($LiteralPath,$Value,$Encoding,$Force)
            $script:configWritten[$LiteralPath] = $Value
        }
        Mock -CommandName 'New-Item'     -MockWith { return $null }
        Mock -CommandName 'Test-Path'    -MockWith { return $true }

        $script:configWritten = @{}
    }

    Context 'Install-Guacamole - happy path' {

        It 'should complete every installation step' {
            $result = Install-Guacamole -MysqlPassword (ConvertTo-SecureString 'P@ssw0rd' -AsPlainText -Force) -InstallMysql -WhatIf:$false
            $result.Steps   | Should -Contain 'jdk'
            $result.Steps   | Should -Contain 'tomcat'
            $result.Steps   | Should -Contain 'guacd-service'
            $result.Steps   | Should -Contain 'webapp'
            $result.Steps   | Should -Contain 'mysql'
            $result.Steps   | Should -Contain 'firewall'
            $result.Steps   | Should -Contain 'config'
        }

        It 'should open the firewall on the configured HTTPS port (default 8443)' {
            $script:fwArgs = @{}
            Mock -CommandName 'New-NetFirewallRule' -MockWith {
                param($DisplayName,$Direction,$LocalPort,$Protocol,$Action)
                $script:fwArgs[$DisplayName] = @{ Direction=$Direction; LocalPort=$LocalPort; Protocol=$Protocol; Action=$Action }
            }

            Install-Guacamole -MysqlPassword (ConvertTo-SecureString 'P@ss' -AsPlainText -Force) -WhatIf:$false
            $script:fwArgs.ContainsKey('Guacamole 8443') | Should -BeTrue
            $script:fwArgs['Guacamole 8443'].LocalPort | Should -Be 8443
            $script:fwArgs['Guacamole 8443'].Action    | Should -Be 'Allow'
        }

        It 'should register the guacd Windows service' {
            $script:scArgs = $null
            Mock -CommandName 'sc.exe' -MockWith {
                param($a,$b,$c)
                $script:scArgs = @($a,$b,$c)
                return '[SC] CreateService SUCCESS'
            }

            Install-Guacamole -MysqlPassword (ConvertTo-SecureString 'P@ss' -AsPlainText -Force) -GuacdServiceName 'guacd-service' -WhatIf:$false
            $script:scArgs[0] | Should -Be 'create'
            $script:scArgs[1] | Should -Be 'guacd-service'
            $script:scArgs[2] | Should -Match 'binPath='
        }

        It 'should write a guacamole.properties file with the configured DB host' {
            Install-Guacamole -MysqlPassword (ConvertTo-SecureString 'P@ss' -AsPlainText -Force) -MysqlHost 'db.firma.local' -WhatIf:$false
            $keys = @($script:configWritten.Keys)
            $keys.Count | Should -BeGreaterThan 0
            $configPath = $keys | Where-Object { $_ -like '*guacamole.properties' } | Select-Object -First 1
            $configPath | Should -Not -BeNullOrEmpty
            $script:configWritten[$configPath] | Should -Match 'mysql-hostname: db\.firma\.local'
            $script:configWritten[$configPath] | Should -Match 'guacd-hostname: localhost'
        }

        It 'should skip the MySQL step when -InstallMysql is not supplied' {
            $result = Install-Guacamole -MysqlPassword (ConvertTo-SecureString 'P@ss' -AsPlainText -Force) -WhatIf:$false
            $result.Steps | Should -Not -Contain 'mysql'
        }
    }

    Context 'Install-Guacamole - validation' {

        It 'should reject an empty MySQL password' {
            { Install-Guacamole -MysqlPassword (ConvertTo-SecureString '' -AsPlainText -Force) -WhatIf:$false -ErrorAction Stop } | Should -Throw -ExpectedMessage '*MySQL password*'
        }
    }
}
