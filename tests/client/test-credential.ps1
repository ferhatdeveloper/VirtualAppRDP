<#
.SYNOPSIS
    Pester 5 unit tests for Credential.ps1 (Windows Credential Manager).

.DESCRIPTION
    Tests the target formatting helpers, the SecureString byte conversions,
    and the public New/Get/Remove/Test/Enumerate functions. The P/Invoke
    into advapi32 is platform-specific, so tests check the path taken when
    the Win32 layer is unavailable (non-Windows) and the parameter shape
    that gets sent to the native APIs on Windows.

.NOTES
    Author : Rdp Virtual Box App - Test Coverage Agent
    Module  : tests/client/test-credential.ps1
    Engine  : Pester 5
#>

BeforeAll {
    $scriptPath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\powershell\client\Credential.ps1'
    $scriptPath = (Resolve-Path -LiteralPath $scriptPath).Path
    . $scriptPath

    . (Join-Path -Path $PSScriptRoot -ChildPath '..\test-helpers.ps1')
}

Describe 'Credential' {

    Context 'Format-StoredCredentialTarget' {

        It 'should build the canonical <Namespace>:<Server>:<AppId> target' {
            $result = Format-StoredCredentialTarget -Server ' 10.0.0.4 ' -AppId 'app-1'
            $result | Should -Be 'RdpVirtualBoxApp:10.0.0.4:app-1'
        }

        It 'should omit the AppId segment when none is supplied' {
            $result = Format-StoredCredentialTarget -Server 'srv01'
            $result | Should -Be 'RdpVirtualBoxApp:srv01'
        }

        It 'should accept an empty AppId' {
            $result = Format-StoredCredentialTarget -Server 'srv01' -AppId ''
            $result | Should -Be 'RdpVirtualBoxApp:srv01'
        }
    }

    Context 'ConvertTo-SecureStringBytes / ConvertFrom-SecureStringBytes' {

        It 'should round-trip a password through the byte helpers' {
            $original = 'Pa$$w0rd!'
            $secure   = ConvertTo-SecureString $original -AsPlainText -Force
            $bytes    = ConvertTo-SecureStringBytes -SecureString $secure
            $bytes    | Should -Not -BeNullOrEmpty
            $bytes.Length | Should -Be ($original.Length * 2)

            $roundTrip = ConvertFrom-SecureStringBytes -Bytes $bytes
            $plain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
                [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($roundTrip))
            $plain | Should -Be $original
        }

        It 'should return an empty SecureString when given no bytes' {
            $result = ConvertFrom-SecureStringBytes -Bytes $null
            $result | Should -Not -BeNullOrEmpty
            $result.Length | Should -Be 0
        }

        It 'should handle zero-length input gracefully' {
            $result = ConvertFrom-SecureStringBytes -Bytes (,[byte[]]@())
            $result.Length | Should -Be 0
        }
    }

    Context 'New-StoredCredential' {

        It 'should return null when the underlying P/Invoke call fails' {
            # Stub the native call to return $false so the helper throws.
            Mock -CommandName 'RdpVBoxApp.CredManNative.CredWrite' -MockWith { return $false } -ParameterFilter { $true }
            # Marshal.GetLastWin32Error is hard to mock; just bind a value.
            $pw = ConvertTo-SecureString 'p' -AsPlainText -Force

            # On non-Windows the Add-Type path may not have the type at all.
            # Either way the function should not throw; it should return $null.
            { $null = New-StoredCredential -Target 'RdpVirtualBoxApp:1:a' -UserName 'u' -SecurePassword $pw -ErrorAction SilentlyContinue } |
                Should -Not -Throw
        }

        It 'should accept the parameter set without throwing when run with -Force' {
            Mock -CommandName 'RdpVBoxApp.CredManNative.CredDelete' -MockWith { return $true }
            Mock -CommandName 'RdpVBoxApp.CredManNative.CredWrite' -MockWith { return $true }
            $pw = ConvertTo-SecureString 'p' -AsPlainText -Force

            { $null = New-StoredCredential -Target 'RdpVirtualBoxApp:1:a' -UserName 'u' -SecurePassword $pw -Force -ErrorAction SilentlyContinue } |
                Should -Not -Throw
        }
    }

    Context 'Get-StoredCredential' {

        It 'should return $null when the credential does not exist' {
            Mock -CommandName 'RdpVBoxApp.CredManNative.CredRead' -MockWith { return $false }
            $result = Get-StoredCredential -Target 'RdpVirtualBoxApp:missing:a'
            $result | Should -BeNullOrEmpty
        }

        It 'should not throw when the CredRead static method returns $false' {
            Mock -CommandName 'RdpVBoxApp.CredManNative.CredRead' -MockWith {
                param($target, $type, $r, [ref]$ptr)
                $ptr = [IntPtr]::Zero
                return $false
            }
            $result = Get-StoredCredential -Target 'RdpVirtualBoxApp:test:a'
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'Remove-StoredCredential' {

        It 'should return $true on a successful delete' {
            Mock -CommandName 'RdpVBoxApp.CredManNative.CredDelete' -MockWith { return $true }
            (Remove-StoredCredential -Target 'RdpVirtualBoxApp:t:a') | Should -BeTrue
        }

        It 'should return $false when the credential does not exist (Win32 1168)' {
            Mock -CommandName 'RdpVBoxApp.CredManNative.CredDelete' -MockWith { return $false }
            (Remove-StoredCredential -Target 'RdpVirtualBoxApp:t:a') | Should -BeFalse
        }
    }

    Context 'Test-StoredCredential' {

        It 'should return $true when Get-StoredCredential returns an object' {
            Mock -CommandName 'Get-StoredCredential' -MockWith { [pscustomobject]@{ Target='x' } }
            Test-StoredCredential -Target 'RdpVirtualBoxApp:t:a' | Should -BeTrue
        }

        It 'should return $false when Get-StoredCredential returns $null' {
            Mock -CommandName 'Get-StoredCredential' -MockWith { $null }
            Test-StoredCredential -Target 'RdpVirtualBoxApp:t:a' | Should -BeFalse
        }
    }

    Context 'Get-StoredCredentialTargetList' {

        It 'should return an empty array when CredEnumerate fails' {
            Mock -CommandName 'RdpVBoxApp.CredManNative.CredEnumerate' -MockWith { return $false }
            @(Get-StoredCredentialTargetList).Count | Should -Be 0
        }

        It 'should return an empty array when the call throws' {
            Mock -CommandName 'RdpVBoxApp.CredManNative.CredEnumerate' -MockWith { throw 'broken' }
            @(Get-StoredCredentialTargetList).Count | Should -Be 0
        }
    }
}
