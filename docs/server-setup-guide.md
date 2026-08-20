# Server Kurulum Kılavuzu

Bu belge, **IT Admin** için Windows Server'a **Rdp Virtual Box App — Server Setup**'ı adım adım kurulumu anlatır.

> Server setup çalıştırılmadan önce [server-requirements.md](server-requirements.md) belgesini okuyun.

---

## İçindekiler

- [Senaryo 1: Yeni Sunucu](#senaryo-1-yeni-sunucu)
- [Senaryo 2: Var Olan Sunucu](#senaryo-2-var-olan-sunucu)
- [Adım 1: Server Setup EXE İndirme](#adım-1-server-setup-exe-indirme)
- [Adım 2: Yönetici Olarak Çalıştırma](#adım-2-yönetici-olarak-çalıştırma)
- [Adım 3: 7 Adımlı Sihirbaz](#adım-3-7-adımlı-sihirbaz)
  - [3.1 Hoş Geldiniz](#31-hoş-geldiniz)
  - [3.2 Bileşen Seçimi](#32-bileşen-seçimi)
  - [3.3 Lisans Kontrolü](#33-lisans-kontrolü)
  - [3.4 Bağlantı Stratejisi Seçimi](#34-bağlantı-stratejisi-seçimi)
  - [3.5 Uygulama Seçimi](#35-uygulama-seçimi)
  - [3.6 İnceleme](#36-inceleme)
  - [3.7 Kurulum](#37-kurulum)
- [SSL Sertifika Kurulumu](#ssl-sertifika-kurulumu)
- [Lisans Aktivasyonu](#lisans-aktivasyonu)
- [Firewall Yapılandırması](#firewall-yapılandırması)
- [Kullanıcı İzinleri](#kullanıcı-izinleri)

---

## Senaryo 1: Yeni Sunucu

1. Windows Server 2019/2022 kurun (GUI veya Server Core).
2. Sunucuyu domaine dahil edin (opsiyonel, ama önerilir).
3. Statik IP atayın.
4. Windows Update'i çalıştırın.
5. Aşağıdaki adımlarla devam edin.

## Senaryo 2: Var Olan Sunucu

1. **Mevcut RDS rollerini kontrol edin:**

   ```powershell
   Get-WindowsFeature -Name RDS-* | Where-Object InstallState -eq 'Installed'
   ```

2. **Mevcut RemoteApp koleksiyonlarını listeleyin:**

   ```powershell
   Get-RDSessionCollection
   ```

3. **Mevcut RDP-Tcp sertifikasını not alın:**

   ```powershell
   wmic /namespace:\\root\cimv2\TerminalServices path Win32_TSGeneralSetting Get SSLCertificateSHA1Hash
   ```

4. Snapshot / backup alın (geri dönüş için).
5. Server Setup EXE'yi çalıştırın — modüller idempotenttir, var olan bileşenleri atlar.

---

## Adım 1: Server Setup EXE İndirme

GitHub Releases sayfasından en son `RdpVirtualBoxApp-Server-vX.X.X.exe` dosyasını indirin:

```
https://github.com/ferhatdeveloper/VirtualAppRDP/releases
```

> Alternatif: kaynak kodu clone'layıp `ISCC.exe src/inno/RdpVirtualBoxApp-Server.iss` ile derleyin.

---

## Adım 2: Yönetici Olarak Çalıştırma

EXE'ye sağ tıklayın → **"Run as administrator"** (Yönetici olarak çalıştır). UAC onayını verin.

İlk açılışta Inno Setup lisans sözleşmesini kabul edin ve kurulum yolunu onaylayın (varsayılan: `C:\Program Files\RdpVirtualBoxApp`).

---

## Adım 3: 7 Adımlı Sihirbaz

Sihirbaz başladığında her adımda ne yapılacağı aşağıda açıklanmıştır.

### 3.1 Hoş Geldiniz

- **Sunucu adı:** Otomatik algılanır.
- **FQDN:** `hostname.firma.local` biçiminde gösterilir.
- **Domain üyeliği:** Workgroup veya Domain — otomatik tespit.
- **Lisans kabulü:** MIT lisansı görüntülenir, kabul edin.

### 3.2 Bileşen Seçimi

İhtiyacınız olan ana checkbox'ları işaretleyin:

| Bileşen | Açıklama |
|---|---|
| **RDS Rolleri** | Session Host, Web Access, Gateway, Licensing, Connection Broker |
| **Self-signed Sertifika** | Test için yeterli; kurumsal için CA-signed kullanın |
| **CA-signed Sertifika** | `.pfx` dosyası seçtirir |
| **RD Web Access** | HTML5 erişim (lisans gerektirir) |
| **RD Gateway** | HTTPS üzerinden RDP tünelleme |
| **Apache Guacamole** | RD Web lisansı yoksa fallback |
| **Tailscale** | NAT arkası cihazlar için mesh VPN |
| **Cloudflare Tunnel** | Dışarıya port açmadan yayınlama |
| **App kütüphanesi** | `AppScanner.ps1` ile sunucudaki .exe'leri tarar |

### 3.3 Lisans Kontrolü

`LicenseDetector.ps1` otomatik olarak:

1. `Get-WindowsFeature RDS-Licensing` → rol kurulu mu?
2. `Get-RDLicenseConfiguration` → lisans sunucusu aktif mi?
3. `HKLM:\...\TermService\Parameters\License\GracePeriod` → kalan gün sayısı

Sonuç:

| Senaryo | HasRdWebLicense | Recommendation |
|---|---|---|
| Lisans var | ✅ true | **Use RD Web** |
| Rol yok / lisans yok | ❌ false | **Install Guacamole** (otomatik öneri) |
| Grace period | ❌ false | **Install Guacamole** (120 gün kaldı) |

### 3.4 Bağlantı Stratejisi Seçimi

Birden fazla stratejiyi aynı anda seçebilirsiniz:

| Strateji | Ne zaman seçin |
|---|---|
| **Direct RDP** | Sadece ofis içi kullanıcılar, VPN olan ortam |
| **RD Gateway** | Kurumsal, firewall dostu erişim |
| **Apache Guacamole** | RD Web lisansı yok veya HTML5 gerekli |
| **Tailscale** | Sıfır konfigürasyon, NAT arkası cihazlar |
| **Cloudflare Tunnel** | Public domain + Cloudflare hesabı var |
| **Hybrid** | Birden fazla senaryo (örn. Direct + Gateway) |

### 3.5 Uygulama Seçimi

`AppScanner.ps1` çalıştırılır ve sunucudaki tüm `.exe`'ler listelenir:

```
Program Files\
Program Files (x86)\
ProgramData\
```

Her uygulama için:
- **Ad** (display name)
- **Yol** (`C:\Program Files\App\app.exe`)
- **Sürüm** (file version)
- **Kategori** (ERP / Office / Browser / Tools / Custom)

Yayınlamak istediklerinizi işaretleyin ve "İleri"ye basın.

### 3.6 İnceleme

Tüm seçimlerin özeti gösterilir:

```
RDS Rolleri:           ✅ Kurulacak
Sertifika:             ✅ Self-signed (rdp.firma.local)
Bağlantı Stratejileri: ✅ Direct + Gateway
Uygulamalar:           ✅ ERP, Raporlama, Muhasebe
Log Yolu:              C:\ProgramData\RdpVirtualBoxApp\Logs\server-setup.log
```

### 3.7 Kurulum

**"Install"** butonuna bastığınızda sırasıyla:

1. `RdsInstaller.ps1` — RDS rolleri kurulumu
2. `CertificateManager.ps1` — Sertifika üretimi / import
3. `FirewallConfig.ps1` — Port kuralları
4. `RemoteAppPublisher.ps1` — RemoteApp koleksiyonu oluşturma + uygulama yayını
5. (Opsiyonel) `GuacamoleInstaller.ps1` — JDK + Tomcat + guacd + MySQL
6. (Opsiyonel) `TailscaleInstaller.ps1` — Mesh VPN
7. (Opsiyonel) `CloudflareTunnelInstaller.ps1` — Public yayınlama
8. (Opsiyonel) `RDGatewayInstaller.ps1` — Gateway kurulumu

Tüm adımlar **rollback desteklidir**: bir adım hata verirse kurulum öncesi duruma geri dönülür.

Kurulum log'u: `%ProgramData%\RdpVirtualBoxApp\Logs\server-setup.log`

---

## SSL Sertifika Kurulumu

### Self-signed (test için)

Sihirbaz otomatik olarak üretir. RDP-Tcp dinleyicisine bağlanır. Tarayıcı uyarısı verir; **üretim için uygun değildir**.

### CA-signed (önerilen)

1. Sertifika otoritesinden `.pfx` dosyası alın.
2. Sihirbazda **CA-signed Sertifika** seçin.
3. `.pfx` dosyasını ve parolasını girin.
4. Sertifika thumbprint'i `Cert:\LocalMachine\My`'e import edilir.
5. RDP-Tcp bağlantısına atanır (`wmic Win32_TSGeneralSetting`).

### Caddy HTTPS (Probe API, önerilen)

Probe REST API (8444) düz HTTP dinler. Caddy **8445** üzerinde TLS sonlandırır ve `127.0.0.1:8444`'e proxy eder. **443 RD Gateway / IIS'e aittir; Caddy 443 kullanmaz.**

```powershell
# Yonetici PowerShell
& "C:\Program Files\RdpVirtualBoxApp\PowerShell\Install-CaddySsl.ps1"
```

- **Alan adı yok:** Caddy dahili CA (`tls internal`). Sunucu `LocalMachine\Root` deposuna eklenir. İstemcilerde tarayıcı uyarısı olabilir.
- **Let's Encrypt:** ortam değişkeni `RDPVB_CADDY_DOMAIN` (ve isteğe bağlı `RDPVB_CADDY_EMAIL`) ayarlayıp script'i yeniden çalıştırın. ACME HTTP-01 için modemde **TCP 80 → 192.168.5.100** ve **TCP 8445** yönlendirmesi gerekir.
- Doğrulama: `https://127.0.0.1:8445/health`

### Let's Encrypt (RD Gateway / RDP sertifikası)

RDP-Tcp ve RD Web için `.pfx` gerekiyorsa:

- `win-acme` (eski adıyla `letsencrypt-win-simple`) kullanın.
- ACME challenge için 80 port'u kısa süreliğine açın.
- Üretilen `.pfx`'i sihirbazda **CA-signed Sertifika** olarak verin.

---

## Lisans Aktivasyonu

### RDS CAL Aktivasyonu

1. **Remote Desktop Services License Server** rolü kurulu olmalı (sihirbaz otomatik kurar).
2. **License Manager**'ı açın (`licmgr.exe`).
3. Sunucuyu Microsoft Volume Licensing Service'e bağlayın.
4. Lisans kodunu girin.
5. RDP kullanıcılarını User CAL ile eşleyin veya Device CAL atayın.

Detaylı bilgi: [licensing-and-rdweb.md](licensing-and-rdweb.md)

### Grace Period

120 günlük grace period boyunca lisans olmadan RD Web kullanılabilir. `LicenseDetector.ps1` kalan gün sayısını gösterir.

---

## Firewall Yapılandırması

`FirewallConfig.ps1` otomatik olarak aşağıdaki kuralları ekler:

```powershell
# RDP
New-NetFirewallRule -DisplayName "RDP 3389" -Direction Inbound -LocalPort 3389 -Protocol TCP -Action Allow

# RD Web / Gateway
New-NetFirewallRule -DisplayName "RD Web 443" -Direction Inbound -LocalPort 443 -Protocol TCP -Action Allow

# Guacamole
New-NetFirewallRule -DisplayName "Guacamole 8443" -Direction Inbound -LocalPort 8443 -Protocol TCP -Action Allow

# Probe REST API (HTTP) + Caddy TLS
New-NetFirewallRule -DisplayName "Probe API 8444" -Direction Inbound -LocalPort 8444 -Protocol TCP -Action Allow
New-NetFirewallRule -DisplayName "Caddy HTTPS 8445" -Direction Inbound -LocalPort 8445 -Protocol TCP -Action Allow

# WinRM (Client ServerProbe için)
New-NetFirewallRule -DisplayName "WinRM 5985" -Direction Inbound -LocalPort 5985 -Protocol TCP -Action Allow
New-NetFirewallRule -DisplayName "WinRM 5986" -Direction Inbound -LocalPort 5986 -Protocol TCP -Action Allow
```

### Kurumsal Firewall

Sunucu bir **edge firewall** arkasındaysa:
- **Direct RDP:** 3389'i NAT'layın veya VPN gerektirin.
- **RD Gateway / Cloudflare:** 443 yeterlidir.
- **Tailscale:** outbound 41641/UDP yeterlidir, inbound kural gerekmez.

---

## Kullanıcı İzinleri

### RDS Kullanıcı Grubu

RDP bağlantısı yapacak kullanıcılar `Remote Desktop Users` grubuna eklenmelidir:

```powershell
Add-LocalGroupMember -Group "Remote Desktop Users" -Member "FIRMA\kullanici"
```

### RemoteApp Erişim İzni

RemoteApp koleksiyonu için yetkilendirme:

```powershell
Set-RDSessionCollectionConfiguration -CollectionName "RdpVirtualBoxApp" -UserGroup "FIRMA\RDPUsers"
```

### Active Directory (önerilir)

Domain ortamında:
- Bir security group oluşturun: `RDP-Authorized-Users`.
- Grup üyelerini yönetin (admin yetkisi gerektirmez).
- Sihirbazda bu grubu `UserGroup` olarak belirtin.

---

## Kurulum Sonrası Doğrulama

```powershell
# 1. RDS rolleri kurulu mu?
Get-WindowsFeature -Name RDS-* | Where-Object InstallState -eq 'Installed'

# 2. RemoteApp koleksiyonu var mı?
Get-RDSessionCollection

# 3. Uygulamalar yayınlanmış mı?
Get-RDRemoteApp -CollectionName "RdpVirtualBoxApp"

# 4. Firewall kuralları açık mı?
Get-NetFirewallRule -DisplayName "RDP*","RD Web*","Guacamole*","WinRM*"

# 5. RD Web çalışıyor mu?
Invoke-WebRequest -Uri "https://localhost/RDWeb/webclient" -UseBasicParsing -SkipCertificateCheck

# 6. Guacamole çalışıyor mu?
Invoke-WebRequest -Uri "https://localhost:8443/guacamole" -UseBasicParsing -SkipCertificateCheck

# 7. Probe REST API çalışıyor mu?
Invoke-RestMethod -Uri "http://localhost:8444/health"
# Token: %ProgramData%\RdpVirtualBoxApp\Config\probe-api.json
$cfg = Get-Content "$env:ProgramData\RdpVirtualBoxApp\Config\probe-api.json" -Raw | ConvertFrom-Json
Invoke-RestMethod -Uri "http://localhost:8444/probe/api/probe" -Headers @{ Authorization = "Bearer $($cfg.token)" }
```

Tüm komutlar başarılıysa server hazırdır. **Client Setup EXE'sini kullanıcılara dağıtabilirsiniz.**

---

## Probe REST API

macOS ve HTTP istemcileri WinRM kullanamaz. Server setup, **TCP 8444** üzerinde Probe REST API host'unu scheduled task olarak kurar:

```powershell
# Elle kur / baslat
powershell -ExecutionPolicy Bypass -File .\src\powershell\server\Install-ProbeApiHost.ps1

# Durum
powershell -ExecutionPolicy Bypass -File .\src\powershell\server\Start-ProbeApiHost.ps1 -Mode Status
```

| Method | Yol | Auth | Aciklama |
|---|---|---|---|
| GET | `/health` | Hayir | Canlilik |
| GET | `/probe/api/probe` | Bearer | Tam sunucu taramasi (Swift semasi) |
| GET | `/api/manifest` | Bearer | `server-manifest.json` |
| GET | `/api/apps` | Bearer | RemoteApp listesi |
| GET | `/api/status` | Bearer | Ozet durum |
| GET | `/` | Hayir | Endpoint katalogu |

Token dosyasi: `%ProgramData%\RdpVirtualBoxApp\Config\probe-api.json`

---

## İlgili Belgeler

- [server-requirements.md](server-requirements.md)
- [licensing-and-rdweb.md](licensing-and-rdweb.md)
- [troubleshooting.md](troubleshooting.md)
- [client-setup-guide.md](client-setup-guide.md)
