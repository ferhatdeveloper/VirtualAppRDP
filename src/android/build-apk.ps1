#Requires -Version 5.1
<#
.SYNOPSIS
  EXFIN RemoteAPP Android APK / Play Store AAB derleme yardimcisi.

.DESCRIPTION
  JDK 17 ve Android SDK gerekir. Android Studio aciksa SDK genellikle
  %LOCALAPPDATA%\Android\Sdk altindadir.

  Imzasiz release:  .\build-apk.ps1
  Imzali AAB:       .\build-apk.ps1 -Bundle
  Yerel upload key: .\New-ReleaseKeystore.ps1
#>
[CmdletBinding()]
param(
    [switch] $Bundle,
    [switch] $DebugApk
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$proj = Join-Path $root 'ExfinRemoteApp'
if (-not (Test-Path -LiteralPath (Join-Path $proj 'settings.gradle.kts'))) {
    throw "Android proje bulunamadi: $proj"
}

if (-not $env:ANDROID_HOME -and -not $env:ANDROID_SDK_ROOT) {
    $guess = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
    if (Test-Path -LiteralPath $guess) {
        $env:ANDROID_HOME = $guess
        $env:ANDROID_SDK_ROOT = $guess
        Write-Host "ANDROID_HOME = $guess"
    }
}

$java = Get-Command java -ErrorAction SilentlyContinue
if (-not $java) {
    throw "JDK 17 bulunamadi. Android Studio ile src\android\ExfinRemoteApp klasorunu acin veya JAVA_HOME ayarlayin."
}

$gradlew = Join-Path $proj 'gradlew.bat'
$task = if ($DebugApk) { 'assembleDebug' } elseif ($Bundle) { 'bundleRelease' } else { 'assembleRelease' }

Push-Location $proj
try {
    if (Test-Path -LiteralPath $gradlew) {
        & $gradlew $task --no-daemon
    } else {
        $gradle = Get-Command gradle -ErrorAction SilentlyContinue
        if (-not $gradle) {
            throw "gradlew.bat yok ve gradle PATH'te degil. Android Studio ile projeyi acin (wrapper uretilir)."
        }
        & gradle $task --no-daemon
    }
    if ($LASTEXITCODE -ne 0) { throw "Gradle $task exit $LASTEXITCODE" }
} finally {
    Pop-Location
}

$out = if ($DebugApk) {
    Join-Path $proj 'app\build\outputs\apk\debug'
} elseif ($Bundle) {
    Join-Path $proj 'app\build\outputs\bundle\release'
} else {
    Join-Path $proj 'app\build\outputs\apk\release'
}
Write-Host "Cikti: $out"
if (Test-Path -LiteralPath $out) {
    Get-ChildItem -LiteralPath $out -File | ForEach-Object { Write-Host ("  {0}  {1} bytes" -f $_.Name, $_.Length) }
}
