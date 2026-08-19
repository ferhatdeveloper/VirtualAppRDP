#requires -Version 5.1
<#
.SYNOPSIS
    Generates (or verifies) a Linux-compatible SHA256SUMS.txt file for
    Rdp Virtual Box App build artifacts.

.DESCRIPTION
    Two operating modes:

      * Default / -Generate (which is the default action): hashes every
        file matching -Path (a directory or a single file) and writes a
        SHA256SUMS.txt file in the format produced by the GNU coreutils
        'sha256sum' utility:

            abc123...  RdpVirtualBoxApp-Client-v1.0.0.exe
            def456...  RdpVirtualBoxApp-Server-v1.0.0.exe

        The output is byte-compatible with 'sha256sum -c' so the same
        file can be verified on Linux, macOS and Windows.

      * -Verify: reads a SHA256SUMS.txt file and re-hashes every entry,
        reporting each as OK or FAILED. The exit code is 0 when all
        entries match, 1 when at least one does not.

    The script never touches the original files in -Verify mode - it
    only reads them - which makes it safe to run on production artifacts.

.PARAMETER Path
    When -Verify is not set: a directory or single file to hash. When
    -Verify is set: the path to the SHA256SUMS.txt file to validate.

.PARAMETER OutputFile
    When -Verify is not set: the destination SHA256SUMS.txt file.
    Defaults to "<Path>\SHA256SUMS.txt" when -Path is a directory, or
    "<Path directory>\SHA256SUMS.txt" when -Path is a file.

.PARAMETER Verify
    Switches the script into verification mode. The -Path parameter
    then denotes the SHA256SUMS.txt file.

.PARAMETER Recurse
    When -Path is a directory, recurse into subdirectories.

.PARAMETER Filter
    Optional glob pattern (e.g. "*.exe") used to limit the files that
    are hashed or verified. Forward and backward slashes are accepted.

.PARAMETER PassThru
    When set, the script returns the resulting SHA256SUMS.txt content
    (generate mode) or a verification result object (verify mode).

.PARAMETER Quiet
    Suppresses the per-file OK/FAILED lines emitted on the host during
    verification.

.EXAMPLE
    PS> .\SHA256-Verify.ps1 -Path .\build\output -OutputFile .\build\output\SHA256SUMS.txt

    Hashes every file in build\output and writes SHA256SUMS.txt.

.EXAMPLE
    PS> .\SHA256-Verify.ps1 -Path .\build\output\SHA256SUMS.txt -Verify

    Verifies every file referenced in SHA256SUMS.txt.

.EXAMPLE
    PS> Get-ChildItem .\build\output\*.exe | .\SHA256-Verify.ps1 -Path { $_ }

    Demonstrates pipeline-style usage against a single file.

.NOTES
    Author : Rdp Virtual Box App - Build & Manifest agent
    Module  : src/powershell/SHA256-Verify.ps1
    Compatible with: PowerShell 5.1 (Windows PowerShell) and PowerShell 7+
    Output format  : identical to GNU sha256sum / sha256sum -c
#>
[CmdletBinding(DefaultParameterSetName = 'Generate')]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string] $Path,

    [Parameter(ParameterSetName = 'Generate', Position = 1)]
    [string] $OutputFile,

    [Parameter(ParameterSetName = 'Verify')]
    [switch] $Verify,

    [Parameter(ParameterSetName = 'Generate')]
    [switch] $Recurse,

    [Parameter()]
    [string] $Filter = '*',

    [Parameter()]
    [switch] $PassThru,

    [Parameter(ParameterSetName = 'Verify')]
    [switch] $Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
$script:VerifyLogPath = Join-Path -Path $env:ProgramData -ChildPath 'RdpVirtualBoxApp\Logs\sha256-verify.log'

function Initialize-VerifyLog {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)

    $directory = Split-Path -Parent $Path
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -Path $directory -ItemType Directory -Force | Out-Null
    }
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -ItemType File -Force | Out-Null
    }
}

function Write-VerifyLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateSet('INFO', 'WARN', 'ERROR')] [string] $Level,
        [Parameter(Mandatory)] [string] $Message
    )

    try {
        $timestamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fffzzz')
        $line = "[$timestamp] [$Level] $Message"
        if ($script:VerifyLogPath -and (Test-Path -LiteralPath (Split-Path -Parent $script:VerifyLogPath))) {
            Add-Content -LiteralPath $script:VerifyLogPath -Value $line -Encoding UTF8
        }
    } catch {
        # Best-effort logging.
    }

    switch ($Level) {
        'INFO'  { Write-Verbose $Message }
        'WARN'  { Write-Warning $Message }
        'ERROR' { Write-Error   $Message }
    }
}

Initialize-VerifyLog -Path $script:VerifyLogPath

function Resolve-ArtifactRoot {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [bool]   $IsDirectory
    )

    if ($IsDirectory) { return $Path }

    # When hashing a single file, the manifest references paths relative
    # to the file's directory. GNU sha256sum uses the file name only.
    return (Split-Path -Parent $Path)
}

function Get-ArtifactFiles {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [bool]   $IsDirectory,
        [Parameter(Mandatory)] [bool]   $Recurse,
        [Parameter(Mandatory)] [string] $Filter
    )

    if ($IsDirectory) {
        $files = Get-ChildItem -LiteralPath $Path -File -Filter $Filter -Recurse:$Recurse -ErrorAction Stop
    } else {
        $files = Get-ChildItem -LiteralPath $Path -File -Filter $Filter -ErrorAction Stop
    }

    return @($files | Where-Object { $_.Name -notmatch '^SHA256SUMS(\.txt)?$' })
}

function Format-Sha256Line {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $HashLower,
        [Parameter(Mandatory)] [string] $RelativeName
    )

    # GNU 'sha256sum -c' parses two-space-separated columns. If the file
    # name begins with a space, the output is escaped with a leading
    # space and a backslash to keep the parser unambiguous - we replicate
    # that behaviour for consistency.
    if ($RelativeName.StartsWith(' ')) {
        return "$HashLower  \$RelativeName"
    }
    return "$HashLower  $RelativeName"
}

function Parse-Sha256Line {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)] [string] $Line)

    if ([string]::IsNullOrWhiteSpace($Line)) { return $null }

    # Skip comments.
    if ($Line.TrimStart().StartsWith('#')) { return $null }

    # sha256sum may emit escaped file names for leading-space cases.
    $hash = $null
    $name = $null

    if ($Line -match '^(?<hash>[0-9a-fA-F]{64})\s+(?<rest>.*)$') {
        $hash = $Matches['hash'].ToLower()
        $rest = $Matches['rest']
        if ($rest.StartsWith('\\') -and $rest.Length -gt 1) {
            # leading-space escape: "\ filename" -> " filename"
            $name = ' ' + $rest.Substring(1)
        } else {
            $name = $rest
        }

        return [pscustomobject]@{
            Hash   = $hash
            RelName = $name
        }
    }

    return $null
}

# ---------------------------------------------------------------------------
# Generate mode
# ---------------------------------------------------------------------------
function Invoke-Generate {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $OutputFile,
        [Parameter(Mandatory)] [bool]   $Recurse,
        [Parameter(Mandatory)] [string] $Filter,
        [Parameter(Mandatory)] [bool]   $PassThru
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Path not found: $Path"
    }

    $isDirectory = (Get-Item -LiteralPath $Path).PSIsContainer
    $artifactRoot = Resolve-ArtifactRoot -Path $Path -IsDirectory $isDirectory

    $files = Get-ArtifactFiles -Path $Path -IsDirectory $isDirectory -Recurse $Recurse -Filter $Filter

    if (-not $files -or $files.Count -eq 0) {
        Write-VerifyLog -Level WARN -Message "No files matched under '$Path' with filter '$Filter'."
    }

    $sb = New-Object System.Text.StringBuilder

    foreach ($file in $files) {
        try {
            $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256 -ErrorAction Stop).Hash.ToLower()
        } catch {
            Write-VerifyLog -Level ERROR -Message "Failed to hash '$($file.FullName)': $($_.Exception.Message)"
            throw
        }

        $relative = Resolve-RelativePath -BasePath $artifactRoot -TargetPath $file.FullName
        $line = Format-Sha256Line -HashLower $hash -RelativeName $relative
        [void]$sb.AppendLine($line)
        Write-VerifyLog -Level INFO -Message "Hashed $relative -> $hash"
    }

    $content = $sb.ToString()

    # Write the SHA256SUMS atomically: write to a temp file then move.
    $directory = Split-Path -Parent $OutputFile
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -Path $directory -ItemType Directory -Force | Out-Null
    }

    $tmp = "$OutputFile.tmp"
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($tmp, $content, $utf8)
    Move-Item -LiteralPath $tmp -Destination $OutputFile -Force

    $count = ($content -split "`r?`n" | Where-Object { $_ }).Count
    Write-VerifyLog -Level INFO -Message "Wrote $count entries to $OutputFile."

    if ($PassThru) {
        return $content
    }
    return $content
}

function Resolve-RelativePath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $BasePath,
        [Parameter(Mandatory)] [string] $TargetPath
    )

    $baseFull = (Resolve-Path -LiteralPath $BasePath).ProviderPath
    $targetFull = (Resolve-Path -LiteralPath $TargetPath).ProviderPath

    if ($targetFull.StartsWith($baseFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        $relative = $targetFull.Substring($baseFull.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
        if ([string]::IsNullOrEmpty($relative)) {
            $relative = Split-Path -Leaf $targetFull
        }
        return ($relative -replace '\\', '/')
    }

    return (Split-Path -Leaf $targetFull)
}

# ---------------------------------------------------------------------------
# Verify mode
# ---------------------------------------------------------------------------
function Invoke-Verify {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [bool]   $PassThru,
        [Parameter(Mandatory)] [bool]   $Quiet
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "SHA256SUMS file not found: $Path"
    }

    $sumsDir = Split-Path -Parent $Path
    $lines = Get-Content -LiteralPath $Path -Encoding UTF8

    $results = New-Object System.Collections.Generic.List[object]
    $failedCount = 0

    foreach ($line in $lines) {
        $entry = Parse-Sha256Line -Line $line
        if ($null -eq $entry) { continue }

        $candidate = Join-Path -Path $sumsDir -ChildPath $entry.RelName
        if (-not (Test-Path -LiteralPath $candidate)) {
            $failedCount++
            $results.Add([pscustomobject]@{
                File   = $entry.RelName
                Hash   = $entry.Hash
                Status = 'Missing'
            })
            if (-not $Quiet) { Write-Host "$(Resolve-VerifyDisplayName $entry.RelName): FAILED (missing file)" }
            continue
        }

        try {
            $actual = (Get-FileHash -LiteralPath $candidate -Algorithm SHA256 -ErrorAction Stop).Hash.ToLower()
        } catch {
            $failedCount++
            $results.Add([pscustomobject]@{
                File   = $entry.RelName
                Hash   = $entry.Hash
                Status = 'Error'
                Error  = $_.Exception.Message
            })
            if (-not $Quiet) { Write-Host "$(Resolve-VerifyDisplayName $entry.RelName): FAILED (hash error)" }
            continue
        }

        if ($actual -eq $entry.Hash) {
            $results.Add([pscustomobject]@{
                File   = $entry.RelName
                Hash   = $entry.Hash
                Status = 'OK'
            })
            if (-not $Quiet) { Write-Host "$(Resolve-VerifyDisplayName $entry.RelName): OK" }
        } else {
            $failedCount++
            $results.Add([pscustomobject]@{
                File   = $entry.RelName
                Hash   = $entry.Hash
                Actual = $actual
                Status = 'Mismatch'
            })
            if (-not $Quiet) { Write-Host "$(Resolve-VerifyDisplayName $entry.RelName): FAILED" }
        }
    }

    $summary = [pscustomobject]@{
        Total    = $results.Count
        Failed   = $failedCount
        Verified = ($results.Count - $failedCount)
        Results  = $results.ToArray()
    }

    if ($PassThru) {
        return $summary
    }

    if ($failedCount -gt 0) {
        Write-Error "$failedCount file(s) failed verification."
        # Throw to surface a non-zero exit code in scripts.
        throw "SHA256 verification failed: $failedCount mismatch(es)."
    }

    return $summary
}

function Resolve-VerifyDisplayName {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [string] $RelName)

    # GNU sha256sum uses just the relative name in the "-c" output, but
    # when the path was originally a full path it may contain folder
    # information. We use the basename for ergonomics.
    return ($RelName -replace '\\', '/')
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
try {
    if ($Verify) {
        $result = Invoke-Verify -Path $Path -PassThru:$PassThru -Quiet:$Quiet
        if ($PassThru) {
            return $result
        }
    } else {
        if (-not $OutputFile) {
            if (Test-Path -LiteralPath $Path) {
                $item = Get-Item -LiteralPath $Path
                if ($item.PSIsContainer) {
                    $OutputFile = Join-Path -Path $Path -ChildPath 'SHA256SUMS.txt'
                } else {
                    $OutputFile = Join-Path -Path (Split-Path -Parent $Path) -ChildPath 'SHA256SUMS.txt'
                }
            } else {
                throw "Path not found and -OutputFile not supplied: $Path"
            }
        }

        $generated = Invoke-Generate -Path $Path -OutputFile $OutputFile -Recurse:$Recurse -Filter $Filter -PassThru:$PassThru
        if ($PassThru) {
            return $generated
        }
    }

    return
}
catch {
    Write-VerifyLog -Level ERROR -Message "SHA256-Verify failed: $($_.Exception.Message)"
    throw
}

Export-ModuleMember -Function @(
    'Invoke-Generate'
    'Invoke-Verify'
    'Get-ArtifactFiles'
    'Parse-Sha256Line'
    'Format-Sha256Line'
)
