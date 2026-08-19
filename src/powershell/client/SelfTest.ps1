<#
.SYNOPSIS
    Rdp Virtual Box App - client-side self-test and diagnostic report.

.DESCRIPTION
    A collection of lightweight diagnostic helpers used both by the wizard
    (manual "Test connection" feature) and by post-install validation.

    Exposed functions:
        Test-ServerConnection     - TCP reachability + optional RDP handshake.
        Test-WebEndpoint          - HTTP/HTTPS reachability for RDWeb / Guacamole.
        Test-Credential           - WinRM/SMB credential validation (server-side).
        Start-DiagnosticReport    - Runs the full suite, returns a report object
                                    and optionally writes it to a JSON file.

.NOTES
    Std : CmdletBinding, try/catch, Verbose, English comments.
    All tests are non-destructive and never write to the credential store.
#>

#Requires -Version 5.1

Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# Test-ServerConnection
# ---------------------------------------------------------------------------
function Test-ServerConnection {
    <#
    .SYNOPSIS  Probes the RDP port (default 3389) on the target server.
    .DESCRIPTION
        Returns a PSCustomObject describing:
            - Reachable : $true when the TCP port accepts connections.
            - LatencyMs : RTT in milliseconds when reachable.
            - RdpBanner : First bytes from the RDP handshake (when reachable).
            - Error     : Error message when unreachable.
    #>
    [CmdletBinding()]
    [OutputType([psobject])]
    param(
        [Parameter(Mandatory)][string] $Server,
        [int] $Port = 3389,
        [int] $TimeoutSeconds = 5
    )

    $result = [pscustomobject]@{
        Server    = $Server
        Port      = $Port
        Reachable = $false
        LatencyMs = -1
        RdpBanner = ''
        Error     = ''
    }

    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $iar = $tcp.BeginConnect($Server, $Port, $null, $null)
        $completed = $iar.AsyncWaitHandle.WaitOne($TimeoutSeconds * 1000, $false)
        if (-not $completed) {
            $tcp.Close()
            $result.Error = "Connection timed out after $TimeoutSeconds s."
            return $result
        }
        $tcp.EndConnect($iar)
        $result.Reachable = $true
        $result.LatencyMs = [int]([System.Diagnostics.Stopwatch]::StartNew().ElapsedMilliseconds)

        # Try to read a tiny RDP X.224 Connection Request banner.
        try {
            $stream = $tcp.GetStream()
            $stream.ReadTimeout = 1500
            $buf = New-Object 'byte[]' 32
            $read = $stream.Read($buf, 0, $buf.Length)
            if ($read -gt 0) {
                $result.RdpBanner = [BitConverter]::ToString($buf, 0, $read)
            }
            $stream.Close()
        } catch {
            $result.RdpBanner = "(no banner)"
        }
        $tcp.Close()
    } catch [System.Net.Sockets.SocketException] {
        $result.Error = $_.Exception.Message
    } catch {
        $result.Error = $_.Exception.Message
    }

    Write-Verbose ("Test-ServerConnection {0}:{1} -> {2}" -f $Server, $Port, $result.Reachable)
    return $result
}

# ---------------------------------------------------------------------------
# Test-WebEndpoint
# ---------------------------------------------------------------------------
function Test-WebEndpoint {
    <#
    .SYNOPSIS  Validates an HTML5 endpoint (RDWeb / Guacamole / custom URL).
    .PARAMETER Url  Full URL including scheme.
    .PARAMETER ExpectedStatusCode  HTTP status codes considered "ok" (default 200, 302, 401).
    #>
    [CmdletBinding()]
    [OutputType([psobject])]
    param(
        [Parameter(Mandatory)][string] $Url,
        [int[]] $ExpectedStatusCode = @(200, 302, 401),
        [int]   $TimeoutSeconds = 8
    )

    $result = [pscustomobject]@{
        Url         = $Url
        Reachable   = $false
        StatusCode  = 0
        ServerHeader = ''
        Title       = ''
        Error       = ''
    }

    try {
        # Normalize missing scheme.
        if ($Url -notmatch '^https?://') { $Url = "https://$Url" }

        $req = [System.Net.HttpWebRequest]::Create($Url)
        $req.Method          = 'GET'
        $req.Timeout         = $TimeoutSeconds * 1000
        $req.ReadWriteTimeout = $TimeoutSeconds * 1000
        $req.UserAgent       = 'RdpVirtualBoxApp/SelfTest'
        $req.AllowAutoRedirect = $false
        $req.ServerCertificateValidationCallback = { $true } # tolerate self-signed

        $resp = $req.GetResponse()
        $result.Reachable    = $true
        $result.StatusCode   = [int]$resp.StatusCode
        $result.ServerHeader = $resp.Headers['Server']
        if ($resp.ContentType -like 'text/html*') {
            $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
            $body   = $reader.ReadToEnd()
            $reader.Close()
            if ($body -match '<title>(?<t>[^<]+)</title>') {
                $result.Title = $matches['t']
            }
        }
        $resp.Close()
    } catch [System.Net.WebException] {
        if ($_.Exception.Response) {
            $result.StatusCode = [int]$_.Exception.Response.StatusCode
            $result.Reachable = $true
        } else {
            $result.Error = $_.Exception.Message
        }
    } catch {
        $result.Error = $_.Exception.Message
    }

    $result | Add-Member -NotePropertyName 'IsExpected' -NotePropertyValue ($ExpectedStatusCode -contains $result.StatusCode) -Force
    Write-Verbose ("Test-WebEndpoint {0} -> {1} (status {2})" -f $Url, $result.Reachable, $result.StatusCode)
    return $result
}

# ---------------------------------------------------------------------------
# Test-Credential
# ---------------------------------------------------------------------------
function Test-Credential {
    <#
    .SYNOPSIS  Validates that the supplied credential works against the
                target server. Supports two transports: WinRM (default) and SMB.
    .DESCRIPTION
        Returns a PSCustomObject with:
            - Success : $true when the credential authenticated.
            - Method  : 'WinRM' or 'SMB'.
            - Error   : Error message on failure.
        The SecureString password is consumed without writing it anywhere.
    #>
    [CmdletBinding()]
    [OutputType([psobject])]
    param(
        [Parameter(Mandatory)][string] $Server,
        [Parameter(Mandatory)][string] $UserName,
        [Parameter(Mandatory)][System.Security.SecureString] $Password,
        [ValidateSet('WinRM','SMB')]
        [string] $Method = 'WinRM',
        [int]    $Port = 0
    )

    $result = [pscustomobject]@{
        Server  = $Server
        User    = $UserName
        Method  = $Method
        Success = $false
        Error   = ''
    }

    try {
        $cred = New-Object System.Management.Automation.PSCredential($UserName, $Password)
        switch ($Method) {
            'WinRM' {
                $portArg = if ($Port -gt 0) { @{ Port = $Port } } else { @{} }
                $test = New-PSSession -ComputerName $Server -Credential $cred -ErrorAction Stop @portArg
                if ($test) {
                    $result.Success = $true
                    Remove-PSSession -Session $test -ErrorAction SilentlyContinue
                }
            }
            'SMB' {
                # Use WMI as a quick auth probe without touching shares.
                $wmires = Get-WmiObject -Class Win32_OperatingSystem -ComputerName $Server -Credential $cred -ErrorAction Stop
                if ($wmires) { $result.Success = $true }
            }
        }
    } catch {
        $result.Error = $_.Exception.Message
    }
    Write-Verbose ("Test-Credential {0}\\{1} ({2}) -> {3}" -f $Server, $UserName, $Method, $result.Success)
    return $result
}

# ---------------------------------------------------------------------------
# Start-DiagnosticReport
# ---------------------------------------------------------------------------
function Start-DiagnosticReport {
    <#
    .SYNOPSIS  Runs the full self-test suite and returns a structured report.
    .PARAMETER Server       Server hostname or IP.
    .PARAMETER Port         RDP port (default 3389).
    .PARAMETER WebUrl       Optional HTML5 endpoint URL.
    .PARAMETER Username     Optional user for credential validation.
    .PARAMETER Password     Optional SecureString password.
    .PARAMETER OutputPath   If supplied, the report is also written as JSON.
    #>
    [CmdletBinding()]
    [OutputType([psobject])]
    param(
        [Parameter(Mandatory)][string] $Server,
        [int]    $Port = 3389,
        [string] $WebUrl,
        [string] $Username,
        [System.Security.SecureString] $Password,
        [ValidateSet('WinRM','SMB')]
        [string] $CredentialMethod = 'WinRM',
        [string] $OutputPath
    )

    Write-Verbose ("Starting diagnostic report for {0}" -f $Server)
    $startedAt = Get-Date

    $tcpTest = Test-ServerConnection -Server $Server -Port $Port
    $webTest = $null
    $credTest = $null
    if ($WebUrl) { $webTest = Test-WebEndpoint -Url $WebUrl }
    if ($Username -and $Password) {
        $credTest = Test-Credential -Server $Server -UserName $Username -Password $Password -Method $CredentialMethod
    }

    $report = [pscustomobject]@{
        generatedAt = $startedAt.ToUniversalTime().ToString('o')
        server      = $Server
        port        = $Port
        tcp         = $tcpTest
        web         = $webTest
        credential  = $credTest
        summary     = [pscustomobject]@{
            tcpOk       = $tcpTest.Reachable
            webOk       = ($null -eq $webTest) -or $webTest.Reachable
            credentialOk = ($null -eq $credTest) -or $credTest.Success
            overall     = ($tcpTest.Reachable) -and
                          (($null -eq $webTest) -or $webTest.Reachable) -and
                          (($null -eq $credTest) -or $credTest.Success)
        }
    }

    if ($OutputPath) {
        try {
            $dir = Split-Path -Parent $OutputPath
            if ($dir -and -not (Test-Path -LiteralPath $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }
            $report | ConvertTo-Json -Depth 6 | Out-File -FilePath $OutputPath -Encoding utf8 -Force
            Write-Verbose ("Report written to {0}" -f $OutputPath)
        } catch {
            Write-Verbose ("Failed to write report: {0}" -f $_.Exception.Message)
        }
    }

    return $report
}

# ---------------------------------------------------------------------------
# Module exports (when dot-sourced as a .psm1)
# ---------------------------------------------------------------------------
if ($MyInvocation.MyCommand.Path -and $MyInvocation.MyCommand.Path -like '*.psm1') {
    Export-ModuleMember -Function @(
        'Test-ServerConnection',
        'Test-WebEndpoint',
        'Test-Credential',
        'Start-DiagnosticReport'
    )
}