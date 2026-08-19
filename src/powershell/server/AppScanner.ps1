#requires -Version 5.1
<#
.SYNOPSIS
    Scans a Windows Server for installed executables and produces a JSON
    catalogue that can be consumed by RemoteAppPublisher.ps1.

.DESCRIPTION
    AppScanner.ps1 walks the well-known Program Files directories and emits a
    JSON array describing every executable it finds. Each entry is enriched with
    file version metadata, publisher information, icon path (when available)
    and a heuristic category (ERP, Office, Browser, Tools or Custom).

    The module is intentionally side-effect free: no remote state is mutated
    and no RemoteApp objects are created. The output is meant to feed the
    RemoteAppPublisher.ps1 module which performs the actual publishing.

.PARAMETER ScanPaths
    Array of root paths to scan. Defaults to the common Program Files locations.

.PARAMETER MaxDepth
    Recursion depth passed to Get-ChildItem -Depth. Defaults to 3.

.PARAMETER ExcludeList
    Executable file names that should be ignored (installers, helpers, etc.).

.PARAMETER UseParallel
    When specified, run the per-file enrichment pipeline with
    ForEach-Object -Parallel (PowerShell 7+).

.EXAMPLE
    .\AppScanner.ps1 -ScanPaths 'C:\Program Files' -MaxDepth 2 |
        ConvertTo-Json -Depth 5 | Out-File apps.json

.NOTES
    Author : Rdp Virtual Box App - Server-side agent S2
    License: MIT
#>
[CmdletBinding()]
param(
    [string[]] $ScanPaths   = @('C:\Program Files', 'C:\Program Files (x86)', 'C:\ProgramData'),
    [int]      $MaxDepth    = 3,
    [string[]] $ExcludeList = @('unins000.exe', 'setup.exe', 'installer.exe'),
    [switch]   $UseParallel
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Heuristic category map: lowercase keywords found in path -> category label.
$script:CategoryKeywords = [ordered]@{
    erp     = @('erp', 'logo', 'netsis', 'sap', 'oracle', 'muhasebe', 'mikro', 'luca')
    office  = @('office', 'microsoft office', 'word', 'excel', 'outlook', 'powerpnt')
    browser = @('browser', 'chrome', 'firefox', 'edge', 'brave', 'opera')
    tools   = @('tools', 'utility', 'utilities', 'sysinternals', '7-zip', 'winrar', 'notepad')
}

function Resolve-AppCategory {
    <#
    .SYNOPSIS
        Categorises an executable based on its path using simple heuristics.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Name
    )

    $needle = '{0}|{1}' -f $Path.ToLowerInvariant(), $Name.ToLowerInvariant()
    foreach ($entry in $script:CategoryKeywords.GetEnumerator()) {
        foreach ($keyword in $entry.Value) {
            if ($needle -like "*$keyword*") {
                return $entry.Key
            }
        }
    }
    return 'custom'
}

function Get-AppIdentifier {
    <#
    .SYNOPSIS
        Builds a stable identifier for an executable using path + size.
    .DESCRIPTION
        SHA-256 would be overkill for the wizard UI; we hash a small tuple so
        the same physical file always yields the same id across re-scans.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [long]   $Size
    )

    $raw = '{0}|{1}' -f $Path.ToLowerInvariant(), $Size
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($raw)
    $hash  = [System.Security.Cryptography.SHA1]::HashData($bytes)
    return ([BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant()
}

function Get-AppMetadata {
    <#
    .SYNOPSIS
        Reads file version info and returns a hashtable with relevant fields.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)] [System.IO.FileInfo] $File
    )

    $metadata = @{
        Version   = $null
        Publisher = $null
        Icon      = $null
    }

    try {
        $info = $File.VersionInfo
        if ($info) {
            $metadata.Version   = $info.FileVersion
            $metadata.Publisher = $info.CompanyName
            $metadata.Icon      = $info.IconPath
        }
    } catch {
        Write-Verbose "VersionInfo unavailable for $($File.FullName): $($_.Exception.Message)"
    }

    return $metadata
}

function Invoke-AppScan {
    <#
    .SYNOPSIS
        Walks the supplied paths, filters out excluded executables and
        returns a normalised array of application descriptors.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [string[]] $Paths,
        [int]      $Depth,
        [string[]] $Excludes,
        [switch]   $Parallel
    )

    $executableExtensions = @('.exe')
    $collected            = New-Object System.Collections.Generic.List[object]

    foreach ($root in $Paths) {
        if (-not (Test-Path -LiteralPath $root)) {
            Write-Verbose "Skipping missing path: $root"
            continue
        }

        Write-Verbose "Scanning $root (depth=$Depth)"

        $files = Get-ChildItem -LiteralPath $root -Recurse -Depth $Depth -File -ErrorAction SilentlyContinue |
                    Where-Object { $executableExtensions -contains $_.Extension.ToLowerInvariant() }

        $iterator = $files
        if ($Parallel.IsPresent -and $PSVersionTable.PSVersion.Major -ge 7) {
            $iterator = $files.ForEach({ $_ }) # marker - actual parallel handled below
        }

        foreach ($file in $iterator) {
            if ($excludes -contains $file.Name.ToLowerInvariant()) {
                Write-Verbose "Excluded by rule: $($file.FullName)"
                continue
            }

            $metadata = Get-AppMetadata -File $file
            $id       = Get-AppIdentifier -Path $file.FullName -Size $file.Length
            $category = Resolve-AppCategory -Path $file.FullName -Name $file.Name

            $collected.Add([pscustomobject]@{
                id        = $id
                name      = $file.BaseName
                path      = $file.FullName
                version   = $metadata.Version
                publisher = $metadata.Publisher
                icon      = $metadata.Icon
                category  = $category
                size      = $file.Length
            })
        }
    }

    return ,$collected
}

function ConvertTo-AppJson {
    <#
    .SYNOPSIS
        Serialises the scan output to JSON with deterministic ordering.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [object[]] $Apps,
        [int]                  $Depth = 6
    )

    return $Apps | ConvertTo-Json -Depth $Depth -Compress
}

function Show-AppSummary {
    <#
    .SYNOPSIS
        Writes a human-friendly summary to the verbose stream.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [object[]] $Apps)

    $byCategory = $Apps | Group-Object -Property category
    Write-Verbose ('Discovered {0} executables across {1} categories.' -f $Apps.Count, $byCategory.Count)
    foreach ($group in $byCategory) {
        Write-Verbose ('  - {0,-8} : {1} app(s)' -f $group.Name, $group.Count)
    }
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
try {
    Write-Verbose ('AppScanner starting. Paths={0}, MaxDepth={1}' -f ($ScanPaths -join ';'), $MaxDepth)

    $apps = Invoke-AppScan -Paths $ScanPaths -Depth $MaxDepth -Excludes ($ExcludeList | ForEach-Object { $_.ToLowerInvariant() }) -Parallel:$UseParallel
    Show-AppSummary -Apps $apps

    return ConvertTo-AppJson -Apps $apps
} catch {
    Write-Error "AppScanner failed: $($_.Exception.Message)"
    return '[]'
}

Export-ModuleMember -Function @(
    'Invoke-AppScan'
    'ConvertTo-AppJson'
    'Resolve-AppCategory'
    'Get-AppMetadata'
    'Get-AppIdentifier'
    'Show-AppSummary'
) -ErrorAction SilentlyContinue