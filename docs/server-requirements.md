# Server Tarafı Gereksinimler

Bu belge, **Rdp Virtual Box App — Server Setup** EXE'sini çalıştırmadan önce Windows Server'ın sahip olması gereken donanım, yazılım, ağ ve lisans gereksinimlerini tanımlar.

> Server setup'ı, kurulum başlamadan önce bu bileşenleri otomatik olarak tarar ve eksik olanları raporlar (ServerProbe).

---

## İçindekiler

- [Donanım Gereksinimleri](#donanım-gereksinimleri)
- [Yazılım Gereksinimleri](#yazılım-gereksinimleri)
- [Ağ Gereksinimleri](#ağ-gereksinimleri)
- [Lisans Gereksinimleri](#lisans-gereksinimleri)
- [Sertifika Gereksinimleri](#sertifika-gereksinimleri)
- [Domain Gereksinimleri (Opsiyonel)](#domain-gereksinimleri-opsiyonel)
- [Kurulum Öncesi Checklist](#kurulum-öncesi-checklist)

---

## Donanım Gereksinimleri

| Senaryo | CPU | RAM | Disk | Ağ |
|---|---|---|---|---|
| **Sadece RDS** (10-25 kullanıcı) | 4 core | 8 GB + kullanıcı başı 2 GB | 40 GB | 1 GbE |
| **RDS + RemoteApp** (25-50 kullanıcı) | 8+ core | 16 GB + kullanıcı başı 2 GB | 60 GB | 1 GbE |
| **RDS + Guacamole** (HTML5 fallback) | 8+ core | 20 GB (Guacamole +4 GB) | 75 GB | 1 GbE |
| **RDS + Tailscale** | 4 core | 8 GB | 40 GB | 1 GbE (UDP 41641 çıkış) |
| **RDS + Cloudflare Tunnel** | 4 core | 8 GB | 40 GB | 1 GbE (outbound 443) |
| **Hybrid (hepsi)** | 16+ core | 32 GB | 100 GB | 1 GbE + düşük latency |

### Detaylar

**CPU:** Modern Intel Xeon / AMD EPYC önerilir. RDP session başına ~0.5-1 vCPU ayrılması tavsiye edilir.

**RAM:** TermService + Win32k.sys tabanlı session'lar kullanıcı başı minimum 2 GB RAM tüketir. RemoteApp uygulamalarının kendi bellek yükünü de hesaba katın.

**Disk:**
- Sistem: 20 GB (Windows Server 2022)
- RDS rolleri + WinRM logs: ~5 GB
- Uygulamalar (ERP vb.): kurulacak uygulamanın boyutu
- Guacamole: JDK 17 (~200 MB) + Tomcat 9 (~30 MB) + MySQL (~500 MB) + guacd (~50 MB) + webapp (~50 MB) ≈ **1.5 GB ekstra**

**Ağ:** Kullanıcı başı 1-5 Mbps simetrik bant genişliği. Ses yönlendirme açıksa +0.5 Mbps/kullanıcı.

---

## Yazılım Gereksinimleri

| Bileşen | Minimum | Önerilen |
|---|---|---|
| **İşletim Sistemi** | Windows Server 2016 | Windows Server 2019 / 2022 |
| **.NET Framework** | 4.7.2 | 4.8 |
| **PowerShell** | 5.1 | 7.4 (CI için) |
| **WinRM** | Aktif (5985/5986) | Aktif |
| **Sunucu Rolü** | Member Server | Domain-joined |
| **Update durumu** | Kritik güncellemeler yüklü | Tüm quality updates |

### Server Core Desteği

Server Core (GUI olmayan) üzerinde çalışır. Ancak:
- `RdpVirtualBoxApp-Server-vX.X.X.exe` WinForms kullandığı için **ilk kurulumda tam GUI gerekebilir** (Uzak Masaüstü üzerinden bağlanın veya VM console'una geçin).
- Kurulum sonrası sunucu Server Core'a dönüştürülebilir (opsiyonel, test gerektirir).

### Desteklenmeyen OS

- Windows Server 2008 / 2012 (RDS mimarisi farklı)
- Windows 10/11 (yanlış platform — bu **client** setup'ı içindir)
- Linux / macOS (uzak RDP client'ları desteklenmez)

---

## Ağ Gereksinimleri

### Açılması Gereken Portlar (Inbound)

| Port | Protokol | Servis | Açıklama |
|---|---|---|---|
| 3389 | TCP | RDP | Direct RDP bağlantısı |
| 443 | TCP | HTTPS | RD Web Access + RD Gateway |
| 8443 | TCP | HTTPS | Apache Guacamole (fallback) |
| 8444 | TCP | HTTP  | Probe REST API (macOS / HTTP istemcileri) |
| 5985 | TCP | WinRM (HTTP) | Client ServerProbe için |
| 5986 | TCP | WinRM (HTTPS) | Client ServerProbe için (önerilen) |

### Outbound Portlar

| Port | Protokol | Kullanım |
|---|---|---|
| 443 | TCP | Tailscale cloud relay, Cloudflare Tunnel |
| 41641 | UDP | Tailscale mesh VPN |
| 80 | TCP | MySQL/MariaDB için Windows Update (kurulum sırasında) |

### Firewall Kuralları (otomatik)

`FirewallConfig.ps1` modülü aşağıdaki kuralları ekler:

```powershell
New-NetFirewallRule -DisplayName "RDP 3389"          -Direction Inbound -LocalPort 3389 -Protocol TCP -Action Allow
New-NetFirewallRule -DisplayName "RD Web 443"        -Direction Inbound -LocalPort 443  -Protocol TCP -Action Allow
New-NetFirewallRule -DisplayName "Guacamole 8443"    -Direction Inbound -LocalPort 8443 -Protocol TCP -Action Allow
New-NetFirewallRule -DisplayName "Probe API 8444"    -Direction Inbound -LocalPort 8444 -Protocol TCP -Action Allow
New-NetFirewallRule -DisplayName "WinRM 5985/5986"   -Direction Inbound -LocalPort 5985-5986 -Protocol TCP -Action Allow
```

---

## Lisans Gereksinimleri

| Bileşen | Lisans | Senaryo |
|---|---|---|
| **Windows Server** | Standart veya Datacenter | Sunucu işletim sistemi |
| **RDS CAL** (User veya Device) | Microsoft Volume Licensing | Her eşzamanlı kullanıcı/cihaz için zorunlu (grace period dışında) |
| **RD Web Access** | RDS CAL kapsamında | Web tabanlı RemoteApp için |
| **Apache Guacamole** | Ücretsiz (Apache 2.0) | RD Web lisansı yoksa fallback |
| **Tailscale** | Ücretsiz tier (100 cihaz) / Team / Enterprise | NAT arkası cihazlar için mesh |
| **Cloudflare Tunnel** | Ücretsiz (sınırlı) / Pro | Public yayınlama için |

### Grace Period

- **120 gün** boyunca lisans olmadan RD Web Access kullanılabilir.
- `LicenseDetector.ps1` bu süreyi `HKLM:\SYSTEM\CurrentControlSet\Services\TermService\Parameters\License\GracePeriod` anahtarından okur.
- 120 günün sonunda bağlantılar kesilir; **Guacamole fallback** önerilir.

Detaylı karşılaştırma: [licensing-and-rdweb.md](licensing-and-rdweb.md)

---

## Sertifika Gereksinimleri

| Tür | Kullanım | Kaynak |
|---|---|---|
| **Self-signed** | Test / küçük ofis | Setup otomatik üretir (`New-SelfSignedCertificate`) |
| **CA-signed (Public CA)** | Kurumsal, RD Web için önerilen | Let's Encrypt, DigiCert vb. |
| **CA-signed (Internal CA)** | Kurumsal domain | Active Directory Certificate Services |

### RDP-Tcp Sertifikası

Setup, sertifikayı `wmic /namespace:\\root\cimv2\TerminalServices path Win32_TSGeneralSetting Set SSLCertificateSHA1Hash=...` ile RDP-Tcp dinleyicisine bağlar.

### RD Web / Gateway için

- Subject: sunucunun FQDN'i (örn. `rdp.firma.local`)
- SAN: tüm ulaşılabilir hostname'ler
- KeyLength: 2048+ bit
- SignatureAlgorithm: SHA-256+

---

## Domain Gereksinimleri (Opsiyonel)

| Mod | Domain | Açıklama |
|---|---|---|
| **Workgroup** | � | Çalışır; kullanıcılar lokal hesap olur. Sertifikalar self-signed olmalı. |
| **AD-joined** | ✅ Önerilen | Tek oturum açma (SSO), Group Policy ile RDP ayarları, otomatik sertifika dağıtımı. |
| **Azure AD-joined** | ⚠️ Sınırlı | RDS CAL ayrı ayrı yönetilir; karma yapılandırma gerekir. |

### AD Gerekli Olan Durumlar

- Group Policy ile RDP kullanıcı izinlerini yönetmek
- CA-signed sertifika otomatik enrollment
- RDS CAL'i User bazlı dağıtmak

---

## Kurulum Öncesi Checklist

Sunucu kurulum EXE'sini çalıştırmadan önce aşağıdaki adımları doğrulayın:

- [ ] Windows Server 2016+ kurulu
- [ ] En son Windows Update'ler yüklü
- [ ] Yönetici hesabıyla oturum açtınız (UAC elevated)
- [ ] Statik IP atanmış
- [ ] Sunucu adı FQDN formatında (örn. `rdp.firma.local`)
- [ ] DNS çözümlemesi çalışıyor
- [ ] WinRM servis etkin (`WinRM quickconfig`)
- [ ] Firewall'da 3389, 443, 5985 test amaçlı açık
- [ ] Yeterli disk alanı var (RDS + uygulamalar + Guacamole opsiyonel)
- [ ] RDS CAL lisans anahtarı hazır (veya grace period bilgilendirmesi kabul)
- [ ] Sertifika kararı verildi (self-signed mi, CA-signed mi)
- [ ] Bağlantı stratejisi kararı verildi (Direct / Gateway / Guacamole / Tailscale / Cloudflare)
- [ ] Yayınlanacak uygulamaların `.exe` yolları tespit edildi

> İlk kurulumu **test makinesinde** denemeniz önerilir.

---

## İlgili Belgeler

- [server-setup-guide.md](server-setup-guide.md) — Adım adım kurulum
- [licensing-and-rdweb.md](licensing-and-rdweb.md) — Lisans stratejisi
- [troubleshooting.md](troubleshooting.md) — Yaygın sorunlar
