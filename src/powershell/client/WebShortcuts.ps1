#requires -Version 5.1
<#
.SYNOPSIS
    WebShortcuts.ps1 — Rdp Virtual Box App client-side HTML5 kisayol ureticisi.

.DESCRIPTION
    RD Web Access veya Apache Guacamole endpointleri icin Windows Internet Shortcut
    (.url) dosyasi, opsiyonel PWA manifesti, service worker ve landing page uretir.
    Uretim sablon motoru uzerinden yapilir; endpoint tipine gore URL formatlama
    Set-RdpUrlFormat fonksiyonu ile yonetilir.

.NOTES
    Encoding : UTF-8 (BOM'suz)
    Author   : Rdp Virtual Box App - Ajan C2
    Version  : 1.0.0
#>

Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# JSON sablonu yukler. %PLACEHOLDER% bazli.
# ---------------------------------------------------------------------------
function Get-PwaTemplate {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [string]$TemplateRoot
    )

    $path = Get-WebTemplatePath -TemplateRoot $TemplateRoot
    Write-Verbose ("PWA sablonu okunuyor: {0}" -f $path)
    $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    $json = $raw | ConvertFrom-Json -AsHashtable
    return $json
}

# ---------------------------------------------------------------------------
# web.template.json dosyasinin tam yolunu cozer.
# ---------------------------------------------------------------------------
function Get-WebTemplatePath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$TemplateRoot
    )

    if ([string]::IsNullOrWhiteSpace($TemplateRoot)) {
        $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
        $candidates = @(
            (Join-Path $scriptDir '..\..\config\client\web.template.json'),
            (Join-Path $scriptDir '..\config\client\web.template.json'),
            (Join-Path $PSScriptRoot '..\config\client\web.template.json')
        )
        foreach ($c in $candidates) {
            $resolved = [System.IO.Path]::GetFullPath((Join-Path $scriptDir $c))
            if (Test-Path -LiteralPath $resolved) { return $resolved }
        }
        throw 'web.template.json bulunamadi. -TemplateRoot ile manuel yol verin.'
    }
    return (Join-Path $TemplateRoot 'web.template.json')
}

# ---------------------------------------------------------------------------
# Endpoint tipine gore URL uretir. Guacamole icin connectionId opsiyonel.
# ---------------------------------------------------------------------------
function Format-WebUrl {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('RDWeb', 'Guacamole')]
        [string]$EndpointType,

        [Parameter(Mandatory)]
        [string]$Server,

        [int]$Port = 0,

        [string]$WebPath,

        [string]$ConnectionId
    )

    switch ($EndpointType) {
        'RDWeb' {
            $usePort = if ($Port -gt 0) { $Port } else { 443 }
            $path = if ([string]::IsNullOrWhiteSpace($WebPath)) { '/RDWeb/webclient' } else { $WebPath }
            $url = 'https://{0}:{1}{2}/index.html' -f $Server, $usePort, $path
            return $url
        }
        'Guacamole' {
            $usePort = if ($Port -gt 0) { $Port } else { 8443 }
            $path = if ([string]::IsNullOrWhiteSpace($WebPath)) { '/guacamole' } else { $WebPath }
            if (-not [string]::IsNullOrWhiteSpace($ConnectionId)) {
                return 'https://{0}:{1}{2}/#/client/{3}' -f $Server, $usePort, $path, $ConnectionId
            }
            return 'https://{0}:{1}{2}/' -f $Server, $usePort, $path
        }
        default {
            throw "Bilinmeyen endpoint tipi: $EndpointType"
        }
    }
}

# ---------------------------------------------------------------------------
# Windows Internet Shortcut (.url) dosyasi uretir.
# ---------------------------------------------------------------------------
function New-WebShortcut {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('RDWeb', 'Guacamole')]
        [string]$EndpointType,

        [Parameter(Mandatory)]
        [string]$Server,

        [int]$Port = 0,

        [string]$WebPath,

        [Parameter(Mandatory)]
        [string]$AppName,

        [string]$AppId,

        [string]$ConnectionId,

        [string]$IconPath,

        [string]$OutputPath = (Join-Path $env:USERPROFILE 'Documents\RdpVirtualBoxApp\web')
    )

    try {
        if (-not (Test-Path -LiteralPath $OutputPath)) {
            New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
        }

        $url = Format-WebUrl -EndpointType $EndpointType -Server $Server -Port $Port -WebPath $WebPath -ConnectionId $ConnectionId
        $safeName = ($AppName -replace '[\\/:*?"<>|]', '_')
        $filePath = Join-Path $OutputPath ('{0}.url' -f $safeName)

        $lines = New-Object System.Collections.Generic.List[string]
        $lines.Add('[InternetShortcut]')
        $lines.Add(('URL={0}' -f $url))
        if (-not [string]::IsNullOrWhiteSpace($IconPath)) {
            $lines.Add(('IconFile={0}' -f $IconPath))
            $lines.Add('IconIndex=0')
        }
        $lines.Add(('Comment=Rdp Virtual Box App - {0}' -f $AppName))

        $content = ($lines -join [Environment]::NewLine)
        Set-Content -LiteralPath $filePath -Value $content -Encoding UTF8
        Write-Verbose ("Web kisayolu uretildi: {0}" -f $filePath)
        return $filePath
    }
    catch {
        Write-Error -ErrorRecord $_ -ErrorAction Stop
    }
}

# ---------------------------------------------------------------------------
# PWA manifesti uretir. (Binary iconlar opsiyonel.)
# ---------------------------------------------------------------------------
function New-PwaManifest {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$AppName,

        [string]$ShortName,

        [string]$AppId,

        [Parameter(Mandatory)]
        [ValidateSet('RDWeb', 'Guacamole')]
        [string]$EndpointType,

        [Parameter(Mandatory)]
        [string]$Server,

        [int]$Port = 0,

        [string]$WebPath,

        [string[]]$IconPaths,

        [string]$TemplateRoot,

        [string]$OutputPath = (Join-Path $env:USERPROFILE 'Documents\RdpVirtualBoxApp\web')
    )

    try {
        if (-not (Test-Path -LiteralPath $OutputPath)) {
            New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
        }

        $startUrl = Format-WebUrl -EndpointType $EndpointType -Server $Server -Port $Port -WebPath $WebPath
        $usePort = if ($Port -gt 0) { $Port } else { if ($EndpointType -eq 'RDWeb') { 443 } else { 8443 } }
        $scope = 'https://{0}:{1}' -f $Server, $usePort

        $short = if ([string]::IsNullOrWhiteSpace($ShortName)) {
            ($AppName -replace '\s+', '').Substring(0, [Math]::Min(12, $AppName.Length))
        } else { $ShortName }

        $template = Get-PwaTemplate -TemplateRoot $TemplateRoot
        $template.name        = $AppName
        $template.short_name  = $short
        $template.start_url   = $startUrl
        $template.scope       = $scope

        if ($template.ContainsKey('theme_color')) { $template.theme_color = '#0078d4' }
        if ($template.ContainsKey('background_color')) { $template.background_color = '#ffffff' }

        if ($null -eq $template.icons) { $template.icons = @() }
        if ($IconPaths -and $IconPaths.Count -gt 0) {
            $icons = New-Object System.Collections.Generic.List[object]
            foreach ($ip in $IconPaths) {
                $ext = [System.IO.Path]::GetExtension($ip).TrimStart('.').ToLowerInvariant()
                if ([string]::IsNullOrEmpty($ext)) { $ext = 'png' }
                $fileName = [System.IO.Path]::GetFileName($ip)
                $icons.Add([ordered]@{
                    src   = $fileName
                    sizes = '192x192'
                    type  = ('image/{0}' -f $ext)
                    purpose = 'any maskable'
                })
            }
            $template.icons = $icons
        }
        elseif ($template.icons.Count -eq 0) {
            $template.icons = @(
                [ordered]@{ src = 'icon-192.png'; sizes = '192x192'; type = 'image/png'; purpose = 'any maskable' },
                [ordered]@{ src = 'icon-512.png'; sizes = '512x512'; type = 'image/png'; purpose = 'any maskable' }
            )
        }

        $manifestPath = Join-Path $OutputPath 'manifest.json'
        $json = $template | ConvertTo-Json -Depth 10
        Set-Content -LiteralPath $manifestPath -Value $json -Encoding UTF8
        Write-Verbose ("PWA manifest uretildi: {0}" -f $manifestPath)
        return $manifestPath
    }
    catch {
        Write-Error -ErrorRecord $_ -ErrorAction Stop
    }
}

# ---------------------------------------------------------------------------
# Service Worker (cache-first stratejisi). Opsiyonel.
# ---------------------------------------------------------------------------
function New-ServiceWorker {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$OutputPath = (Join-Path $env:USERPROFILE 'Documents\RdpVirtualBoxApp\web'),

        [string]$CacheName = 'rdp-virtual-box-app-v1'
    )

    if (-not (Test-Path -LiteralPath $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }

    $sw = @"
/**
 * Rdp Virtual Box App - Service Worker
 * Cache-first stratejisi ile temel assetlerin offline kalmasi icin.
 */
const CACHE_NAME = '$CacheName';
const CORE_ASSETS = [
    './',
    './manifest.json',
    './icon-192.png',
    './icon-512.png'
];

self.addEventListener('install', (event) => {
    event.waitUntil(
        caches.open(CACHE_NAME).then((cache) => cache.addAll(CORE_ASSETS))
    );
    self.skipWaiting();
});

self.addEventListener('activate', (event) => {
    event.waitUntil(
        caches.keys().then((keys) => Promise.all(
            keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k))
        ))
    );
    self.clients.claim();
});

self.addEventListener('fetch', (event) => {
    if (event.request.method !== 'GET') { return; }
    event.respondWith(
        caches.match(event.request).then((cached) => {
            return cached || fetch(event.request).then((response) => {
                const copy = response.clone();
                caches.open(CACHE_NAME).then((c) => c.put(event.request, copy));
                return response;
            });
        })
    );
});
"@

    $swPath = Join-Path $OutputPath 'sw.js'
    Set-Content -LiteralPath $swPath -Value $sw -Encoding UTF8
    Write-Verbose ("Service worker uretildi: {0}" -f $swPath)
    return $swPath
}

# ---------------------------------------------------------------------------
# Minimal landing page. PWA yuklemesi icin install prompt'u icerir.
# ---------------------------------------------------------------------------
function New-IndexPage {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$AppName,

        [Parameter(Mandatory)]
        [string]$StartUrl,

        [string]$OutputPath = (Join-Path $env:USERPROFILE 'Documents\RdpVirtualBoxApp\web')
    )

    if (-not (Test-Path -LiteralPath $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }

    $html = @"
<!DOCTYPE html>
<html lang="tr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="theme-color" content="#0078d4">
    <title>$AppName - Rdp Virtual Box App</title>
    <link rel="manifest" href="manifest.json">
    <link rel="icon" href="icon-192.png" type="image/png">
    <style>
        body { font-family: 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; margin: 0; background: #f3f3f3; display: flex; min-height: 100vh; align-items: center; justify-content: center; }
        .card { background: #fff; padding: 32px 40px; border-radius: 12px; box-shadow: 0 8px 32px rgba(0,0,0,0.08); max-width: 480px; text-align: center; }
        h1 { color: #0078d4; margin: 0 0 8px; font-size: 22px; }
        p { color: #444; line-height: 1.5; margin: 0 0 24px; }
        a.btn { background: #0078d4; color: #fff; padding: 10px 20px; border-radius: 6px; text-decoration: none; font-weight: 600; }
        a.btn:hover { background: #005fa3; }
    </style>
</head>
<body>
    <div class="card">
        <h1>$AppName</h1>
        <p>Bu sayfa Rdp Virtual Box App tarafindan olusturuldu. Asagidaki dugmeyle uygulamayi acabilir veya PWA olarak kurabilirsiniz.</p>
        <a class="btn" href="$StartUrl" target="_blank" rel="noopener">Uygulamayi Ac</a>
    </div>
    <script>
        if ('serviceWorker' in navigator) {
            window.addEventListener('load', () => {
                navigator.serviceWorker.register('sw.js').catch(() => {});
            });
        }
    </script>
</body>
</html>
"@

    $indexPath = Join-Path $OutputPath 'index.html'
    Set-Content -LiteralPath $indexPath -Value $html -Encoding UTF8
    Write-Verbose ("Landing page uretildi: {0}" -f $indexPath)
    return $indexPath
}

# ---------------------------------------------------------------------------
# Tek seferde tum web artifactlarini uretir.
# ---------------------------------------------------------------------------
function New-WebShortcutBundle {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('RDWeb', 'Guacamole')]
        [string]$EndpointType,

        [Parameter(Mandatory)]
        [string]$Server,

        [int]$Port = 0,

        [string]$WebPath,

        [Parameter(Mandatory)]
        [string]$AppName,

        [string]$AppId,

        [string]$ConnectionId,

        [switch]$CreatePwa,

        [string]$TemplateRoot,

        [string]$OutputPath = (Join-Path $env:USERPROFILE 'Documents\RdpVirtualBoxApp\web')
    )

    $result = [ordered]@{
        Shortcut = $null
        Manifest = $null
        ServiceWorker = $null
        IndexPage = $null
    }

    $result.Shortcut = New-WebShortcut -EndpointType $EndpointType -Server $Server -Port $Port -WebPath $WebPath -AppName $AppName -AppId $AppId -ConnectionId $ConnectionId -OutputPath $OutputPath

    if ($CreatePwa) {
        $startUrl = Format-WebUrl -EndpointType $EndpointType -Server $Server -Port $Port -WebPath $WebPath
        $result.Manifest = New-PwaManifest -AppName $AppName -ShortName $AppId -AppId $AppId -EndpointType $EndpointType -Server $Server -Port $Port -WebPath $WebPath -TemplateRoot $TemplateRoot -OutputPath $OutputPath
        $result.ServiceWorker = New-ServiceWorker -OutputPath $OutputPath
        $result.IndexPage = New-IndexPage -AppName $AppName -StartUrl $startUrl -OutputPath $OutputPath
    }

    return $result
}

# ---------------------------------------------------------------------------
# Modulun disariya acilan isimleri.
# ---------------------------------------------------------------------------
Export-ModuleMember -Function `
    'New-WebShortcut',
    'New-PwaManifest',
    'New-ServiceWorker',
    'New-IndexPage',
    'New-WebShortcutBundle',
    'Format-WebUrl',
    'Get-PwaTemplate',
    'Get-WebTemplatePath'
