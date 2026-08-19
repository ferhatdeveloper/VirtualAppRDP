<#
.SYNOPSIS
    Shared Pester helpers for the Rdp Virtual Box App test suite.

.DESCRIPTION
    Provides reusable building blocks so each test file stays focused on
    behaviour rather than boilerplate. Inspired by Pester's own
    Pester.Mock, this helper module:

      * computes a writable scratch directory for every test run
      * exposes a New-MockContext helper that returns a fresh PSObject
        used to capture mock invocations across nested Mocks
      * exposes a few pure-logic helpers we can call regardless of the
        platform (the real installers run on Windows only)

.NOTES
    Author : Rdp Virtual Box App - Test Coverage Agent
    Module  : tests/test-helpers.ps1
    Engine  : Pester 5.4+
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Scratch directory provider
# ---------------------------------------------------------------------------
function Get-RdsTestScratchDir {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [string]$Prefix = 'RdsVbaTests'
    )

    $base = [System.IO.Path]::GetTempPath()
    $dir  = Join-Path -Path $base -ChildPath $Prefix
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }
    return $dir
}

function New-RdsTestLogPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$BaseName
    )

    $dir = Get-RdsTestScratchDir
    return (Join-Path -Path $dir -ChildPath ('{0}-{1}.log' -f $BaseName, ([guid]::NewGuid())))
}

# ---------------------------------------------------------------------------
# Mock invocation collector — accessible from any nested Mock scope.
# ---------------------------------------------------------------------------
function New-RdsMockContext {
    <#
    .SYNOPSIS
        Returns a fresh hashtable with a List to record mock invocations.
    .DESCRIPTION
        Inside a Mock body, `$mockContext.Record('cmdlet', $args)` records
        that the cmdlet was called. Tests inspect the list afterwards.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]

    return @{
        Calls = New-Object System.Collections.Generic.List[object]
        Record = [scriptblock]::Create({
            param($Name, $Params)
            $Calls.Add([pscustomobject]@{ Name = $Name; Params = $Params })
        }.GetNewClosure())
    }
}

# ---------------------------------------------------------------------------
# Pure logic helpers — duplicated mirrors of source logic so tests can
# assert *expected* behaviour without touching the real installers.
# ---------------------------------------------------------------------------
function Format-RdsTestCredentialTarget {
    param([string]$Namespace, [string]$Server, [string]$AppId = '')
    $parts = @($Namespace, $Server.Trim())
    if ($AppId -and -not [string]::IsNullOrEmpty($AppId)) { $parts += $AppId }
    return ($parts -join ':')
}

function ConvertTo-RdsTestSecureString {
    param([Parameter(Mandatory)][string]$Plain)
    $secure = New-Object System.Security.SecureString
    foreach ($ch in $Plain.ToCharArray()) { $secure.AppendChar($ch) }
    $secure.MakeReadOnly()
    return $secure
}

function Assert-ThrowsWithMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [Parameter(Mandatory)][string]$ExpectedMessage
    )

    $thrown = $null
    try {
        & $ScriptBlock
    } catch {
        $thrown = $_
    }
    $thrown | Should -Not -BeNullOrEmpty
    $thrown.Exception.Message | Should -Match $ExpectedMessage
}

Export-ModuleMember -Function @(
    'Get-RdsTestScratchDir'
    'New-RdsTestLogPath'
    'New-RdsMockContext'
    'Format-RdsTestCredentialTarget'
    'ConvertTo-RdsTestSecureString'
    'Assert-ThrowsWithMessage'
)
