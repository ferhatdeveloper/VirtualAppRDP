<#
.SYNOPSIS
    Windows Credential Manager wrapper for Rdp Virtual Box App client setup.

.DESCRIPTION
    Stores RDP / RemoteApp credentials in the Windows Credential Manager
    (Generic Credential type) using P/Invoke into advapi32's CredMan APIs
    (CredRead/CredWrite/CredDelete).

    Targets follow the convention `RdpVirtualBoxApp:<serverIp>:<appId>`. The
    `Ask later` mode is a no-op — nothing is written to the credential store.

.NOTES
    Std : CmdletBinding, try/catch, Verbose, English comments.
    Exposed functions:
        New-StoredCredential, Get-StoredCredential, Remove-StoredCredential,
        Test-StoredCredential, Get-StoredCredentialTargetList
#>

#Requires -Version 5.1

Set-StrictMode -Version Latest

$script:CredentialNamespace = 'RdpVirtualBoxApp'

# ---------------------------------------------------------------------------
# P/Invoke signatures for CredRead/CredWrite/CredDelete/C CredFree
# ---------------------------------------------------------------------------
if (-not ('RdpVBoxApp.CredManNative' -as [type])) {
    Add-Type -Namespace 'RdpVBoxApp' -Name 'CredManNative' -MemberDefinition @'
[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
public struct CREDENTIAL
{
    public uint Flags;
    public uint Type;
    public IntPtr TargetName;
    public IntPtr Comment;
    public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
    public uint CredentialBlobSize;
    public IntPtr CredentialBlob;
    public uint Persist;
    public uint AttributeCount;
    public IntPtr Attributes;
    public IntPtr TargetAlias;
    public IntPtr UserName;
}

public enum CRED_TYPE : uint
{
    Generic = 1,
    DomainPassword = 2,
    DomainCertificate = 3,
    DomainVisiblePassword = 4,
    GenericCertificate = 5,
    DomainExtended = 6,
    Maximum = 7
}

public enum CRED_PERSIST : uint
{
    Session = 1,
    LocalMachine = 2,
    Enterprise = 3
}

[DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
public static extern bool CredRead(string target, uint type, uint reservedFlag, out IntPtr CredentialPtr);

[DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
public static extern bool CredWrite([In] ref CREDENTIAL userCredential, uint flags);

[DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
public static extern bool CredDelete(string target, uint type, uint flags);

[DllImport("advapi32.dll", SetLastError = true)]
public static extern void CredFree(IntPtr cred);

[DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
public static extern bool CredEnumerate(string filter, uint flag, out uint count, out IntPtr credentialsArrayPtr);
'@ | Out-Null
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Format-StoredCredentialTarget {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string] $Server,
        [Parameter(Mandatory)][AllowEmptyString()][string] $AppId = ''
    )

    $parts = @($script:CredentialNamespace, $Server.Trim())
    if (-not [string]::IsNullOrEmpty($AppId)) { $parts += $AppId }
    return ($parts -join ':')
}

function ConvertTo-SecureStringBytes {
    [CmdletBinding()]
    [OutputType([byte[]])]
    param([Parameter(Mandatory)][System.Security.SecureString] $SecureString)

    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
    try {
        $length = [System.Runtime.InteropServices.Marshal]::ReadInt32($bstr, -4)
        $bytes  = New-Object 'byte[]' $length
        $copy   = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        $enc    = [System.Text.Encoding]::Unicode
        $raw    = $enc.GetBytes($copy)
        # Trim the trailing UTF-16 NUL pair if present so we don't embed a
        # null terminator in the credential blob.
        if ($raw.Length -ge 2 -and $raw[$raw.Length - 1] -eq 0 -and $raw[$raw.Length - 2] -eq 0) {
            return $raw[0..($raw.Length - 3)]
        }
        return $raw
    } finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) | Out-Null
    }
}

function ConvertFrom-SecureStringBytes {
    [CmdletBinding()]
    [OutputType([System.Security.SecureString])]
    param([Parameter(Mandatory)][byte[]] $Bytes)

    if ($null -eq $Bytes -or $Bytes.Length -eq 0) {
        return (New-Object System.Security.SecureString)
    }
    $str = [System.Text.Encoding]::Unicode.GetString($Bytes)
    $secure = New-Object System.Security.SecureString
    foreach ($ch in $str.ToCharArray()) { $secure.AppendChar($ch) }
    $secure.MakeReadOnly()
    return $secure
}

# ---------------------------------------------------------------------------
# Public functions
# ---------------------------------------------------------------------------
function New-StoredCredential {
    <#
    .SYNOPSIS  Persists a credential into the Windows Credential Manager.
    .DESCRIPTION
        Stores a SecureString password as a Generic Credential for the target
        "RdpVirtualBoxApp:<serverIp>:<appId>". Returns the target string on
        success.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]   $Target,
        [Parameter(Mandatory)][string]   $UserName,
        [Parameter(Mandatory)][System.Security.SecureString] $SecurePassword,
        [ValidateSet('Session','LocalMachine','Enterprise')]
        [string] $Persistence = 'LocalMachine',
        [switch] $Force
    )

    try {
        if ($PSCmdlet.ShouldProcess($Target, 'Write Credential')) {
            $cred = New-Object RdpVBoxApp.CredManNative+CREDENTIAL
            $cred.Type     = [uint32][RdpVBoxApp.CredManNative+CRED_TYPE]::Generic
            $cred.Persist  = [uint32]([RdpVBoxApp.CredManNative+CRED_PERSIST]::$Persistence)
            $cred.UserName = [System.Runtime.InteropServices.Marshal]::StringToCoTaskMemUni($UserName)
            $cred.TargetName = [System.Runtime.InteropServices.Marshal]::StringToCoTaskMemUni($Target)
            $cred.Comment  = [System.Runtime.InteropServices.Marshal]::StringToCoTaskMemUni("Stored by Rdp Virtual Box App on $(Get-Date -Format 's')")

            $bytes  = ConvertTo-SecureStringBytes -SecureString $SecurePassword
            $blob   = [System.Runtime.InteropServices.Marshal]::AllocCoTaskMem($bytes.Length)
            [System.Runtime.InteropServices.Marshal]::Copy($bytes, 0, $blob, $bytes.Length)
            $cred.CredentialBlob      = $blob
            $cred.CredentialBlobSize  = [uint32]$bytes.Length

            # Force a clean write.
            if ($Force) {
                Remove-StoredCredential -Target $Target -ErrorAction SilentlyContinue
            }

            $written = [RdpVBoxApp.CredManNative]::CredWrite([ref]$cred, 0)
            $err = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()

            # Clean unmanaged allocations.
            [System.Runtime.InteropServices.Marshal]::FreeCoTaskMem($cred.TargetName)
            [System.Runtime.InteropServices.Marshal]::FreeCoTaskMem($cred.Comment)
            [System.Runtime.InteropServices.Marshal]::FreeCoTaskMem($cred.UserName)
            [System.Runtime.InteropServices.Marshal]::FreeCoTaskMem($blob)

            if (-not $written) {
                throw "CredWrite failed (Win32 error $err)."
            }

            Write-Verbose ("Stored credential for target '{0}'." -f $Target)
            return $Target
        }
    } catch {
        Write-Error -ErrorRecord $_
        return $null
    }
}

function Get-StoredCredential {
    <#
    .SYNOPSIS  Retrieves a stored credential as a PSCustomObject.
    .DESCRIPTION
        Returns a PSCustomObject with Target, UserName, SecurePassword and
        LastWritten properties, or $null when the target doesn't exist.
    #>
    [CmdletBinding()]
    [OutputType([psobject])]
    param(
        [Parameter(Mandatory)][string] $Target
    )

    try {
        $ptr = [IntPtr]::Zero
        $ok  = [RdpVBoxApp.CredManNative]::CredRead(
            $Target,
            [uint32][RdpVBoxApp.CredManNative+CRED_TYPE]::Generic,
            0,
            [ref]$ptr
        )
        if (-not $ok) {
            $err = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
            if ($err -ne 1168) { # ERROR_NOT_FOUND
                Write-Verbose ("CredRead for '{0}' failed (Win32 {1})." -f $Target, $err)
            }
            return $null
        }
        try {
            $cred = [System.Runtime.InteropServices.Marshal]::PtrToStructure(
                $ptr,
                [type]'RdpVBoxApp.CredManNative+CREDENTIAL'
            )
            $user = if ($cred.UserName -ne [IntPtr]::Zero) {
                [System.Runtime.InteropServices.Marshal]::PtrToStringUni($cred.UserName)
            } else { '' }

            $secure = New-Object System.Security.SecureString
            if ($cred.CredentialBlobSize -gt 0 -and $cred.CredentialBlob -ne [IntPtr]::Zero) {
                $buf = New-Object 'byte[]' $cred.CredentialBlobSize
                [System.Runtime.InteropServices.Marshal]::Copy($cred.CredentialBlob, $buf, 0, [int]$cred.CredentialBlobSize)
                $secure = ConvertFrom-SecureStringBytes -Bytes $buf
            } else {
                $secure.MakeReadOnly()
            }

            $lastWritten = [datetime]::FromFileTimeUtc($cred.LastWritten.dwHighDateTime * 0x100000000 + $cred.LastWritten.dwLowDateTime)

            return [pscustomobject]@{
                Target         = $Target
                UserName       = $user
                SecurePassword = $secure
                LastWritten    = $lastWritten
                Type           = $cred.Type
            }
        } finally {
            [RdpVBoxApp.CredManNative]::CredFree($ptr) | Out-Null
        }
    } catch {
        Write-Error -ErrorRecord $_
        return $null
    }
}

function Remove-StoredCredential {
    <#
    .SYNOPSIS  Removes a stored credential. Returns $true on success.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string] $Target
    )

    try {
        if ($PSCmdlet.ShouldProcess($Target, 'Delete Credential')) {
            $deleted = [RdpVBoxApp.CredManNative]::CredDelete(
                $Target,
                [uint32][RdpVBoxApp.CredManNative+CRED_TYPE]::Generic,
                0
            )
            $err = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
            if (-not $deleted -and $err -ne 1168) {
                Write-Verbose ("CredDelete failed for '{0}' (Win32 {1})." -f $Target, $err)
                return $false
            }
            Write-Verbose ("Removed credential for target '{0}'." -f $Target)
            return $true
        }
    } catch {
        Write-Error -ErrorRecord $_
    }
    return $false
}

function Test-StoredCredential {
    <#
    .SYNOPSIS  Returns $true when a credential exists for the target.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string] $Target)

    return ($null -ne (Get-StoredCredential -Target $Target))
}

function Get-StoredCredentialTargetList {
    <#
    .SYNOPSIS  Lists all stored Rdp Virtual Box App credential targets.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    $results = New-Object System.Collections.Generic.List[string]
    try {
        $count = [uint32]0
        $arr   = [IntPtr]::Zero
        $ok = [RdpVBoxApp.CredManNative]::CredEnumerate(
            ($script:CredentialNamespace + '*'),
            0,
            [ref]$count,
            [ref]$arr
        )
        if (-not $ok) { return @() }
        try {
            $ptrSize = [System.Runtime.InteropServices.Marshal]::SizeOf([type][System.IntPtr])
            for ($i = 0; $i -lt $count; $i++) {
                $credPtr = [System.Runtime.InteropServices.Marshal]::ReadIntPtr($arr, $i * $ptrSize)
                $cred = [System.Runtime.InteropServices.Marshal]::PtrToStructure(
                    $credPtr, [type]'RdpVBoxApp.CredManNative+CREDENTIAL'
                )
                if ($cred.TargetName -ne [IntPtr]::Zero) {
                    $results.Add([System.Runtime.InteropServices.Marshal]::PtrToStringUni($cred.TargetName))
                }
            }
        } finally {
            [RdpVBoxApp.CredManNative]::CredFree($arr) | Out-Null
        }
    } catch {
        Write-Error -ErrorRecord $_
    }
    return $results.ToArray()
}

# ---------------------------------------------------------------------------
# Module exports (when dot-sourced as a .psm1)
# ---------------------------------------------------------------------------
if ($MyInvocation.MyCommand.Path -and $MyInvocation.MyCommand.Path -like '*.psm1') {
    Export-ModuleMember -Function @(
        'New-StoredCredential',
        'Get-StoredCredential',
        'Remove-StoredCredential',
        'Test-StoredCredential',
        'Get-StoredCredentialTargetList',
        'Format-StoredCredentialTarget'
    )
}