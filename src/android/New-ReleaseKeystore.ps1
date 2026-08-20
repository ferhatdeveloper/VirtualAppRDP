#Requires -Version 5.1
<#
.SYNOPSIS
  Play Store / sideload icin yerel upload keystore uretir. Repoya yazmaz.

.DESCRIPTION
  keytool (JDK) gerekir. Cikti varsayilan: %USERPROFILE%\.exfin\exfin-upload.jks
  ve src\android\ExfinRemoteApp\keystore.properties (gitignored).
#>
[CmdletBinding()]
param(
    [string] $Alias = 'exfin',
    [string] $OutDir = (Join-Path $env:USERPROFILE '.exfin')
)

$ErrorActionPreference = 'Stop'
$keytool = Get-Command keytool -ErrorAction SilentlyContinue
if (-not $keytool) {
    throw "keytool yok. JDK 17 kurun (Android Studio ile gelir) ve PATH'e ekleyin."
}

$sec = Read-Host -AsSecureString -Prompt 'Keystore parolasi (en az 6 karakter)'
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
try { $pass = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
if ([string]::IsNullOrWhiteSpace($pass) -or $pass.Length -lt 6) {
    throw "Parola en az 6 karakter olmali."
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$jks = Join-Path $OutDir 'exfin-upload.jks'
if (Test-Path -LiteralPath $jks) {
    throw "Zaten var: $jks — silmeden uzerine yazilmaz."
}

$dname = 'CN=EXFIN RemoteAPP, OU=Mobile, O=EXFIN, L=Istanbul, C=TR'
& keytool -genkeypair -keystore $jks -alias $Alias -keyalg RSA -keysize 2048 -validity 10000 `
    -storepass $pass -keypass $pass -dname $dname
if ($LASTEXITCODE -ne 0) { throw "keytool exit $LASTEXITCODE" }

$propsPath = Join-Path $PSScriptRoot 'ExfinRemoteApp\keystore.properties'
@(
    "storeFile=$($jks.Replace('\', '\\'))"
    "storePassword=$pass"
    "keyAlias=$Alias"
    "keyPassword=$pass"
) | Set-Content -LiteralPath $propsPath -Encoding ASCII

Write-Host "Keystore: $jks"
Write-Host "Ozellikler: $propsPath (gitignored)"
Write-Host "Play Console'a bu JKS'yi yedekleyin. Kaybederseniz guncelleme yayinlayamazsiniz."
