#requires -RunAsAdministrator
$ErrorActionPreference = 'Continue'
Start-Transcript 'C:\ProgramData\RdpVirtualBoxApp\Logs\rd-gateway-rap.log' -Force | Out-Null
try {
    $cap = Get-WmiObject -Namespace root\CIMV2\TerminalServices -Class Win32_TSGatewayConnectionAuthorizationPolicy | Where-Object { $_.Name -eq 'Exfin-CAP' }
    if ($cap) {
        try { $cap.Password = $true; $null = $cap.Put(); Write-Output 'CAP Password=true' } catch { Write-Output ('CAP put ' + $_.Exception.Message) }
        Write-Output ($cap | Select-Object Name,Enabled,UserGroupNames,Password,SmartCard | Format-List | Out-String)
    }

    Import-Module RemoteDesktopServices
    Write-Output 'RDS tree:'
    if (Test-Path RDS:\GatewayServer) {
        Get-ChildItem RDS:\GatewayServer | ForEach-Object { Write-Output $_.Name }
        if (Test-Path RDS:\GatewayServer\CAP) { Get-ChildItem RDS:\GatewayServer\CAP | ForEach-Object { Write-Output ('CAP item ' + $_.Name) } }
        if (Test-Path RDS:\GatewayServer\RAP) { Get-ChildItem RDS:\GatewayServer\RAP | ForEach-Object { Write-Output ('RAP item ' + $_.Name) } }
    }

    $rdpSid = New-Object Security.Principal.SecurityIdentifier 'S-1-5-32-555'
    $rdpName = $rdpSid.Translate([Security.Principal.NTAccount]).Value
    $admSid = New-Object Security.Principal.SecurityIdentifier 'S-1-5-32-544'
    $admName = $admSid.Translate([Security.Principal.NTAccount]).Value

    # RAP via RDS provider
    try {
        if (-not (Test-Path 'RDS:\GatewayServer\RAP\Exfin-RAP')) {
            New-Item -Path 'RDS:\GatewayServer\RAP' -Name 'Exfin-RAP' -UserGroups @($rdpName, $admName) -ComputerGroupType 2 -Port 3389 -ErrorAction Stop
            Write-Output 'RDS New-Item RAP ok'
        } else { Write-Output 'RDS RAP exists' }
    } catch {
        Write-Output ('RDS RAP New-Item fail: ' + $_.Exception.Message)
        try {
            New-Item -Path 'RDS:\GatewayServer\RAP' -Name 'Exfin-RAP' -ErrorAction Stop
            Set-ItemProperty RDS:\GatewayServer\RAP\Exfin-RAP -Name UserGroups -Value @($rdpName, $admName)
            Write-Output 'RDS RAP created empty then set'
        } catch { Write-Output ('RDS RAP v2 fail: ' + $_.Exception.Message) }
    }

    Get-ChildItem RDS:\GatewayServer\RAP -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Output ('RAP ' + $_.Name)
        Get-ItemProperty $_.PSPath | Format-List | Out-String | Write-Output
    }

    $rapCls = [wmiclass]'root\CIMV2\TerminalServices:Win32_TSGatewayResourceAuthorizationPolicy'
    $rin = $rapCls.GetMethodParameters('Create')
    $rin.Name = 'Exfin-RAP-All'
    $rin.UserGroupNames = "$rdpName;$admName"
    $rin.Enabled = $true
    $rin.PortNumbers = '*'
    $rin.ProtocolNames = 'RDP'
    $rin.ResourceGroupType = 1
    $rin.ResourceGroupName = '*'
    $rin.Description = 'all'
    try {
        $o = $rapCls.InvokeMethod('Create', $rin, $null)
        Write-Output ('WMI RAP * Return=' + $o.ReturnValue)
    } catch { Write-Output ('WMI RAP * ' + $_.Exception.Message) }

    Get-WmiObject -Namespace root\CIMV2\TerminalServices -Class Win32_TSGatewayResourceAuthorizationPolicy |
        ForEach-Object { Write-Output ("RAP $($_.Name) type=$($_.ResourceGroupType) ports=$($_.PortNumbers) groups=$($_.UserGroupNames) proto=$($_.ProtocolNames)") }

    Restart-Service TSGateway -Force
    Write-Output 'DONE'
} catch {
    Write-Output ('FAIL ' + $_.Exception.Message)
} finally { Stop-Transcript | Out-Null }
