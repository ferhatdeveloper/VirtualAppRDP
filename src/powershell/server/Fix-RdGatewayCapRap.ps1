#requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'
$log = 'C:\ProgramData\RdpVirtualBoxApp\Logs\rd-gateway-cap.log'
Start-Transcript -Path $log -Force | Out-Null
try {
    $rdpSid = New-Object Security.Principal.SecurityIdentifier 'S-1-5-32-555'
    $admSid = New-Object Security.Principal.SecurityIdentifier 'S-1-5-32-544'
    $rdpName = $rdpSid.Translate([Security.Principal.NTAccount]).Value
    $admName = $admSid.Translate([Security.Principal.NTAccount]).Value
    $groups = "$rdpName;$admName"
    Write-Output "groups=$groups"

    $capCls = [wmiclass]'root\CIMV2\TerminalServices:Win32_TSGatewayConnectionAuthorizationPolicy'
    Get-WmiObject -Namespace root\CIMV2\TerminalServices -Class Win32_TSGatewayConnectionAuthorizationPolicy |
        ForEach-Object { Write-Output ("OLD CAP $($_.Name) groups=$($_.UserGroupNames)") }

    $in = $capCls.GetMethodParameters('Create')
    foreach ($p in $in.Properties) { Write-Output ("CAP param $($p.Name)=$($p.Value)") }
    $in.Name = 'Exfin-CAP'
    $in.UserGroupNames = $groups
    $in.Enabled = $true
    if ($in.Properties['Password']) { $in.Password = $true }
    if ($in.Properties['SmartCard']) { $in.SmartCard = $false }
    if ($in.Properties['CookieAuthentication']) { $in.CookieAuthentication = $false }
    if ($in.Properties['IdleTimeout']) { $in.IdleTimeout = 120 }
    if ($in.Properties['SessionTimeout']) { $in.SessionTimeout = 480 }
    if ($in.Properties['DeviceRedirectionType']) { $in.DeviceRedirectionType = 2 }
    $capOut = $capCls.InvokeMethod('Create', $in, $null)
    Write-Output ('CAP ReturnValue=' + $capOut.ReturnValue + ' PolicyName=' + $capOut.PolicyName)

    $rapCls = [wmiclass]'root\CIMV2\TerminalServices:Win32_TSGatewayResourceAuthorizationPolicy'
    $rin = $rapCls.GetMethodParameters('Create')
    foreach ($p in $rin.Properties) { Write-Output ("RAP param $($p.Name)") }
    $rin.Name = 'Exfin-RAP'
    $rin.UserGroupNames = $groups
    $rin.Enabled = $true
    if ($rin.Properties['PortNumbers']) { $rin.PortNumbers = '3389' }
    if ($rin.Properties['ProtocolNames']) { $rin.ProtocolNames = 'RDP' }
    if ($rin.Properties['ResourceGroupType']) { $rin.ResourceGroupType = 2 }
    if ($rin.Properties['ResourceGroupName']) { $rin.ResourceGroupName = '' }
    if ($rin.Properties['Description']) { $rin.Description = 'EXFIN all resources 3389' }
    $rapOut = $rapCls.InvokeMethod('Create', $rin, $null)
    Write-Output ('RAP ReturnValue=' + $rapOut.ReturnValue + ' PolicyName=' + $rapOut.PolicyName)

    Get-WmiObject -Namespace root\CIMV2\TerminalServices -Class Win32_TSGatewayConnectionAuthorizationPolicy |
        ForEach-Object { Write-Output ("CAP $($_.Name) en=$($_.Enabled) groups=$($_.UserGroupNames) pwd=$($_.Password)") }
    Get-WmiObject -Namespace root\CIMV2\TerminalServices -Class Win32_TSGatewayResourceAuthorizationPolicy |
        ForEach-Object { Write-Output ("RAP $($_.Name) en=$($_.Enabled) groups=$($_.UserGroupNames) type=$($_.ResourceGroupType) ports=$($_.PortNumbers)") }

    $link = 'C:\Windows\Web\RDWeb\webclient'
    $target = 'C:\ProgramData\RdpVirtualBoxApp\RdWebClient\content'
    if (-not (Test-Path $link) -and (Test-Path $target)) {
        cmd /c "mklink /J `"$link`" `"$target`""
        Write-Output ('junction=' + (Test-Path $link))
    }

    Restart-Service TSGateway -Force
    Write-Output 'DONE'
    exit 0
} catch {
    Write-Output ('FAIL ' + $_.Exception.Message)
    Write-Output $_.ScriptStackTrace
    exit 1
} finally { Stop-Transcript | Out-Null }
