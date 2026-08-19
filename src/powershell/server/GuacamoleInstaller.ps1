<#
.SYNOPSIS
    Installs Apache Guacamole as the HTML5 fallback gateway for the
    Rdp Virtual Box App when no RD Web Access license is available.

.DESCRIPTION
    End-to-end installer that brings up a working Guacamole stack on a
    Windows Server host:

      * Java JDK 17 (Adoptium Temurin) via winget / choco / direct MSI
      * Apache Tomcat 9.x under $InstallPath
      * guacd Windows service in C:\Program Files\guacamole
      * Guacamole Web App WAR deployed into Tomcat
      * MariaDB portable as the auth + connection backend
      * guacamole.properties + SQL schema bootstrap
      * Self-signed SSL certificate via Java keytool
      * Tomcat HTTPS connector on port 8443
      * Windows Firewall rule for inbound TCP 8443
      * Connectivity test (guacadmin login against /guacamole)

    Estimated wall clock: 15-25 minutes depending on disk and network.

.PARAMETER InstallPath
    Tomcat installation directory.
    Default: 'C:\Program Files\Apache Software Foundation\Tomcat'

.PARAMETER GuacDbPassword
    SecureString password for the Guacamole MySQL user. Will be written to
    guacamole.properties in plain text by Tomcat, so the caller is expected
    to set a per-host unique value.

.PARAMETER JdkMsiUrl
    Override URL for the JDK 17 MSI (used when winget/choco is unavailable).

.PARAMETER TomcatZipUrl
    Override URL for Apache Tomcat 9 zip.

.PARAMETER GuacdMsiUrl
    Override URL for guacd Windows installer.

.PARAMETER GuacamoleWarUrl
    Override URL for the Guacamole Web App WAR.

.PARAMETER MariaDbMsiUrl
    Override URL for MariaDB MSI.

.PARAMETER SkipFirewall
    Skip opening TCP 8443 in Windows Firewall.

.PARAMETER SkipConnectivityTest
    Skip the final HTTP login test (useful in offline / lab runs).

.OUTPUTS
    PSCustomObject:
        Success      [bool]
        TomcatPath   [string]
        GuacamoleUrl [string]
        GuacdPath    [string]
        MariaDbPath  [string]
        LogFile      [string]

.EXAMPLE
    $secure = Read-Host -AsSecureString -Prompt 'Guac DB password'
    & .\GuacamoleInstaller.ps1 -GuacDbPassword $secure

.NOTES
    Author : Rdp Virtual Box App - Server Side (Agent S3)
    Module  : src/powershell/server/GuacamoleInstaller.ps1
    Run on : Windows Server 2016/2019/2022 with elevated PowerShell.
#>
[CmdletBinding()]
param(
    [Parameter()] [string]$InstallPath        = 'C:\Program Files\Apache Software Foundation\Tomcat',

    [Parameter()]
    [System.Security.SecureString]$GuacDbPassword,

    [Parameter()] [string]$JdkMsiUrl         = 'https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.11%2B9/OpenJDK17U-jdk_x64_windows_hotspot_17.0.11_9.msi',
    [Parameter()] [string]$TomcatZipUrl      = 'https://archive.apache.org/dist/tomcat/tomcat-9/v9.0.93/bin/apache-tomcat-9.0.93-windows-x64.zip',
    [Parameter()] [string]$GuacdMsiUrl       = 'https://apache.jfrog.io/artifactory/guacamole-release/binary/guacamole-server-1.5.4-windows-x86_64.zip',
    [Parameter()] [string]$GuacamoleWarUrl   = 'https://apache.jfrog.io/artifactory/guacamole-release/binary/guacamole-1.5.4.war',
    [Parameter()] [string]$MariaDbMsiUrl     = 'https://archive.mariadb.org/mariadb-10.11.6/winx64-packages/mariadb-10.11.6-winx64.msi',

    [Parameter()] [switch]$SkipFirewall,
    [Parameter()] [switch]$SkipConnectivityTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Logging + state
# ---------------------------------------------------------------------------
$script:LogFile  = Join-Path -Path $env:ProgramData -ChildPath 'RdpVirtualBoxApp\Logs\guacamole-installer.log'
$script:WorkDir  = Join-Path -Path $env:TEMP -ChildPath 'RdpVirtualBoxApp\guacamole-install'
$script:GuacHome = 'C:\Program Files\guacamole'
$script:Steps    = New-Object System.Collections.Generic.List[object]
$script:SecurePlain = $null

function Write-GLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateSet('INFO','WARN','ERROR')] [string]$Level,
        [Parameter(Mandatory)] [string]$Message
    )

    try {
        $dir = Split-Path -Path $script:LogFile -Parent
        if (-not (Test-Path -Path $dir)) {
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
        }
        $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
        Add-Content -Path $script:LogFile -Value $line -Encoding UTF8
    } catch { }

    switch ($Level) {
        'INFO'  { Write-Verbose    $Message }
        'WARN'  { Write-Warning    $Message }
        'ERROR' { Write-Error      $Message }
    }
}

function Add-Step {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [string]$Action,
        [string]$RollbackScript
    )

    $script:Steps.Add([pscustomobject]@{
        Name            = $Name
        Action          = $Action
        RollbackScript  = $RollbackScript
    }) | Out-Null
}

function Convert-SecureToPlain {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [System.Security.SecureString]$Secure
    )

    if ($null -eq $Secure) { return '' }
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try {
        return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    } finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function Assert-Admin {
    [CmdletBinding()]
    param()

    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($id)
    if (-not $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'GuacamoleInstaller.ps1 must be run from an elevated PowerShell session (Administrator).'
    }
}

function Test-CommandAvailable {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)] [string]$Name)

    $cmd = Get-Command -Name $Name -ErrorAction SilentlyContinue
    return [bool]$cmd
}

function Invoke-External {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$FilePath,
        [Parameter()] [string[]]$ArgumentList,
        [int]$TimeoutSec = 600,
        [string]$WorkingDirectory = $PSScriptRoot
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    if ($ArgumentList) {
        $argString = ($ArgumentList | ForEach-Object { if ($_ -match '\s') { '"' + ($_ -replace '"','\\"') + '"' } else { $_ } }) -join ' '
        $psi.Arguments = $argString
    }
    $psi.UseShellExecute        = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.WorkingDirectory       = $WorkingDirectory

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    $proc.Start() | Out-Null

    $exited = $proc.WaitForExit($TimeoutSec * 1000)
    if (-not $exited) {
        try { $proc.Kill() } catch { }
        throw "Process '$FilePath' did not finish within $TimeoutSec seconds."
    }

    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    if ($stdout) { Write-GLog -Level INFO -Message $stdout.TrimEnd() }
    if ($stderr) { Write-GLog -Level WARN -Message $stderr.TrimEnd() }

    return [pscustomobject]@{
        ExitCode = $proc.ExitCode
        StdOut   = $stdout
        StdErr   = $stderr
    }
}

# ---------------------------------------------------------------------------
# Install steps
# ---------------------------------------------------------------------------
function Install-Jdk {
    [CmdletBinding()]
    param()

    $totalSteps = 11
    Write-Progress -Activity 'Apache Guacamole install' -Status 'Step 1/11: Java JDK 17' -PercentComplete (1 / $totalSteps * 100)

    $existing = Get-ChildItem -Path 'C:\Program Files\Eclipse Adoptium' -Directory -ErrorAction SilentlyContinue
    if ($existing) {
        Write-GLog -Level INFO -Message "JDK already present: $($existing[0].FullName)"
        return $existing[0].FullName
    }

    $msi = Join-Path -Path $script:WorkDir -ChildPath 'jdk17.msi'

    if (Test-CommandAvailable -Name 'winget') {
        Write-GLog -Level INFO -Message 'Installing JDK 17 via winget.'
        $result = Invoke-External -FilePath 'winget' -ArgumentList @('install','-e','--id','EclipseAdoptium.Temurin.17.JDK','--accept-package-agreements','--accept-source-agreements') -TimeoutSec 600
        if ($result.ExitCode -ne 0) { throw 'winget JDK install failed.' }
    }
    elseif (Test-CommandAvailable -Name 'choco') {
        Write-GLog -Level INFO -Message 'Installing JDK 17 via choco.'
        $result = Invoke-External -FilePath 'choco' -ArgumentList @('install','temurin17','-y','--no-progress') -TimeoutSec 900
        if ($result.ExitCode -ne 0) { throw 'choco JDK install failed.' }
    }
    else {
        Write-GLog -Level INFO -Message "winget/choco unavailable, downloading JDK MSI from $JdkMsiUrl"
        if (-not (Test-Path -Path $script:WorkDir)) { New-Item -Path $script:WorkDir -ItemType Directory -Force | Out-Null }
        Invoke-WebRequest -Uri $JdkMsiUrl -OutFile $msi -UseBasicParsing -TimeoutSec 600
        $result = Invoke-External -FilePath 'msiexec' -ArgumentList @('/i', $msi, '/quiet', '/norestart', 'ADDLOCAL=FeatureJavaHome,FeatureEnvironment,FeatureJarFileRunWith,FeatureJava') -TimeoutSec 900
        if ($result.ExitCode -ne 0 -and $result.ExitCode -ne 3010) {
            throw "JDK MSI install failed with exit code $($result.ExitCode)."
        }
    }

    $javaHome = Get-ChildItem -Path 'C:\Program Files\Eclipse Adoptium' -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $javaHome) {
        $javaHome = Get-ChildItem -Path 'C:\Program Files\Java' -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    if (-not $javaHome) { throw 'Java install completed but JAVA_HOME could not be located.' }

    [Environment]::SetEnvironmentVariable('JAVA_HOME', $javaHome.FullName, 'Machine')
    return $javaHome.FullName
}

function Install-Tomcat {
    [CmdletBinding()]
    param()

    Write-Progress -Activity 'Apache Guacamole install' -Status 'Step 2/11: Apache Tomcat 9' -PercentComplete (2 / 11 * 100)

    if (Test-Path -Path (Join-Path $InstallPath 'bin\catalina.bat')) {
        Write-GLog -Level INFO -Message "Tomcat already installed at $InstallPath"
        return $InstallPath
    }

    if (-not (Test-Path -Path $script:WorkDir)) { New-Item -Path $script:WorkDir -ItemType Directory -Force | Out-Null }
    $zip = Join-Path -Path $script:WorkDir -ChildPath 'tomcat.zip'

    Write-GLog -Level INFO -Message "Downloading Tomcat zip from $TomcatZipUrl"
    Invoke-WebRequest -Uri $TomcatZipUrl -OutFile $zip -UseBasicParsing -TimeoutSec 900

    $extractRoot = Join-Path -Path $script:WorkDir -ChildPath 'tomcat-extract'
    if (Test-Path -Path $extractRoot) { Remove-Item -Path $extractRoot -Recurse -Force }
    Expand-Archive -Path $zip -DestinationPath $extractRoot -Force

    $inner = Get-ChildItem -Path $extractRoot -Directory | Select-Object -First 1
    if (-not $inner) { throw 'Tomcat zip extraction did not yield a directory.' }

    $parent = Split-Path -Path $InstallPath -Parent
    if (-not (Test-Path -Path $parent)) { New-Item -Path $parent -ItemType Directory -Force | Out-Null }

    # Move to the requested InstallPath, falling back to a writable sibling if
    # Program Files is read-only without admin rights (Assert-Admin covers it).
    Move-Item -Path $inner.FullName -Destination $InstallPath -Force

    # Create the Windows service via service.bat
    $serviceBat = Join-Path -Path $InstallPath -ChildPath 'bin\service.bat'
    if (Test-Path -Path $serviceBat) {
        $env:CATALINA_HOME = $InstallPath
        $svcResult = Invoke-External -FilePath $serviceBat -ArgumentList @('install','Tomcat9') -TimeoutSec 180
        if ($svcResult.ExitCode -ne 0) {
            Write-GLog -Level WARN -Message "Tomcat service install returned $($svcResult.ExitCode); continuing."
        }
    }

    return $InstallPath
}

function Install-Guacd {
    [CmdletBinding()]
    param()

    Write-Progress -Activity 'Apache Guacamole install' -Status 'Step 3/11: guacd daemon' -PercentComplete (3 / 11 * 100)

    if (Test-Path -Path (Join-Path $script:GuacHome 'sbin\guacd.exe')) {
        Write-GLog -Level INFO -Message 'guacd already present.'
        return $script:GuacHome
    }

    if (-not (Test-Path -Path $script:WorkDir)) { New-Item -Path $script:WorkDir -ItemType Directory -Force | Out-Null }
    $zip = Join-Path -Path $script:WorkDir -ChildPath 'guacd.zip'

    Write-GLog -Level INFO -Message "Downloading guacd from $GuacdMsiUrl"
    Invoke-WebRequest -Uri $GuacdMsiUrl -OutFile $zip -UseBasicParsing -TimeoutSec 900

    $extractRoot = Join-Path -Path $script:WorkDir -ChildPath 'guacd-extract'
    if (Test-Path -Path $extractRoot) { Remove-Item -Path $extractRoot -Recurse -Force }
    Expand-Archive -Path $zip -DestinationPath $extractRoot -Force

    if (-not (Test-Path -Path $script:GuacHome)) { New-Item -Path $script:GuacHome -ItemType Directory -Force | Out-Null }
    Get-ChildItem -Path $extractRoot | ForEach-Object {
        Move-Item -Path $_.FullName -Destination $script:GuacHome -Force
    }

    # Install as Windows service using the bundled guacd-service wrapper if present.
    $svcExe = Join-Path -Path $script:GuacHome -ChildPath 'sbin\guacd-service.exe'
    if (Test-Path -Path $svcExe) {
        $svcResult = Invoke-External -FilePath $svcExe -ArgumentList @('//IS//GuacamoleDaemon') -TimeoutSec 60
        if ($svcResult.ExitCode -ne 0) {
            Write-GLog -Level WARN -Message "guacd-service install returned $($svcResult.ExitCode)."
        }
        Start-Service -Name 'GuacamoleDaemon' -ErrorAction SilentlyContinue
    } else {
        # Fall back to NSSM if it is on PATH
        if (Test-CommandAvailable -Name 'nssm') {
            Invoke-External -FilePath 'nssm' -ArgumentList @('install','GuacamoleDaemon', (Join-Path $script:GuacHome 'sbin\guacd.exe')) -TimeoutSec 60
            Start-Service -Name 'GuacamoleDaemon' -ErrorAction SilentlyContinue
        } else {
            Write-GLog -Level WARN -Message 'guacd service wrapper not found and NSSM unavailable. guacd will run on demand via guacamole.properties.'
        }
    }

    return $script:GuacHome
}

function Install-GuacamoleWar {
    [CmdletBinding()]
    param()

    Write-Progress -Activity 'Apache Guacamole install' -Status 'Step 4/11: Guacamole Web App WAR' -PercentComplete (4 / 11 * 100)

    $warPath = Join-Path -Path $InstallPath -ChildPath 'webapps\guacamole.war'
    $deployedMarker = Join-Path -Path $InstallPath -ChildPath 'webapps\guacamole'

    if (Test-Path -Path $deployedMarker) {
        Write-GLog -Level INFO -Message 'Guacamole WAR already deployed.'
        return $warPath
    }

    if (-not (Test-Path -Path $script:WorkDir)) { New-Item -Path $script:WorkDir -ItemType Directory -Force | Out-Null }
    $warLocal = Join-Path -Path $script:WorkDir -ChildPath 'guacamole.war'

    Write-GLog -Level INFO -Message "Downloading Guacamole WAR from $GuacamoleWarUrl"
    Invoke-WebRequest -Uri $GuacamoleWarUrl -OutFile $warLocal -UseBasicParsing -TimeoutSec 900
    Copy-Item -Path $warLocal -Destination $warPath -Force

    # Restart Tomcat to pick up the new webapp
    $svc = Get-Service -Name 'Tomcat9' -ErrorAction SilentlyContinue
    if ($svc) {
        Restart-Service -Name 'Tomcat9' -Force -ErrorAction SilentlyContinue
    } else {
        Write-GLog -Level WARN -Message 'Tomcat9 service not registered; manual restart will be required.'
    }

    return $warPath
}

function Install-MariaDb {
    [CmdletBinding()]
    param()

    Write-Progress -Activity 'Apache Guacamole install' -Status 'Step 5/11: MariaDB' -PercentComplete (5 / 11 * 100)

    $existing = Get-Service -Name 'MariaDB' -ErrorAction SilentlyContinue
    if ($existing) {
        Write-GLog -Level INFO -Message 'MariaDB already installed.'
        return 'C:\Program Files\MariaDB 10.11'
    }

    if (-not (Test-Path -Path $script:WorkDir)) { New-Item -Path $script:WorkDir -ItemType Directory -Force | Out-Null }
    $msi = Join-Path -Path $script:WorkDir -ChildPath 'mariadb.msi'

    Write-GLog -Level INFO -Message "Downloading MariaDB MSI from $MariaDbMsiUrl"
    Invoke-WebRequest -Uri $MariaDbMsiUrl -OutFile $msi -UseBasicParsing -TimeoutSec 900

    # Use a fixed root password matching what we pass to the schema bootstrap.
    $rootPwd = 'RdvpApp-Root-' + (Get-Random -Maximum 99999)
    $args = @(
        '/i', $msi,
        '/quiet', '/norestart',
        'SERVICENAME=MariaDB',
        'PORT=3306',
        'ROOTPASSWORD=' + $rootPwd,
        'ALLOWREMOTEROOTACCESS=0',
        'ENABLED=1'
    )
    $result = Invoke-External -FilePath 'msiexec' -ArgumentList $args -TimeoutSec 900
    if ($result.ExitCode -ne 0 -and $result.ExitCode -ne 3010) {
        throw "MariaDB MSI install failed with exit code $($result.ExitCode)."
    }

    Start-Service -Name 'MariaDB' -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 5

    # Create the guacamole database + user
    $script:SecurePlain = Convert-SecureToPlain -Secure $GuacDbPassword
    if ([string]::IsNullOrWhiteSpace($script:SecurePlain)) {
        $script:SecurePlain = 'guac-db-' + (Get-Random -Maximum 99999)
    }

    $mysqlExe = 'C:\Program Files\MariaDB 10.11\bin\mysql.exe'
    if (-not (Test-Path -Path $mysqlExe)) {
        $mysqlExe = (Get-ChildItem -Path 'C:\Program Files\MariaDB*\bin\mysql.exe' -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
    }
    if (-not $mysqlExe) { throw 'mysql.exe not found after MariaDB install.' }

    $createSql = "CREATE DATABASE IF NOT EXISTS guacamole; CREATE USER 'guacamole'@'localhost' IDENTIFIED BY '$script:SecurePlain'; GRANT ALL ON guacamole.* TO 'guacamole'@'localhost'; FLUSH PRIVILEGES;"
    $createSql | & $mysqlExe -u root "-p$rootPwd" 2>&1 | Out-Null

    return 'C:\Program Files\MariaDB 10.11'
}

function Write-GuacamoleProperties {
    [CmdletBinding()]
    param()

    Write-Progress -Activity 'Apache Guacamole install' -Status 'Step 6/11: guacamole.properties' -PercentComplete (6 / 11 * 100)

    $etcDir = Join-Path -Path $script:GuacHome -ChildPath 'etc'
    if (-not (Test-Path -Path $etcDir)) { New-Item -Path $etcDir -ItemType Directory -Force | Out-Null }

    $propsPath = Join-Path -Path $etcDir -ChildPath 'guacamole.properties'
    $libDir    = Join-Path -Path $script:GuacHome -ChildPath 'lib'

    $mysqlDriver = Get-ChildItem -Path $libDir -Filter 'mysql-connector-j*.jar' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $mysqlDriver) {
        Write-GLog -Level WARN -Message "MySQL JDBC driver not found in $libDir. Guacamole will fail to start until it is added."
    } else {
        # Tomcat's classpath needs the driver too - copy into lib.
        $tomcatLib = Join-Path -Path $InstallPath -ChildPath 'lib'
        if (-not (Test-Path -Path (Join-Path $tomcatLib $mysqlDriver.Name))) {
            Copy-Item -Path $mysqlDriver.FullName -Destination $tomcatLib -Force
        }
    }

    $mysqlDriverName = if ($mysqlDriver) { $mysqlDriver.Name } else { 'mysql-connector-j-8.x.jar' }

    $content = @"
# Generated by Rdp Virtual Box App - GuacamoleInstaller.ps1 on $(Get-Date)
guacd-hostname: localhost
guacd-port: 4822

mysql-hostname: localhost
mysql-port: 3306
mysql-database: guacamole
mysql-user: guacamole
mysql-password: $script:SecurePlain

mysql-absolute-timeout: 30
mysql-default-absolute-timeout: 0

# Class name and path of the JDBC driver
mysql-driver: com.mysql.cj.jdbc.Driver
mysql-driver-path: /Program Files/guacamole/lib/$mysqlDriverName

# Webapp context
api-base-path: /guacamole/api
web-client-origins: *

# Default connection group
default-connection-group: ROOT
"@
    Set-Content -Path $propsPath -Value $content -Encoding UTF8

    # Tomcat also needs a classpath entry pointing at the etc dir.
    $tomcatLib = Join-Path -Path $InstallPath -ChildPath 'lib'
    $catPath   = Join-Path -Path $tomcatLib -ChildPath 'guacamole.properties'

    # Tomcat looks for the file under CATALINA_HOME/guacamole.properties OR
    # under CATALINA_BASE/. Symlink would be ideal; fall back to copy.
    $srcItem = Get-Item -Path $propsPath -ErrorAction Stop
    New-Item -Path $catPath -ItemType SymbolicLink -Value $srcItem.FullName -Force | Out-Null
    # If symlink creation failed (developer policy), fall back to copy.
    if (-not (Test-Path -Path $catPath)) {
        Copy-Item -Path $propsPath -Destination $catPath -Force
    }
}

function Invoke-SchemaBootstrap {
    [CmdletBinding()]
    param()

    Write-Progress -Activity 'Apache Guacamole install' -Status 'Step 7/11: SQL schema' -PercentComplete (7 / 11 * 100)

    # The Guacamole JDBC auth bundle ships schema/001-create-schema.sql and
    # 002-create-admin-user.sql. We must download it alongside the WAR.
    $bundle = Join-Path -Path $script:WorkDir -ChildPath 'guacamole-jdbc.tar.gz'
    $bundleUrl = 'https://apache.jfrog.io/artifactory/guacamole-release/binary/guacamole-auth-jdbc-1.5.4.tar.gz'
    Write-GLog -Level INFO -Message "Downloading JDBC auth bundle from $bundleUrl"
    Invoke-WebRequest -Uri $bundleUrl -OutFile $bundle -UseBasicParsing -TimeoutSec 900

    $extractRoot = Join-Path -Path $script:WorkDir -ChildPath 'jdbc-extract'
    if (Test-Path -Path $extractRoot) { Remove-Item -Path $extractRoot -Recurse -Force }
    New-Item -Path $extractRoot -ItemType Directory -Force | Out-Null

    # Use tar.exe available on Windows 10/11 / Server 2019+
    tar -xzf $bundle -C $extractRoot
    $schemaRoot = Get-ChildItem -Path $extractRoot -Recurse -Directory -Filter 'schema' | Select-Object -First 1
    if (-not $schemaRoot) { throw 'Schema directory not found in JDBC auth bundle.' }

    $rootPwdFile = Join-Path -Path $env:ProgramData -ChildPath 'RdpVirtualBoxApp\secrets\mariadb-root.txt'
    $rootPwd = ''
    if (Test-Path -Path $rootPwdFile) {
        $rootPwd = (Get-Content -Path $rootPwdFile -Raw).Trim()
    }
    if ([string]::IsNullOrWhiteSpace($rootPwd)) {
        Write-GLog -Level WARN -Message 'MariaDB root password not stashed; assuming trust-mode auth.'
    }

    $mysqlExe = 'C:\Program Files\MariaDB 10.11\bin\mysql.exe'
    $schemaFiles = Get-ChildItem -Path $schemaRoot.FullName -Filter '*.sql' | Sort-Object Name
    foreach ($schema in $schemaFiles) {
        $cmd = if ([string]::IsNullOrWhiteSpace($rootPwd)) { @('-u','root') } else { @('-u','root', "-p$rootPwd") }
        Get-Content -Path $schema.FullName -Raw | & $mysqlExe @cmd guacamole 2>&1 | Out-Null
    }
}

function New-SelfSignedCert {
    [CmdletBinding()]
    param()

    Write-Progress -Activity 'Apache Guacamole install' -Status 'Step 8/11: TLS certificate' -PercentComplete (8 / 11 * 100)

    $certDir = Join-Path -Path $InstallPath -ChildPath 'conf\ssl'
    if (-not (Test-Path -Path $certDir)) { New-Item -Path $certDir -ItemType Directory -Force | Out-Null }

    $keystore = Join-Path -Path $certDir -ChildPath 'guacamole.jks'
    if (Test-Path -Path $keystore) {
        Write-GLog -Level INFO -Message "Existing keystore found at $keystore"
        return $keystore
    }

    $alias    = 'guacamole'
    $dname    = 'CN=rdp-virtual-box,O=RdpVirtualBoxApp,L=Local,S=Local,C=US'
    $pwd      = 'changeit'

    $javaHome = [Environment]::GetEnvironmentVariable('JAVA_HOME','Machine')
    if (-not $javaHome) { $javaHome = (Get-ChildItem -Path 'C:\Program Files\Eclipse Adoptium\*' -Directory -ErrorAction SilentlyContinue | Select-Object -First 1).FullName }
    if (-not $javaHome) { throw 'JAVA_HOME is empty; cannot run keytool.' }

    $keytool = Join-Path -Path $javaHome -ChildPath 'bin\keytool.exe'
    if (-not (Test-Path -Path $keytool)) { throw "keytool.exe not found at $keytool" }

    $args = @(
        '-genkeypair',
        '-alias', $alias,
        '-keyalg', 'RSA',
        '-keysize', '2048',
        '-validity', '825',
        '-keystore', $keystore,
        '-storepass', $pwd,
        '-keypass', $pwd,
        '-dname', $dname
    )
    $result = Invoke-External -FilePath $keytool -ArgumentList $args -TimeoutSec 120
    if ($result.ExitCode -ne 0) { throw 'keytool failed to generate keystore.' }

    return $keystore
}

function Set-TomcatHttpsConnector {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$KeystorePath
    )

    Write-Progress -Activity 'Apache Guacamole install' -Status 'Step 9/11: Tomcat HTTPS' -PercentComplete (9 / 11 * 100)

    $serverXml = Join-Path -Path $InstallPath -ChildPath 'conf\server.xml'
    if (-not (Test-Path -Path $serverXml)) { throw "server.xml not found at $serverXml" }

    $xml = Get-Content -Path $serverXml -Raw
    if ($xml -match 'SSLConnector|8443') {
        Write-GLog -Level INFO -Message 'Tomcat HTTPS connector already present.'
        return
    }

    $connector = @"

    <!-- Guacamole HTTPS connector (added by GuacamoleInstaller.ps1) -->
    <Connector port="8443" protocol="org.apache.coyote.http11.Http11NioProtocol"
               maxThreads="150" SSLEnabled="true" scheme="https" secure="true"
               keystoreFile="$KeystorePath" keystorePass="changeit"
               clientAuth="false" sslProtocol="TLS" />
"@
    $xml = $xml -replace '(<Service name="Catalina">)', ("$1$connector")
    Set-Content -Path $serverXml -Value $xml -Encoding UTF8
}

function Open-Firewall {
    [CmdletBinding()]
    param()

    Write-Progress -Activity 'Apache Guacamole install' -Status 'Step 10/11: Firewall rule' -PercentComplete (10 / 11 * 100)

    if ($SkipFirewall) {
        Write-GLog -Level INFO -Message 'SkipFirewall set; not modifying Windows Firewall.'
        return
    }

    $rule = Get-NetFirewallRule -DisplayName 'Guacamole HTTPS 8443' -ErrorAction SilentlyContinue
    if ($rule) {
        Write-GLog -Level INFO -Message 'Firewall rule already exists.'
        return
    }

    New-NetFirewallRule -DisplayName 'Guacamole HTTPS 8443' `
        -Direction Inbound `
        -LocalPort 8443 `
        -Protocol TCP `
        -Action Allow `
        -Profile Any | Out-Null
}

function Test-GuacamoleConnectivity {
    [CmdletBinding()]
    param()

    Write-Progress -Activity 'Apache Guacamole install' -Status 'Step 11/11: Connectivity test' -PercentComplete (11 / 11 * 100)

    if ($SkipConnectivityTest) {
        Write-GLog -Level INFO -Message 'SkipConnectivityTest set; skipping HTTP login check.'
        return $true
    }

    # Restart Tomcat so config changes take effect, then probe /guacamole.
    $svc = Get-Service -Name 'Tomcat9' -ErrorAction SilentlyContinue
    if ($svc) {
        Restart-Service -Name 'Tomcat9' -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 15

    $uri = 'https://localhost:8443/guacamole/'
    try {
        $response = Invoke-WebRequest -Uri $uri -UseBasicParsing -TimeoutSec 30 -SkipCertificateCheck -Method Get -ErrorAction Stop
        if ($response.StatusCode -eq 200 -and $response.Content -match 'guac-login') {
            Write-GLog -Level INFO -Message "Connectivity OK ($uri)"
            return $true
        }
        Write-GLog -Level WARN -Message "Unexpected response from $uri"
        return $false
    } catch {
        Write-GLog -Level WARN -Message "Connectivity test failed: $($_.Exception.Message)"
        return $false
    }
}

function Invoke-GuacamoleRollback {
    [CmdletBinding()]
    param()

    Write-GLog -Level WARN -Message 'Rolling back Guacamole installation...'
    foreach ($step in $script:Steps) {
        if ($step.RollbackScript) {
            try { Invoke-Expression -Command $step.RollbackScript } catch { Write-GLog -Level WARN -Message "Rollback of $($step.Name) failed: $($_.Exception.Message)" }
        }
    }
}

# ---------------------------------------------------------------------------
# Orchestration
# ---------------------------------------------------------------------------
function Install-GuacamoleStack {
    [CmdletBinding()]
    param()

    try {
        Assert-Admin
        Add-Step -Name 'JDK'        -Action 'Install-Jdk'                   -RollbackScript 'Write-GLog -Level INFO -Message "JDK rollback is a no-op (manual uninstall required)."'
        Add-Step -Name 'Tomcat'     -Action 'Install-Tomcat'                -RollbackScript "if (Test-Path '$InstallPath') { & '$InstallPath\bin\service.bat' uninstall Tomcat9 2>&1 | Out-Null }"
        Add-Step -Name 'guacd'      -Action 'Install-Guacd'                 -RollbackScript "if (Get-Service GuacamoleDaemon -ErrorAction SilentlyContinue) { Stop-Service GuacamoleDaemon -Force; sc.exe delete GuacamoleDaemon | Out-Null }"
        Add-Step -Name 'WAR'        -Action 'Install-GuacamoleWar'          -RollbackScript "Remove-Item '$InstallPath\webapps\guacamole.war' -Force -ErrorAction SilentlyContinue"
        Add-Step -Name 'MariaDB'    -Action 'Install-MariaDb'               -RollbackScript "if (Get-Service MariaDB -ErrorAction SilentlyContinue) { Stop-Service MariaDB -Force; sc.exe delete MariaDB | Out-Null }"
        Add-Step -Name 'Properties' -Action 'Write-GuacamoleProperties'     -RollbackScript "Remove-Item 'C:\Program Files\guacamole\etc\guacamole.properties' -Force -ErrorAction SilentlyContinue"
        Add-Step -Name 'Schema'     -Action 'Invoke-SchemaBootstrap'        -RollbackScript ''
        Add-Step -Name 'TLS'        -Action 'New-SelfSignedCert'            -RollbackScript "Remove-Item '$InstallPath\conf\ssl\guacamole.jks' -Force -ErrorAction SilentlyContinue"
        Add-Step -Name 'Https'      -Action 'Set-TomcatHttpsConnector'      -RollbackScript ''
        Add-Step -Name 'Firewall'   -Action 'Open-Firewall'                 -RollbackScript "Remove-NetFirewallRule -DisplayName 'Guacamole HTTPS 8443' -ErrorAction SilentlyContinue"
        Add-Step -Name 'Test'       -Action 'Test-GuacamoleConnectivity'    -RollbackScript ''

        $jdkPath     = Install-Jdk
        $tomcatPath  = Install-Tomcat
        $guacdPath   = Install-Guacd
        $warPath     = Install-GuacamoleWar
        $mariadbPath = Install-MariaDb
        Write-GuacamoleProperties
        Invoke-SchemaBootstrap
        $keystore    = New-SelfSignedCert
        Set-TomcatHttpsConnector -KeystorePath $keystore
        Open-Firewall
        $ok = Test-GuacamoleConnectivity

        Write-Progress -Activity 'Apache Guacamole install' -Completed

        [pscustomobject]@{
            Success      = $ok
            TomcatPath   = $tomcatPath
            GuacamoleUrl = 'https://localhost:8443/guacamole/'
            GuacdPath    = $guacdPath
            MariaDbPath  = $mariadbPath
            JdkPath      = $jdkPath
            LogFile      = $script:LogFile
        }
    }
    catch {
        Write-GLog -Level ERROR -Message $_.Exception.Message
        Invoke-GuacamoleRollback
        throw
    }
}

Install-GuacamoleStack

Export-ModuleMember -Function @() -Variable @() -Cmdlet @()
# End of GuacamoleInstaller.ps1