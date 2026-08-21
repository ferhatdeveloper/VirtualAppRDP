#requires -RunAsAdministrator
$line = '185.86.15.238 ARZ'
$path = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
$cur = Get-Content -LiteralPath $path -ErrorAction Stop
if ($cur | Where-Object { $_ -match '^\s*185\.86\.15\.238\s+ARZ\b' }) {
    Write-Output 'hosts already has 185.86.15.238 ARZ'
} else {
    Add-Content -LiteralPath $path -Value $line -Encoding ASCII
    Write-Output 'added 185.86.15.238 ARZ'
}
ipconfig /flushdns | Out-Null
