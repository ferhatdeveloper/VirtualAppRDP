<#
.SYNOPSIS
    Pester 5 unit tests for LicenseDetector.ps1 (server-side).

.DESCRIPTION
    Exercises the three documented scenarios:
      1. License present (RDS-Licensing installed + Get-RDLicenseConfiguration activated)
      2. No license (role missing or activation flag false)
      3. Grace period (no activated license but TermService registry reports
         a positive RemainingGracePeriodDays value)

    Get-WindowsFeature, Get-RDLicenseConfiguration, Get-Command and the
    registry path are all mocked globally (Pester's -ModuleName is only
    needed when the function lives in a real module, which is not the case
    here because we dot-source the script).

.NOTES
    Author : Rdp Virtual Box App - Test Agent (C5)
    Module  : tests/server/test-license-detector.ps1
    Engine  : Pester 5
#>

BeforeAll {
    $scriptPath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\powershell\server\LicenseDetector.ps1'
    $scriptPath = (Resolve-Path -LiteralPath $scriptPath).Path
    . $scriptPath

    # The script body executes at dot-source time and returns a single
    # PSCustomObject. Subsequent calls need a way to re-run the body with
    # different mocks in place, so we extract the body once, wrap it in a
    # closure that takes a LicenseServerHint parameter, and expose that
    # closure as Invoke-LicenseDetection. Helper functions are already in
    # scope from the dot-source.
    $raw = Get-Content -LiteralPath $scriptPath -Raw

    $bodyStart = $raw.IndexOf('# Main')
    $bodyEnd   = $raw.IndexOf('Export-ModuleMember')
    if ($bodyStart -lt 0 -or $bodyEnd -lt 0 -or $bodyEnd -le $bodyStart) {
        throw "Unable to locate the executable body inside $scriptPath"
    }
    $body = $raw.Substring($bodyStart, $bodyEnd - $bodyStart)

    # Build a scriptblock that runs the body with the script-level
    # $LicenseServerHint parameter in scope. Use ${...} variable expansion
    # so $body is interpolated but `$LicenseServerHint is kept literal.
    $sb = [scriptblock]::Create(@"
param(`$LicenseServerHint)
`$ErrorActionPreference = 'Stop'
$body
"@)

    function Invoke-LicenseDetection {
        param([string]$LicenseServerHint)
        & $sb -LicenseServerHint $LicenseServerHint
    }
}

Describe 'LicenseDetector' {

    BeforeEach {
        # Default mocks. Each Context overrides what it needs.
        Mock -CommandName 'Get-WindowsFeature' -MockWith {
            param($Name,$ErrorAction)
            if ($Name -eq 'RDS-Licensing') {
                return [pscustomobject]@{ Name = 'RDS-Licensing'; InstallState = 'Installed' }
            }
            return [pscustomobject]@{ Name = $Name; InstallState = 'Available' }
        }

        Mock -CommandName 'Test-Path' -MockWith {
            param($Path)
            if ($Path -like '*TermService*License*') { return $false }
            return $true
        }

        Mock -CommandName 'Get-ItemProperty' -MockWith { return $null }

        Mock -CommandName 'Get-Command' -MockWith {
            param($Name,$ErrorAction)
            # Make Get-RDLicenseConfiguration appear available by default;
            # specific tests override the mock for Get-RDLicenseConfiguration.
            if ($Name -eq 'Get-RDLicenseConfiguration') {
                return [pscustomobject]@{ Name = 'Get-RDLicenseConfiguration'; Source = 'RemoteDesktop' }
            }
            return $null
        }

        Mock -CommandName 'Get-RDLicenseConfiguration' -MockWith {
            [pscustomobject]@{ Activated = $false; LicenseServer = '' }
        }
    }

    Context 'Scenario 1: License is present' {

        BeforeEach {
            Mock -CommandName 'Get-RDLicenseConfiguration' -MockWith {
                [pscustomobject]@{
                    Activated     = $true
                    LicenseServer = 'lic.firma.local'
                    Mode          = 'PerUser'
                }
            }
        }

        It 'should report HasRdWebLicense as true' {
            $r = Invoke-LicenseDetection
            $r.HasRdWebLicense | Should -BeTrue
        }

        It 'should recommend Use RD Web' {
            $r = Invoke-LicenseDetection
            $r.Recommendation | Should -Be 'Use RD Web'
        }

        It 'should expose the resolved license server name' {
            $r = Invoke-LicenseDetection
            $r.LicenseServer | Should -Be 'lic.firma.local'
        }

        It 'should respect the LicenseServerHint when provided' {
            $r = Invoke-LicenseDetection -LicenseServerHint 'hint.firma.local'
            $r.LicenseServer | Should -Be 'hint.firma.local'
        }
    }

    Context 'Scenario 2: No license installed' {

        BeforeEach {
            Mock -CommandName 'Get-WindowsFeature' -MockWith {
                param($Name,$ErrorAction)
                # Role missing.
                return [pscustomobject]@{ Name = 'RDS-Licensing'; InstallState = 'Available' }
            }
        }

        It 'should report HasRdWebLicense as false' {
            $r = Invoke-LicenseDetection
            $r.HasRdWebLicense | Should -BeFalse
        }

        It 'should recommend Install Guacamole' {
            $r = Invoke-LicenseDetection
            $r.Recommendation | Should -Match 'Guacamole'
        }

        It 'should expose zero remaining grace days' {
            $r = Invoke-LicenseDetection
            $r.GracePeriodDays | Should -Be 0
        }

        It 'should still return a structured result object when no license is present' {
            $r = Invoke-LicenseDetection
            $r | Should -Not -BeNullOrEmpty
            $r.Detail | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Scenario 3: Grace period active' {

        BeforeEach {
            Mock -CommandName 'Test-Path' -MockWith {
                param($Path)
                if ($Path -like '*TermService*License*') { return $true }
                return $true
            }

            Mock -CommandName 'Get-ItemProperty' -MockWith {
                param($Path,$ErrorAction)
                return [pscustomobject]@{ GracePeriod = 45; SpecifiedLicenseServerList = '' }
            }
        }

        It 'should report HasRdWebLicense as false during grace period' {
            $r = Invoke-LicenseDetection
            $r.HasRdWebLicense | Should -BeFalse
        }

        It 'should expose the remaining grace period days' {
            $r = Invoke-LicenseDetection
            $r.GracePeriodDays | Should -Be 45
        }

        It 'should recommend Install Guacamole' {
            $r = Invoke-LicenseDetection
            $r.Recommendation | Should -Match 'Guacamole'
        }

        It 'should include a LICENSE_REQUIRED message in the Detail field' {
            $r = Invoke-LicenseDetection
            $r.Detail | Should -Match 'LISANS GEREKLI'
        }
    }
}
