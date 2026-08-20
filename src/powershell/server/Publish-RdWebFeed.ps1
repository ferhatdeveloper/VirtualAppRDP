#requires -Version 5.1
#requires -RunAsAdministrator
<#
.SYNOPSIS
    Workgroup RD Web HTML5 katalogunu doldurur.
    Microsoft RD Web Client /RDWeb/Pages/WebFeed.aspx kaynaklarini
    yerel Session Host TSAppAllowList'ten okur (ws08r2rdserver).
    Domain + RD Collection gerekmez.
#>
[CmdletBinding()]
param(
    [string]$WorkspaceName = 'EXFIN RemoteAPP',
    [string]$GatewayHost = '185.86.15.238',
    [string]$AppAlias = 'Tiger3Ent'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'
$ConfirmPreference = 'None'
$logDir = Join-Path $env:ProgramData 'RdpVirtualBoxApp\Logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$log = Join-Path $logDir 'rdweb-feed-publish.log'
$done = Join-Path $logDir 'rdweb-feed-publish.done'
function Write-FeedLog([string]$Message) {
    $line = '[{0}] {1}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $Message
    try { Add-Content -LiteralPath $log -Value $line -Encoding UTF8 } catch { }
    Write-Output $line
}

try { Remove-Item -LiteralPath $done -Force -ErrorAction SilentlyContinue } catch { }

$hostName = $env:COMPUTERNAME
Write-FeedLog ("START host={0} workspace={1} gateway={2}" -f $hostName, $WorkspaceName, $GatewayHost)

function Set-AppSettingValue {
    param(
        [xml]$Xml,
        [string]$Key,
        [string]$Value
    )
    $nodes = @($Xml.SelectNodes("/configuration/appSettings/add[@key='$Key']"))
    if ($nodes.Count -eq 0) {
        $parent = $Xml.SelectSingleNode('/configuration/appSettings')
        if ($null -eq $parent) { throw "appSettings missing for $Key" }
        $el = $Xml.CreateElement('add')
        [void]$el.SetAttribute('key', $Key)
        [void]$el.SetAttribute('value', $Value)
        [void]$parent.AppendChild($el)
        return
    }
    foreach ($n in $nodes) { $n.SetAttribute('value', $Value) }
}

# --- RDWeb feed source (classic 2008 R2 Session Host WMI, works on workgroup) ---
$rdWebCfgPath = 'C:\Windows\Web\RDWeb\web.config'
if (-not (Test-Path -LiteralPath $rdWebCfgPath)) { throw "Missing $rdWebCfgPath" }
$bak = $rdWebCfgPath + '.exfin.bak'
if (-not (Test-Path -LiteralPath $bak)) {
    Copy-Item -LiteralPath $rdWebCfgPath -Destination $bak -Force
    Write-FeedLog "Backup $bak"
}
[xml]$rdXml = Get-Content -LiteralPath $rdWebCfgPath -Encoding UTF8
Set-AppSettingValue -Xml $rdXml -Key 'WorkspaceID' -Value $hostName
Set-AppSettingValue -Xml $rdXml -Key 'WorkspaceName' -Value $WorkspaceName
Set-AppSettingValue -Xml $rdXml -Key 'WorkspaceDescription' -Value $WorkspaceName
Set-AppSettingValue -Xml $rdXml -Key 'ws08r2rdserver' -Value $hostName
Set-AppSettingValue -Xml $rdXml -Key 'radcmserver' -Value ''
$rdXml.Save($rdWebCfgPath)
Write-FeedLog "RDWeb web.config WorkspaceID=$hostName WorkspaceName=$WorkspaceName ws08r2rdserver=$hostName"

# --- Pages: Gateway so WAN HTML5 launches through TCP 443 ---
$pagesCfgPath = 'C:\Windows\Web\RDWeb\Pages\web.config'
if (Test-Path -LiteralPath $pagesCfgPath) {
    $pbak = $pagesCfgPath + '.exfin.bak'
    if (-not (Test-Path -LiteralPath $pbak)) {
        Copy-Item -LiteralPath $pagesCfgPath -Destination $pbak -Force
    }
    [xml]$pXml = Get-Content -LiteralPath $pagesCfgPath -Encoding UTF8
    Set-AppSettingValue -Xml $pXml -Key 'DefaultTSGateway' -Value $GatewayHost
    Set-AppSettingValue -Xml $pXml -Key 'GatewayCredentialsSource' -Value '0'
    $pXml.Save($pagesCfgPath)
    Write-FeedLog "Pages DefaultTSGateway=$GatewayHost GatewayCredentialsSource=0"
}

# --- TS Web Access Computers (2008 R2 feed ACL) ---
$tswaGroup = 'TS Web Access Computers'
try {
    if (-not (Get-LocalGroup -Name $tswaGroup -ErrorAction SilentlyContinue)) {
        New-LocalGroup -Name $tswaGroup -Description 'RD Web Access feed computers' | Out-Null
        Write-FeedLog "Created group $tswaGroup"
    }
    $toAdd = @(
        "NT AUTHORITY\NETWORK SERVICE"
        "NT AUTHORITY\SYSTEM"
        "IIS APPPOOL\DefaultAppPool"
        ('{0}$' -f $hostName)
    )
    try {
        $pools = & "$env:windir\system32\inetsrv\appcmd.exe" list apppool /text:APPPOOL.NAME 2>$null
        foreach ($pool in @($pools)) {
            if ($pool) { $toAdd += ('IIS APPPOOL\{0}' -f $pool.Trim()) }
        }
    } catch { }
    foreach ($acct in ($toAdd | Select-Object -Unique)) {
        if ([string]::IsNullOrWhiteSpace($acct)) { continue }
        try {
            Add-LocalGroupMember -Group $tswaGroup -Member $acct -ErrorAction Stop
            Write-FeedLog "Added $acct to $tswaGroup"
        } catch {
            if ($_.Exception.Message -notmatch 'already a member') {
                Write-FeedLog ("WARN add {0}: {1}" -f $acct, $_.Exception.Message)
            }
        }
    }
} catch {
    Write-FeedLog ("WARN TSWA group: {0}" -f $_.Exception.Message)
}

# --- Restore / publish Tiger3Ent in TSAppAllowList (registry only; WMI Put can delete the app) ---
$exe = 'C:\LOGO\TIGER3ENT\Tiger3Enterprise.exe'
$allowRoot = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Terminal Server\TSAppAllowList'
$appsRoot = Join-Path $allowRoot 'Applications'
if (-not (Test-Path -LiteralPath $allowRoot)) { New-Item -Path $allowRoot -Force | Out-Null }
if (-not (Test-Path -LiteralPath $appsRoot)) { New-Item -Path $appsRoot -Force | Out-Null }
New-ItemProperty -LiteralPath $allowRoot -Name 'fDisabledAllowList' -Value 0 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
Set-ItemProperty -LiteralPath $allowRoot -Name 'fDisabledAllowList' -Value 0 -Type DWord -Force
$appKey = Join-Path $appsRoot $AppAlias
if (-not (Test-Path -LiteralPath $appKey)) { New-Item -Path $appKey -Force | Out-Null }
Set-ItemProperty -LiteralPath $appKey -Name 'Name' -Value 'Tiger3 Enterprise' -Type String -Force
Set-ItemProperty -LiteralPath $appKey -Name 'Path' -Value $exe -Type String -Force
Set-ItemProperty -LiteralPath $appKey -Name 'VPath' -Value $exe -Type String -Force
Set-ItemProperty -LiteralPath $appKey -Name 'IconPath' -Value $exe -Type String -Force
Set-ItemProperty -LiteralPath $appKey -Name 'IconIndex' -Value 0 -Type DWord -Force
Set-ItemProperty -LiteralPath $appKey -Name 'CommandLineSetting' -Value 1 -Type DWord -Force
Set-ItemProperty -LiteralPath $appKey -Name 'RequiredCommandLine' -Value '' -Type String -Force
Set-ItemProperty -LiteralPath $appKey -Name 'ShowInTSWebAccess' -Value 1 -Type DWord -Force
Set-ItemProperty -LiteralPath $appKey -Name 'ShowInTSWA' -Value 1 -Type DWord -Force
Set-ItemProperty -LiteralPath $appKey -Name 'Alias' -Value $AppAlias -Type String -Force
Write-FeedLog ("Registry restored {0} -> {1} exists={2}" -f $AppAlias, $exe, (Test-Path -LiteralPath $exe))

try {
    $listed = @(Get-WmiObject -Namespace root\cimv2\TerminalServices -Class Win32_TSPublishedApplication -ErrorAction Stop)
    Write-FeedLog ("WMI published count={0}" -f $listed.Count)
    foreach ($app in $listed) {
        Write-FeedLog ("WMI app alias={0} ShowInPortal={1} Path={2}" -f $app.Alias, $app.ShowInPortal, $app.Path)
    }
} catch {
    Write-FeedLog ("WARN WMI list: {0}" -f $_.Exception.Message)
}

# --- Workspace redirector (stale WIN-FAB395IK1BM) ---
try {
    $ws = Get-WmiObject -Namespace root\cimv2\TerminalServices -Class Win32_Workspace -ErrorAction Stop
    if ($ws) {
        $ws.Name = $WorkspaceName
        $ws.Redirector = $hostName
        $null = $ws.Put()
        Write-FeedLog ("Workspace Name={0} Redirector={1} ID={2}" -f $ws.Name, $ws.Redirector, $ws.ID)
    }
} catch {
    Write-FeedLog ("WARN Workspace Put: {0}" -f $_.Exception.Message)
}

try {
    $pub = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Terminal Server\CentralizedPublishing'
    if (Test-Path -LiteralPath $pub) {
        Set-ItemProperty -LiteralPath $pub -Name 'WorkspaceID' -Value $hostName -Type String -Force
        Set-ItemProperty -LiteralPath $pub -Name 'WorkspaceName' -Value $WorkspaceName -Type String -Force
        Set-ItemProperty -LiteralPath $pub -Name 'Redirector' -Value $hostName -Type String -Force
        Write-FeedLog 'CentralizedPublishing registry updated'
    }
} catch {
    Write-FeedLog ("WARN CentralizedPublishing: {0}" -f $_.Exception.Message)
}

# --- IIS recycle ---
try {
    & "$env:windir\system32\inetsrv\appcmd.exe" recycle apppool /apppool.name:"DefaultAppPool" | Out-Null
} catch { }
try { Restart-WebAppPool -Name 'DefaultAppPool' -ErrorAction SilentlyContinue } catch { }
try {
    Import-Module WebAdministration -ErrorAction SilentlyContinue
    Get-ChildItem IIS:\AppPools -ErrorAction SilentlyContinue | ForEach-Object {
        try { Restart-WebAppPool -Name $_.Name -ErrorAction SilentlyContinue } catch { }
    }
} catch { }
try { iisreset /noforce | Out-Null } catch { Write-FeedLog ("WARN iisreset: {0}" -f $_.Exception.Message) }
Start-Sleep -Seconds 4
Write-FeedLog 'IIS recycled'

# --- Verify WMI after put ---
try {
    Get-WmiObject -Namespace root\cimv2\TerminalServices -Class Win32_TSPublishedApplication |
        ForEach-Object { Write-FeedLog ("VERIFY app alias={0} ShowInPortal={1} Path={2}" -f $_.Alias, $_.ShowInPortal, $_.Path) }
} catch { }

'ok' | Set-Content -LiteralPath $done -Encoding ASCII
Write-FeedLog 'DONE'
exit 0
