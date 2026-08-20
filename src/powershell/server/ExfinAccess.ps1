#requires -Version 5.1
# EXFIN RemoteAPP — ikon, dosya onizleme, TOTP, istemci kayit/izin

if (-not ('ExfinTotp' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Security.Cryptography;
using System.Text;

public static class ExfinTotp {
    const string Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

    public static string NewSecret() {
        var bytes = new byte[20];
        using (var rng = RandomNumberGenerator.Create()) rng.GetBytes(bytes);
        return ToBase32(bytes);
    }

    public static string ToBase32(byte[] data) {
        if (data == null || data.Length == 0) return "";
        var sb = new StringBuilder();
        int buffer = 0, bits = 0;
        foreach (var b in data) {
            buffer = (buffer << 8) | b;
            bits += 8;
            while (bits >= 5) {
                bits -= 5;
                sb.Append(Alphabet[(buffer >> bits) & 31]);
            }
        }
        if (bits > 0) sb.Append(Alphabet[(buffer << (5 - bits)) & 31]);
        return sb.ToString();
    }

    public static byte[] FromBase32(string input) {
        var s = (input ?? "").Trim().ToUpperInvariant().Replace("=", "").Replace(" ", "");
        var bytes = new System.Collections.Generic.List<byte>();
        int buffer = 0, bits = 0;
        foreach (var ch in s) {
            int val = Alphabet.IndexOf(ch);
            if (val < 0) continue;
            buffer = (buffer << 5) | val;
            bits += 5;
            if (bits >= 8) {
                bits -= 8;
                bytes.Add((byte)((buffer >> bits) & 255));
            }
        }
        return bytes.ToArray();
    }

    public static long UnixSeconds() {
        // DateTimeOffset.ToUnixTimeSeconds() .NET 4.6+ gerektirir; PS 5.1 / .NET 4.5 icin epoch farki.
        DateTime epoch = new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc);
        return (long)(DateTime.UtcNow - epoch).TotalSeconds;
    }

    public static string CodeAt(string secret, long unixSeconds) {
        var key = FromBase32(secret);
        if (key == null || key.Length == 0) return "";
        long ts = unixSeconds / 30L;
        var msg = new byte[8];
        for (int i = 7; i >= 0; i--) { msg[i] = (byte)(ts & 255); ts >>= 8; }
        using (var hmac = new HMACSHA1(key)) {
            var hash = hmac.ComputeHash(msg);
            int off = hash[hash.Length - 1] & 15;
            int bin = ((hash[off] & 127) << 24)
                    | ((hash[off + 1] & 255) << 16)
                    | ((hash[off + 2] & 255) << 8)
                    | (hash[off + 3] & 255);
            int otp = bin % 1000000;
            return otp.ToString("D6");
        }
    }

    public static bool Verify(string secret, string code, int window) {
        if (string.IsNullOrWhiteSpace(secret) || string.IsNullOrWhiteSpace(code)) return false;
        code = code.Trim().Replace(" ", "");
        if (code.Length < 6) return false;
        if (window < 0) window = 0;
        if (window > 4) window = 4;
        long unix = UnixSeconds();
        bool ok = false;
        try {
            for (int i = -window; i <= window; i++) {
                string expect = CodeAt(secret, unix + (i * 30L));
                if (expect.Length == 0) continue;
                if (FixedEquals(expect, code)) ok = true;
            }
        } catch {
            return false;
        }
        return ok;
    }

    static bool FixedEquals(string a, string b) {
        if (a == null || b == null || a.Length != b.Length) return false;
        int diff = 0;
        for (int i = 0; i < a.Length; i++) diff |= a[i] ^ b[i];
        return diff == 0;
    }
}
'@
}

function Get-ExfinConfigDir {
    $override = [string]$env:RDPVB_EXFIN_CONFIG
    if (-not [string]::IsNullOrWhiteSpace($override)) { return $override }
    return (Join-Path $env:ProgramData 'RdpVirtualBoxApp\Config')
}

function Get-ExfinTotpPath { Join-Path (Get-ExfinConfigDir) 'totp.json' }
function Get-ExfinClientsPath { Join-Path (Get-ExfinConfigDir) 'clients.json' }

function Get-ExfinJsonProp {
    param($Object, [string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        foreach ($k in @($Object.Keys)) {
            if ([string]::Equals([string]$k, $Name, [StringComparison]::OrdinalIgnoreCase)) { return $Object[$k] }
        }
        return $Default
    }
    $p = $Object.PSObject.Properties[$Name]
    if ($p) { return $p.Value }
    return $Default
}

function ConvertTo-ExfinJsonText {
    param($Value)
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [bool]) { if ($Value) { return 'true' } else { return 'false' } }
    if ($Value -is [string]) {
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.Append('"')
        foreach ($ch in $Value.ToCharArray()) {
            switch ($ch) {
                '"'  { [void]$sb.Append('\"') }
                '\'  { [void]$sb.Append('\\') }
                "`n" { [void]$sb.Append('\n') }
                "`r" { [void]$sb.Append('\r') }
                "`t" { [void]$sb.Append('\t') }
                default {
                    if ([int]$ch -lt 32) { [void]$sb.AppendFormat('\u{0:x4}', [int]$ch) }
                    else { [void]$sb.Append($ch) }
                }
            }
        }
        [void]$sb.Append('"')
        return $sb.ToString()
    }
    if ($Value -is [byte] -or $Value -is [int16] -or $Value -is [uint16] -or $Value -is [int] -or $Value -is [uint32] -or $Value -is [long] -or $Value -is [uint64] -or $Value -is [double] -or $Value -is [decimal] -or $Value -is [float]) {
        return [System.Convert]::ToString($Value, [System.Globalization.CultureInfo]::InvariantCulture)
    }
    if ($Value -is [datetime]) {
        return (ConvertTo-ExfinJsonText -Value $Value.ToUniversalTime().ToString('o'))
    }
    if ($Value -is [System.Collections.IDictionary]) {
        $parts = New-Object System.Collections.Generic.List[string]
        foreach ($k in @($Value.Keys)) {
            $keyJson = ConvertTo-ExfinJsonText -Value ([string]$k)
            $valJson = ConvertTo-ExfinJsonText -Value $Value[$k]
            [void]$parts.Add(($keyJson + ':' + $valJson))
        }
        return ('{' + ($parts -join ',') + '}')
    }
    if ($Value -is [pscustomobject]) {
        $ht = New-Object System.Collections.Specialized.OrderedDictionary
        foreach ($p in $Value.PSObject.Properties) {
            if ($ht.Contains($p.Name)) { $ht[$p.Name] = $p.Value } else { [void]$ht.Add($p.Name, $p.Value) }
        }
        return (ConvertTo-ExfinJsonText -Value $ht)
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        $parts = New-Object System.Collections.Generic.List[string]
        foreach ($item in $Value) {
            [void]$parts.Add((ConvertTo-ExfinJsonText -Value $item))
        }
        return ('[' + ($parts -join ',') + ']')
    }
    return (ConvertTo-ExfinJsonText -Value ([string]$Value))
}

function Read-ExfinJsonFile {
    param([string]$Path, $Default)
    if (-not (Test-Path -LiteralPath $Path)) { return $Default }
    try { return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $Default }
}

function Write-ExfinJsonFile {
    param([string]$Path, $Object)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($Path, (ConvertTo-ExfinJsonText -Value $Object), $utf8)
}

function Test-ExfinSafeLocalPath {
    param([string]$FilePath)
    $p = [string]$FilePath
    if ([string]::IsNullOrWhiteSpace($p)) { return $false }
    $p = $p.Trim().Trim('"')
    if ($p -match '\.\.') { return $false }
    if ($p -notmatch '^[A-Za-z]:\\') { return $false }
    return $true
}

function Get-ExfinTextExtensions {
    return @('.txt','.log','.csv','.json','.xml','.ini','.rdp','.ps1','.md','.cfg','.conf','.bat','.cmd','.html','.css','.js','.yml','.yaml')
}

function Test-ExfinPreviewable {
    param([string]$Extension)
    $e = ([string]$Extension).ToLowerInvariant()
    if (-not $e.StartsWith('.')) { $e = '.' + $e }
    return ((Get-ExfinTextExtensions) -contains $e)
}

function Get-ExfinFilePreview {
    param([string]$FilePath)
    if (-not (Test-ExfinSafeLocalPath -FilePath $FilePath)) { throw 'invalid_path' }
    if (-not (Test-Path -LiteralPath $FilePath)) { throw 'not_found' }
    $item = Get-Item -LiteralPath $FilePath -ErrorAction Stop
    if ($item.PSIsContainer) { throw 'not_a_file' }
    $ext = $item.Extension.ToLowerInvariant()
    if (-not (Test-ExfinPreviewable -Extension $ext)) { throw 'not_text' }
    if ($item.Length -gt 262144) { throw 'too_large' }
    $text = [System.IO.File]::ReadAllText($item.FullName)
    $o = New-Object System.Collections.Specialized.OrderedDictionary
    $o.Add('path', [string]$item.FullName)
    $o.Add('name', [string]$item.Name)
    $o.Add('size', [int64]$item.Length)
    $o.Add('extension', $ext)
    $o.Add('content', [string]$text)
    return $o
}

function Get-ExfinIconPngBase64 {
    param([string]$FilePath)
    if (-not (Test-ExfinSafeLocalPath -FilePath $FilePath)) { return '' }
    if (-not (Test-Path -LiteralPath $FilePath)) { return '' }
    try {
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($FilePath)
        if (-not $icon) { return '' }
        $bmp = $icon.ToBitmap()
        $ms = New-Object System.IO.MemoryStream
        $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        $b64 = [Convert]::ToBase64String($ms.ToArray())
        $ms.Dispose(); $bmp.Dispose(); $icon.Dispose()
        return $b64
    } catch { return '' }
}

function Set-TsRemoteAppIcon {
    param([string]$Alias, [string]$IconPath)
    $safe = ConvertTo-RemoteAppAlias -Name $Alias
    $key = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Terminal Server\TSAppAllowList\Applications\$safe"
    if (-not (Test-Path -LiteralPath $key)) { throw 'app_not_found' }
    if (-not (Test-ExfinSafeLocalPath -FilePath $IconPath)) { throw 'invalid_path' }
    if (-not (Test-Path -LiteralPath $IconPath)) { throw 'icon_not_found' }
    $full = (Get-Item -LiteralPath $IconPath).FullName
    Set-ItemProperty -LiteralPath $key -Name 'IconPath' -Value $full -Type String -Force
    Set-ItemProperty -LiteralPath $key -Name 'IconIndex' -Value 0 -Type DWord -Force
    $o = New-Object System.Collections.Specialized.OrderedDictionary
    $o.Add('alias', $safe)
    $o.Add('iconPath', $full)
    $o.Add('updated', $true)
    return $o
}

function Get-ExfinAppIconPayload {
    param([string]$Alias, [string]$FilePath)
    $src = [string]$FilePath
    if ([string]::IsNullOrWhiteSpace($src) -and $Alias -and (Get-Command Get-LocalRemoteAppEntries -ErrorAction SilentlyContinue)) {
        foreach ($app in @(Get-LocalRemoteAppEntries)) {
            $a = [string](Get-ExfinJsonProp $app 'alias')
            if ($a -eq $Alias) {
                $src = [string](Get-ExfinJsonProp $app 'iconPath')
                if ([string]::IsNullOrWhiteSpace($src)) { $src = [string](Get-ExfinJsonProp $app 'path') }
                break
            }
        }
    }
    $png = Get-ExfinIconPngBase64 -FilePath $src
    $o = New-Object System.Collections.Specialized.OrderedDictionary
    $o.Add('alias', [string]$Alias)
    $o.Add('path', [string]$src)
    $o.Add('png', [string]$png)
    return $o
}

function Get-ExfinTotpIssuer { return 'EXFIN RemoteAPP' }

function Get-ExfinTotpAccount {
    $n = [string]$env:COMPUTERNAME
    if ([string]::IsNullOrWhiteSpace($n)) { $n = 'HOST' }
    return $n
}

function New-ExfinOtpAuthUri {
    param([string]$Secret, [string]$Account)
    $issuer = Get-ExfinTotpIssuer
    $hostName = $Account
    if ([string]::IsNullOrWhiteSpace($hostName)) { $hostName = Get-ExfinTotpAccount }
    $issuerQ = [Uri]::EscapeDataString($issuer)
    return ('otpauth://totp/{0}:{1}?secret={2}&issuer={3}&period=30&digits=6' -f $issuer, $hostName, $Secret, $issuerQ)
}

function Get-ExfinTotpState {
    $obj = Read-ExfinJsonFile -Path (Get-ExfinTotpPath) -Default $null
    $o = New-Object System.Collections.Specialized.OrderedDictionary
    $o.Add('enabled', [bool](Get-ExfinJsonProp $obj 'enabled' $false))
    $o.Add('enrolled', [bool](Get-ExfinJsonProp $obj 'enrolled' $false))
    $o.Add('issuer', (Get-ExfinTotpIssuer))
    $o.Add('account', (Get-ExfinTotpAccount))
    return $o
}

function New-ExfinTotpEnrollment {
    $secret = [ExfinTotp]::NewSecret()
    $issuer = Get-ExfinTotpIssuer
    $account = Get-ExfinTotpAccount
    $uri = New-ExfinOtpAuthUri -Secret $secret -Account $account
    $prev = Read-ExfinJsonFile -Path (Get-ExfinTotpPath) -Default $null
    Write-ExfinJsonFile -Path (Get-ExfinTotpPath) -Object @{
        enabled       = $false
        enrolled      = [bool](Get-ExfinJsonProp $prev 'enrolled' $false)
        secret        = $secret
        pendingSecret = $secret
        issuer        = $issuer
        pending       = $true
        account       = $account
    }
    $o = New-Object System.Collections.Specialized.OrderedDictionary
    $o.Add('secret', $secret)
    $o.Add('otpauth', $uri)
    $o.Add('issuer', $issuer)
    $o.Add('account', $account)
    $o.Add('hint', 'Google Authenticator ile QR tarayin veya anahtari elle girin, sonra 6 haneli kodu onaylayin.')
    return $o
}

function Confirm-ExfinTotpEnrollment {
    param([string]$Code)
    $obj = Read-ExfinJsonFile -Path (Get-ExfinTotpPath) -Default $null
    $secret = [string](Get-ExfinJsonProp $obj 'pendingSecret')
    if ([string]::IsNullOrWhiteSpace($secret)) { $secret = [string](Get-ExfinJsonProp $obj 'secret') }
    if ([string]::IsNullOrWhiteSpace($secret)) { throw 'not_started' }
    if (-not [ExfinTotp]::Verify($secret, $Code, 1)) { throw 'invalid_code' }
    $issuer = Get-ExfinTotpIssuer
    $account = Get-ExfinTotpAccount
    Write-ExfinJsonFile -Path (Get-ExfinTotpPath) -Object @{
        enabled       = $true
        enrolled      = $true
        secret        = $secret
        pendingSecret = ''
        issuer        = $issuer
        pending       = $false
        account       = $account
    }
    return (Get-ExfinTotpState)
}

function Test-ExfinTotpCode {
    param([string]$Code)
    $obj = Read-ExfinJsonFile -Path (Get-ExfinTotpPath) -Default $null
    if (-not $obj -or -not [bool](Get-ExfinJsonProp $obj 'enabled' $false)) { return $true }
    return [bool][ExfinTotp]::Verify([string](Get-ExfinJsonProp $obj 'secret'), $Code, 1)
}

function Test-ExfinTotpVerify {
    param([string]$Code)
    $obj = Read-ExfinJsonFile -Path (Get-ExfinTotpPath) -Default $null
    $secret = [string](Get-ExfinJsonProp $obj 'secret')
    if (-not [bool](Get-ExfinJsonProp $obj 'enabled' $false) -or [string]::IsNullOrWhiteSpace($secret)) { return $false }
    return [bool][ExfinTotp]::Verify($secret, $Code, 1)
}

function Disable-ExfinTotp {
    Write-ExfinJsonFile -Path (Get-ExfinTotpPath) -Object @{
        enabled       = $false
        enrolled      = $false
        secret        = ''
        pendingSecret = ''
        issuer        = (Get-ExfinTotpIssuer)
        pending       = $false
        account       = (Get-ExfinTotpAccount)
    }
    return (Get-ExfinTotpState)
}

function ConvertTo-ExfinClientRecord {
    param($Source)
    if ($null -eq $Source) { return $null }
    $apps = @()
    $rawApps = Get-ExfinJsonProp $Source 'apps'
    if ($null -ne $rawApps) {
        foreach ($a in @($rawApps)) {
            if ($null -eq $a) { continue }
            if ($a -is [string]) { $apps += $a; continue }
            $apps += @{
                id    = [string](Get-ExfinJsonProp $a 'id')
                name  = [string](Get-ExfinJsonProp $a 'name')
                alias = [string](Get-ExfinJsonProp $a 'alias')
            }
        }
    }
    $status = [string](Get-ExfinJsonProp $Source 'status' 'pending')
    if ([string]::IsNullOrWhiteSpace($status)) { $status = 'pending' }
    return @{
        id           = [string](Get-ExfinJsonProp $Source 'id')
        machineId    = [string](Get-ExfinJsonProp $Source 'machineId')
        hostname     = [string](Get-ExfinJsonProp $Source 'hostname')
        username     = [string](Get-ExfinJsonProp $Source 'username')
        apps         = $apps
        status       = $status
        registeredAt = [string](Get-ExfinJsonProp $Source 'registeredAt')
        approvedAt   = [string](Get-ExfinJsonProp $Source 'approvedAt')
    }
}

function Get-ExfinClientsState {
    $obj = Read-ExfinJsonFile -Path (Get-ExfinClientsPath) -Default $null
    $list = New-Object System.Collections.ArrayList
    foreach ($c in @((Get-ExfinJsonProp $obj 'clients' @()))) {
        $rec = ConvertTo-ExfinClientRecord -Source $c
        if ($null -eq $rec) { continue }
        [void]$list.Add($rec)
    }
    return @{
        requireApproval = [bool](Get-ExfinJsonProp $obj 'requireApproval' $false)
        clients         = @($list.ToArray())
    }
}

function Save-ExfinClientsState {
    param($State)
    $clients = New-Object System.Collections.ArrayList
    foreach ($c in @((Get-ExfinJsonProp $State 'clients' @()))) {
        $rec = ConvertTo-ExfinClientRecord -Source $c
        if ($null -eq $rec) { continue }
        [void]$clients.Add($rec)
    }
    Write-ExfinJsonFile -Path (Get-ExfinClientsPath) -Object @{
        requireApproval = [bool](Get-ExfinJsonProp $State 'requireApproval' $false)
        clients         = @($clients.ToArray())
    }
}

function Register-ExfinClientRecord {
    param([string]$JsonText)
    $state = Get-ExfinClientsState
    $obj = $JsonText | ConvertFrom-Json
    $machineId = [string](Get-ExfinJsonProp $obj 'machineId')
    if ([string]::IsNullOrWhiteSpace($machineId)) { $machineId = [guid]::NewGuid().ToString('N') }
    $username = [string](Get-ExfinJsonProp $obj 'username')
    $id = ($machineId + '|' + $username).ToLowerInvariant()
    $found = $false
    $next = New-Object System.Collections.ArrayList
    foreach ($c in @($state.clients)) {
        $cid = [string](Get-ExfinJsonProp $c 'id')
        if ($cid -eq $id) {
            $found = $true
            $status = [string](Get-ExfinJsonProp $c 'status' 'pending')
            if ([string]::IsNullOrWhiteSpace($status)) { $status = 'pending' }
            [void]$next.Add(@{
                id           = $id
                machineId    = $machineId
                hostname     = $(if (Get-ExfinJsonProp $obj 'hostname') { [string](Get-ExfinJsonProp $obj 'hostname') } else { [string](Get-ExfinJsonProp $c 'hostname') })
                username     = $(if ($username) { $username } else { [string](Get-ExfinJsonProp $c 'username') })
                apps         = (Get-ExfinJsonProp $obj 'apps')
                status       = $status
                registeredAt = [string](Get-ExfinJsonProp $c 'registeredAt')
                approvedAt   = [string](Get-ExfinJsonProp $c 'approvedAt')
            })
        } else {
            [void]$next.Add($c)
        }
    }
    if (-not $found) {
        [void]$next.Add(@{
            id           = $id
            machineId    = $machineId
            hostname     = [string](Get-ExfinJsonProp $obj 'hostname')
            username     = $username
            apps         = (Get-ExfinJsonProp $obj 'apps')
            status       = 'pending'
            registeredAt = (Get-Date).ToUniversalTime().ToString('o')
            approvedAt   = ''
        })
    }
    $state.clients = @($next.ToArray())
    Save-ExfinClientsState -State $state
    return (Get-ExfinClientsState)
}

function Set-ExfinClientAccess {
    param([string]$JsonText)
    $state = Get-ExfinClientsState
    $obj = $JsonText | ConvertFrom-Json
    if ($null -ne (Get-ExfinJsonProp $obj 'requireApproval')) {
        $state.requireApproval = [bool](Get-ExfinJsonProp $obj 'requireApproval')
    }
    $id = [string](Get-ExfinJsonProp $obj 'id')
    $action = [string](Get-ExfinJsonProp $obj 'action')
    if ($id -and $action) {
        $next = New-Object System.Collections.ArrayList
        foreach ($c in @($state.clients)) {
            $cid = [string](Get-ExfinJsonProp $c 'id')
            if ($cid -eq $id) {
                $st = $action.ToLowerInvariant()
                if ($st -eq 'allow' -or $st -eq 'approve') { $st = 'approved' }
                if ($st -eq 'deny' -or $st -eq 'block') { $st = 'denied' }
                $c['status'] = $st
                if ($st -eq 'approved') { $c['approvedAt'] = (Get-Date).ToUniversalTime().ToString('o') }
            }
            [void]$next.Add($c)
        }
        $state.clients = @($next.ToArray())
    }
    Save-ExfinClientsState -State $state
    return (Get-ExfinClientsState)
}

function Test-ExfinClientMayDownload {
    param([string]$ClientId)
    $state = Get-ExfinClientsState
    if (-not [bool]$state.requireApproval) { return $true }
    if ([string]::IsNullOrWhiteSpace($ClientId)) { return $false }
    $want = $ClientId.Trim()
    foreach ($c in @($state.clients)) {
        $status = [string](Get-ExfinJsonProp $c 'status')
        if ($status -ne 'approved') { continue }
        $cid = [string](Get-ExfinJsonProp $c 'id')
        $mid = [string](Get-ExfinJsonProp $c 'machineId')
        if ([string]::Equals($cid, $want, [StringComparison]::OrdinalIgnoreCase)) { return $true }
        if (-not [string]::IsNullOrWhiteSpace($mid) -and [string]::Equals($mid, $want, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Invoke-ExfinAccessRequest {
    param($Request, [string]$Method, [string]$PathNorm, $Query)
    $low = $PathNorm.ToLowerInvariant()
    $raw = ''
    if ($Request -and $Request.PSObject.Properties['Body']) { $raw = [string]$Request.Body }
    switch ($low) {
        '/api/file' {
            $fp = ''
            if ($Query -is [System.Collections.IDictionary] -and $Query['path']) { $fp = [string]$Query['path'] }
            try { return New-ProbeApiHttpResponse -Body (Get-ExfinFilePreview -FilePath $fp) }
            catch { return New-ProbeApiHttpResponse -Status 400 -Body @{ error = [string]$_.Exception.Message } }
        }
        '/api/icon' {
            $alias = ''
            $fp = ''
            if ($Query -is [System.Collections.IDictionary]) {
                if ($Query['alias']) { $alias = [string]$Query['alias'] }
                if ($Query['path']) { $fp = [string]$Query['path'] }
            }
            return New-ProbeApiHttpResponse -Body (Get-ExfinAppIconPayload -Alias $alias -FilePath $fp)
        }
        '/api/totp' {
            if ($Method -eq 'GET') { return New-ProbeApiHttpResponse -Body (Get-ExfinTotpState) }
            try {
                if ([string]::IsNullOrWhiteSpace($raw)) { return New-ProbeApiHttpResponse -Status 400 -Body @{ error = 'missing_body' } }
                $obj = $raw | ConvertFrom-Json
                $action = ([string](Get-ExfinJsonProp $obj 'action')).ToLowerInvariant()
                if ($action -eq 'enroll') { return New-ProbeApiHttpResponse -Body (New-ExfinTotpEnrollment) }
                if ($action -eq 'confirm') {
                    return New-ProbeApiHttpResponse -Body (Confirm-ExfinTotpEnrollment -Code ([string](Get-ExfinJsonProp $obj 'code')))
                }
                if ($action -eq 'verify') {
                    $ok = Test-ExfinTotpVerify -Code ([string](Get-ExfinJsonProp $obj 'code'))
                    if (-not $ok) { return New-ProbeApiHttpResponse -Status 401 -Body @{ error = 'invalid_code' } }
                    return New-ProbeApiHttpResponse -Body @{ ok = $true }
                }
                if ($action -eq 'disable') {
                    return New-ProbeApiHttpResponse -Body (Disable-ExfinTotp)
                }
                return New-ProbeApiHttpResponse -Status 400 -Body @{ error = 'unknown_action' }
            } catch {
                $msg = [string]$_.Exception.Message
                $st = 400
                if ($msg -eq 'invalid_code') { $st = 401 }
                return New-ProbeApiHttpResponse -Status $st -Body @{ error = $msg }
            }
        }
        '/api/clients' {
            if ($Method -eq 'GET') { return New-ProbeApiHttpResponse -Body (Get-ExfinClientsState) }
            try {
                if ([string]::IsNullOrWhiteSpace($raw)) { return New-ProbeApiHttpResponse -Status 400 -Body @{ error = 'missing_body' } }
                $obj = $raw | ConvertFrom-Json
                $action = [string](Get-ExfinJsonProp $obj 'action')
                $hasId = -not [string]::IsNullOrWhiteSpace([string](Get-ExfinJsonProp $obj 'id'))
                if ($hasId -and ($action -eq 'approve' -or $action -eq 'allow' -or $action -eq 'deny' -or $action -eq 'block')) {
                    return New-ProbeApiHttpResponse -Body (Set-ExfinClientAccess -JsonText $raw)
                }
                if ($null -ne $obj.PSObject.Properties['requireApproval'] -and [string]::IsNullOrWhiteSpace([string](Get-ExfinJsonProp $obj 'machineId'))) {
                    return New-ProbeApiHttpResponse -Body (Set-ExfinClientAccess -JsonText $raw)
                }
                return New-ProbeApiHttpResponse -Body (Register-ExfinClientRecord -JsonText $raw)
            } catch {
                return New-ProbeApiHttpResponse -Status 400 -Body @{ error = [string]$_.Exception.Message }
            }
        }
        default { return $null }
    }
}
