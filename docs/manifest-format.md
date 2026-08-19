# Server Manifest Formatı

Bu belge, **Rdp Virtual Box App** projesinin server-side setup ile client-side
setup arasındaki veri köprüsü olan `server-manifest.json` dosyasının
yapısını, üretim yöntemini ve client tarafından nasıl tüketileceğini
tanımlar.

> Manifest dosyası [src/powershell/server/Generate-Manifest.ps1](../src/powershell/server/Generate-Manifest.ps1)
> tarafından üretilir. Client tarafında [src/powershell/client/SetupUI.ps1](../src/powershell/client/SetupUI.ps1)
> ve `ServerProbe.ps1` tarafından okunur.

---

## İçindekiler

- [Genel Bakış](#genel-bakış)
- [Şema (manifestVersion 1.0.0)](#şema-manifestversion-100)
- [Manifest Üretici](#manifest-üretici)
- [Client'ın Manifesti Okuması](#clientın-manifesti-okuması)
  - [Senaryo A — SMB Share](#senaryo-a--smb-share)
  - [Senaryo B — HTTP(S) İndirme](#senaryo-b--https-indirme)
  - [Senaryo C — WinRM + Local Path](#senaryo-c--winrm--local-path)
- [Build Artifact Doğrulama (SHA256)](#build-artifact-doğrulama-sha256)
- [Geriye Dönük Uyumluluk](#geriye-dönük-uyumluluk)
- [Örnek Manifest](#örnek-manifest)

---

## Genel Bakış

Server-side setup tamamlandıktan sonra, client kurulumlarının hangi
uygulamaları yayınlayacağını, hangi portların açık olduğunu ve RDS
web erişiminin nereye yönlendirildiğini **tekrardan taramasına gerek
kalmadan** bilmesi gerekir. `server-manifest.json` tam olarak bu
amacı taşır:

- **Sunucu kimliği** — FQDN, IP, AD domain, OS.
- **Bağlantı stratejileri** — Direct, Gateway, Guacamole, Tailscale,
  Cloudflare için etkin/devre dışı ve erişim URL'leri.
- **Web endpoint** — RD Web Access veya Apache Guacamole hangisi aktifse.
- **RemoteApps listesi** — `Get-RDRemoteApp` çıktısı.
- **Sertifika bilgisi** — RDP-Tcp'ye bağlı self-signed veya CA sertifika
  thumbprint'i.

Dosya, `%ProgramData%\RdpVirtualBoxApp\Manifest\server-manifest.json`
konumuna yazılır ve UTF-8 (BOM'suz) JSON olarak saklanır.

---

## Şema (manifestVersion 1.0.0)

```json
{
  "manifestVersion": "1.0.0",
  "generatedAt": "2026-08-19T16:00:00Z",
  "server": {
    "fqdn": "server.domain.local",
    "ip": "192.168.0.106",
    "domain": "jber.local",
    "os": "Windows Server 2019 Datacenter"
  },
  "connectionStrategies": {
    "direct":     { "enabled": true,  "port": 3389, "url": "192.168.0.106:3389" },
    "gateway":    { "enabled": false, "port": 443,  "url": null },
    "guacamole":  { "enabled": true,  "port": 8443, "url": "https://server:8443/guacamole" },
    "tailscale":  { "enabled": false, "url": null },
    "cloudflare": { "enabled": false, "url": null }
  },
  "webEndpoint": {
    "type": "Guacamole",
    "url":  "https://server:8443/guacamole"
  },
  "remoteApps": [
    {
      "alias":     "NebimWinner",
      "name":      "Nebim Winner",
      "path":      "C:\\Program Files\\Nebim\\Winner\\winner.exe",
      "publisher": "Nebim",
      "icon":      "C:\\Program Files\\Nebim\\Winner\\winner.exe"
    }
  ],
  "certificate": {
    "thumbprint": "ABC123DEF456...",
    "type":       "SelfSigned"
  }
}
```

### Alan Açıklamaları

| Alan | Tip | Açıklama |
|------|-----|----------|
| `manifestVersion` | string | Semver — `1.0.0` itibariyle bu şema. |
| `generatedAt` | string (ISO 8601 UTC) | Manifest üretim zaman damgası. |
| `server.fqdn` | string? | Sunucunun tam DNS adı. |
| `server.ip` | string? | Sunucunun birincil IPv4 adresi. |
| `server.domain` | string? | Active Directory domain (workgroup ise boş). |
| `server.os` | string? | `Win32_OperatingSystem.Caption` değeri. |
| `connectionStrategies.<name>.enabled` | bool | İlgili strateji kurulmuş ve kullanılabilir mi? |
| `connectionStrategies.<name>.port` | int? | Varsayılan port (Tailscale/Cloudflare için `null`). |
| `connectionStrategies.<name>.url` | string? | Bağlantı URL'i (etkin değilse `null`). |
| `webEndpoint.type` | enum? | `RDWeb`, `Guacamole` veya `null`. |
| `webEndpoint.url` | string? | HTML5 erişim URL'i. |
| `remoteApps[].alias` | string | RemoteApp alias (RDS koleksiyonundaki kısa ad). |
| `remoteApps[].name` | string | Görüntü adı (DisplayName). |
| `remoteApps[].path` | string | Sunucudaki yürütülebilir dosya yolu. |
| `remoteApps[].publisher` | string | Yayıncı bilgisi (kullanıcı karşılama ekranı için). |
| `remoteApps[].icon` | string? | İkon dosyası yolu (yoksa `path` ile aynı). |
| `certificate.thumbprint` | string? | RDP-Tcp'ye bağlı sertifika thumbprint'i. |
| `certificate.type` | enum? | `SelfSigned`, `CA` veya `Unknown`. |

### Bağlantı Stratejisi Karar Tablosu

| Strateji | Default Port | enabled=true Koşulu | URL Kalıbı |
|----------|--------------|---------------------|------------|
| `direct` | 3389 | Sunucu RDP açık | `ip:3389` |
| `gateway` | 443 | `IncludeStrategies` listesinde + RD Gateway kurulu | `https://fqdn:443` |
| `guacamole` | 8443 | `IncludeStrategies` listesinde + Guacamole erişilebilir | `https://fqdn:8443/guacamole` |
| `tailscale` | — | `-TailscaleHostname` parametresi geçildi | `https://<ts-host>:3389` |
| `cloudflare` | — | `-CloudflareHostname` parametresi geçildi | `https://<cf-host>` |

---

## Manifest Üretici

`src/powershell/server/Generate-Manifest.ps1` modülü, manifest'i üretirken
aşağıdaki kaynaklardan yararlanır:

- `Win32_ComputerSystem` / `Win32_OperatingSystem` (CIM) — sunucu kimliği.
- `Get-RDRemoteApp -CollectionName <CollectionName>` (RemoteDesktop
  modülü) — RemoteApps listesi.
- `Win32_TSGeneralSetting` (WMI) — RDP-Tcp'ye bağlı sertifika thumbprint'i.
- `Remote Desktop` X509 store — sertifika fallback kaynağı.
- HTTP HEAD probe (opsiyonel) — RD Web veya Guacamole endpoint tespiti.

### Tipik Kullanım

```powershell
# Varsayılan konuma tam manifest üret (%ProgramData%)
.\Generate-Manifest.ps1 -IncludeApps -IncludeWebEndpoint

# Özel çıktı yolu + özel hostname'ler
.\Generate-Manifest.ps1 `
    -OutputPath 'C:\RdpVirtualBoxApp\manifest\server-manifest.json' `
    -IncludeApps `
    -IncludeWebEndpoint `
    -TailscaleHostname 'server.tail-net.ts.net' `
    -CloudflareHostname 'rdp.example.com'

# Yalnızca strateji bölümünü güncelle (RemoteApps hariç)
.\Generate-Manifest.ps1 -IncludeWebEndpoint
```

### Ortam Değişkenleri

| Değişken | Varsayılan | Açıklama |
|----------|------------|----------|
| `$env:ProgramData` | `C:\ProgramData` | Manifest ve log dizini için kök. |

Üretim sırasında aşağıdaki log dosyası yazılır:

```
%ProgramData%\RdpVirtualBoxApp\Logs\generate-manifest.log
```

---

## Client'ın Manifesti Okuması

Client setup, manifesti aşağıdaki üç yoldan biriyle alır. Hangi yolun
kullanılacağı, server-side setup'taki paylaşım tercihlerine ve ağ
yapısına bağlıdır.

### Senaryo A — SMB Share

Server setup sırasında manifest, **gizli bir SMB share** üzerinden
yayınlanır. Bu en basit yoldur ve homojen Windows ağları için idealdir.

**Server tarafı (ServerSetupUI.ps1 içinde bir kere çalıştırılır):**

```powershell
$sharePath = 'C:\RdpVirtualBoxApp$'
$manifestDir = Join-Path $sharePath 'Manifest'
New-Item -Path $manifestDir -ItemType Directory -Force | Out-Null

# Hidden share oluştur (sonuna $ eklenir)
New-SmbShare -Name 'RdpVirtualBoxApp$' `
    -Path $sharePath `
    -FullAccess 'DOMAIN\Domain Admins' `
    -ReadAccess 'DOMAIN\Domain Users' `
    -Description 'Rdp Virtual Box App artifacts'

# Manifest'i share üzerine kopyala
Copy-Item -Path "$env:ProgramData\RdpVirtualBoxApp\Manifest\server-manifest.json" `
    -Destination "$manifestDir\server-manifest.json" -Force
```

**Client tarafı (SetupUI.ps1 içinde):**

```powershell
$manifestUrl = '\\server\RdpVirtualBoxApp$\Manifest\server-manifest.json'
if (Test-Path -LiteralPath $manifestUrl) {
    $manifest = Get-Content -LiteralPath $manifestUrl -Raw -Encoding UTF8 | ConvertFrom-Json
    Write-Host "Manifest okundu. Sunucu: $($manifest.server.fqdn)"
}
```

> **Avantaj:** Tek dosya, imzasız okuma, ACL ile kontrol.
> **Dezavantaj:** SMB portlarının (445) açık olması gerekir; internet
> üzerinden çalışmaz.

### Senaryo B — HTTP(S) İndirme

Server, manifesti kendi HTTPS endpoint'i üzerinden yayınlar. Apache
Guacamole zaten 8443 portunda çalışıyorsa, **aynı Tomcat altına
bağımsız bir manifest servlet'i** eklenebilir. Alternatif olarak
**RD Web Access** IIS kök dizinine statik bir dosya konabilir.

**Server tarafı (RD Web IIS kök dizinine kopyalama):**

```powershell
$rdWebRoot = 'C:\Windows\Web\RDWeb\Pages'
Copy-Item -Path "$env:ProgramData\RdpVirtualBoxApp\Manifest\server-manifest.json" `
    -Destination "$rdWebRoot\server-manifest.json" -Force
```

**Client tarafı (SetupUI.ps1 içinde):**

```powershell
# RD Web zaten HTTPS üzerinden erişilebilir olduğu için aynı kökü kullan
$manifestUrl = 'https://server/RDWeb/Pages/server-manifest.json'

# veya Guacamole kuruluysa
$manifestUrl = 'https://server:8443/guacamole/server-manifest.json'

# Self-signed sertifika için TLS doğrulamasını gevşet
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }

try {
    $manifest = Invoke-RestMethod -Uri $manifestUrl -Method Get -TimeoutSec 5
    Write-Host "Manifest indirildi. Versiyon: $($manifest.manifestVersion)"
} catch {
    Write-Warning "Manifest indirilemedi: $($_.Exception.Message)"
}
```

> **Avantaj:** Firewall dostu (443/8443), internet üzerinden çalışır,
> cache'lenebilir.
> **Dezavantaj:** Self-signed sertifika uyarısı; IIS veya Tomcat
> konfigürasyonu gerekir.

### Senaryo C — WinRM + Local Path

Client ile server aynı AD domaindeyse ve WinRM erişimi açıksa,
client `Invoke-Command` ile server'a bağlanıp manifesti doğrudan
server diskinden okuyabilir. Bu yol, **client tarafı minimum düzeyde
konfigürasyon gerektirir** çünkü SMB veya IIS kurulumu gerektirmez.

**Client tarafı (SetupUI.ps1 içinde):**

```powershell
$server = '192.168.0.106'
$cred   = Get-Credential -Message 'Sunucu yönetici hesabı'

# Seçenek 1: dosyayı base64 stream olarak al
$remoteManifest = Invoke-Command -ComputerName $server -Credential $cred `
    -ScriptBlock {
        Get-Content -LiteralPath "$env:ProgramData\RdpVirtualBoxApp\Manifest\server-manifest.json" `
            -Raw -Encoding UTF8
    } -ErrorAction Stop

$manifest = $remoteManifest | ConvertFrom-Json

# Seçenek 2: doğrudan UNC path üzerinden erişim için map edilmiş drive
# New-PSDrive -Name 'RDPV' -PSProvider FileSystem -Root "\\$server\C$\ProgramData\RdpVirtualBoxApp\Manifest" -Credential $cred
# $manifest = Get-Content -LiteralPath 'RDPV:\server-manifest.json' -Raw -Encoding UTF8 | ConvertFrom-Json
```

> **Avantaj:** WinRM zaten ServerProbe için kullanılıyor; ek konfig yok.
> **Dezavantaj:** Yönetici hesabı gerekir; her bağlantıda kimlik bilgisi
> sorulabilir.

### Hangi Senaryo Tercih Edilmeli?

| Senaryo | Aynı LAN | VPN/Mesh üzerinden | İnternet üzerinden |
|---------|----------|--------------------|--------------------|
| **SMB** | İdeal | Koşullu (445 açık) | Kullanılmaz |
| **HTTP(S)** | KBV gereksiz | İdeal (443/8443) | İdeal (Cloudflare/Tailscale) |
| **WinRM** | İdeal | Yavaş ama çalışır | Kullanılmaz (5985/5986) |

---

## Build Artifact Doğrulama (SHA256)

Build süreci sonunda `SHA256SUMS.txt` üretilir. Bu dosya
[src/powershell/SHA256-Verify.ps1](../src/powershell/SHA256-Verify.ps1)
ile hem üretilir hem doğrulanır; format GNU `sha256sum` ile
**byte-uyumlu** olduğundan Linux/macOS tarafında da doğrudan
`sha256sum -c SHA256SUMS.txt` ile çalışır.

### Üretim

```powershell
# Build çıktılarını hash'le
.\SHA256-Verify.ps1 -Path .\build\output -OutputFile .\build\output\SHA256SUMS.txt
```

Üretilen `SHA256SUMS.txt`:

```
abc123...  RdpVirtualBoxApp-Client-v1.0.0.exe
def456...  RdpVirtualBoxApp-Server-v1.0.0.exe
```

### Doğrulama

```powershell
# PowerShell ile
.\SHA256-Verify.ps1 -Path .\build\output\SHA256SUMS.txt -Verify

# Linux / macOS'ta
sha256sum -c SHA256SUMS.txt
```

`SHA256-Verify.ps1` `-Verify` modunda her dosya için `OK` veya `FAILED`
satırı yazar; herhangi bir uyumsuzluk varsa exit kodu 1 ile biter.

### Workflow Entegrasyonu

`.github/workflows/build.yml` zaten `Get-FileHash` ile inline SHA256SUMS
üretiyor. `SHA256-Verify.ps1` modülü, build pipeline'ı içinde şu
şekilde de çağrılabilir:

```yaml
- name: Generate SHA256SUMS
  shell: pwsh
  run: |
    pwsh -NoProfile -File src/powershell/SHA256-Verify.ps1 `
      -Path build/output `
      -OutputFile build/output/SHA256SUMS.txt
```

---

## Geriye Dönük Uyumluluk

`manifestVersion` alanı, client tarafında şema geçişleri için
kullanılır. Client, `manifestVersion` değerini kendi desteklediği
aralıkta değilse kullanıcıya uyarı gösterir:

| manifestVersion | Client Davranışı |
|-----------------|------------------|
| 1.0.0 | Tam destek. |
| 1.1.x (gelecek) | Yeni alanlar göz ardı edilir, eski alanlar okunur. |
| 2.x.x | Client uyarısı: "Manifest sürümü yeni." |

Yeni alanlar eklenirken geriye dönük uyumluluk korunmalı, mevcut
alan kaldırılmamalı veya tipleri değiştirilmemelidir.

---

## Örnek Manifest

Gerçek bir sunucu için beklenen çıktı (kısaltılmış):

```json
{
  "manifestVersion": "1.0.0",
  "generatedAt": "2026-08-19T13:45:12Z",
  "server": {
    "fqdn": "rdp.jber.local",
    "ip": "192.168.0.106",
    "domain": "jber.local",
    "os": "Windows Server 2019 Datacenter"
  },
  "connectionStrategies": {
    "direct":     { "enabled": true,  "port": 3389, "url": "192.168.0.106:3389" },
    "gateway":    { "enabled": false, "port": 443,  "url": null },
    "guacamole":  { "enabled": true,  "port": 8443, "url": "https://rdp.jber.local:8443/guacamole" },
    "tailscale":  { "enabled": false, "url": null },
    "cloudflare": { "enabled": false, "url": null }
  },
  "webEndpoint": {
    "type": "Guacamole",
    "url":  "https://rdp.jber.local:8443/guacamole"
  },
  "remoteApps": [
    {
      "alias":     "NebimWinner",
      "name":      "Nebim Winner",
      "path":      "C:\\Program Files\\Nebim\\Winner\\winner.exe",
      "publisher": "Nebim",
      "icon":      "C:\\Program Files\\Nebim\\Winner\\winner.exe"
    },
    {
      "alias":     "Logo",
      "name":      "Logo Tiger",
      "path":      "C:\\Program Files\\Logo\\logo.exe",
      "publisher": "Logo",
      "icon":      "C:\\Program Files\\Logo\\logo.exe"
    }
  ],
  "certificate": {
    "thumbprint": "A1B2C3D4E5F6...",
    "type": "SelfSigned"
  }
}
```

---

## İlgili Dosyalar

- [src/powershell/server/Generate-Manifest.ps1](../src/powershell/server/Generate-Manifest.ps1)
- [src/powershell/SHA256-Verify.ps1](../src/powershell/SHA256-Verify.ps1)
- [src/powershell/client/SetupUI.ps1](../src/powershell/client/SetupUI.ps1)
- [src/powershell/client/ServerProbe.ps1](../src/powershell/client/ServerProbe.ps1)
- [docs/server-setup-guide.md](server-setup-guide.md)
- [docs/client-setup-guide.md](client-setup-guide.md)
- [docs/troubleshooting.md](troubleshooting.md)
