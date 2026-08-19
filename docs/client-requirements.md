# Client Tarafı Gereksinimler

Bu belge, **Rdp Virtual Box App — Client Setup** EXE'sini çalıştırmadan önce son kullanıcı bilgisayarının sahip olması gereken bileşenleri tanımlar.

---

## İçindekiler

- [İşletim Sistemi](#işletim-sistemi)
- [RDP Client](#rdp-client)
- [Tarayıcı (Web Modu)](#tarayıcı-web-modu)
- [.NET Framework](#net-framework)
- [Ağ Erişimi](#ağ-erişimi)
- [Disk Alanı](#disk-alanı)
- [Kurulum Öncesi Checklist](#kurulum-öncesi-checklist)

---

## İşletim Sistemi

| OS | Minimum Build | Önerilen |
|---|---|---|
| **Windows 11** | 21H2 (Build 22000) | 23H2+ |
| **Windows 10** | 1809 (Build 17763) | 22H2 |
| **Windows 8.1** | — | ❌ Desteklenmiyor (RDP 8.0 sınırlamaları) |
| **Windows 7** | — | ❌ Desteklenmiyor |

> **Önemli:** Windows 10 1809 öncesi sürümlerde RemoteApp `remoteapplicationprogram:s:||alias` parametre düzgün çalışmaz.

### macOS

**Resmi olarak desteklenir** (1.1.0+). İki seçenek mevcuttur:

| Yöntem | Uygulama | Bağlantı Tipi |
|---|---|---|
| **Web Modu** | Safari / Chrome / Firefox | RD Web Access veya Apache Guacamole üzerinden HTML5 |
| **Native Client** | `RdpVirtualBoxApp-Client.dmg` (SwiftUI) | Microsoft Remote Desktop.app ile `.rdp` veya `rdp://` URL'si |

| macOS Sürümü | Minimum Build | Önerilen |
|---|---|---|
| **macOS Sonoma** | 14.0 | 14.5+ |
| **macOS Ventura** | 13.0 | 13.6+ |
| **macOS Monterey** | 12.0 | 12.7+ |

#### Web Modu (Tavsiye Edilen)

Modern tarayıcı üzerinden RD Web Access veya Guacamole'a bağlanır. Kurulum gerektirmez.

#### Native Client (SwiftUI)

`RdpVirtualBoxApp-Client-vX.X.X.dmg` dosyasını indirin ve `Applications` klasörüne sürükleyin. Sihirbaz `.rdp` dosyaları üretir ve bunları Microsoft Remote Desktop.app ile açar. **Microsoft Remote Desktop** App Store'dan ücretsiz yüklenmelidir.

#### Bağımlılıklar

| Bileşen | Yükleme |
|---|---|
| **macOS 12+** | Sistem güncellemesi |
| **Microsoft Remote Desktop** | App Store → "Microsoft Remote Desktop" |
| **Xcode Command Line Tools** | `xcode-select --install` (yalnızca DMG build için; son kullanıcı gerektirmez) |

### Linux

**Resmi olarak desteklenmiyor.** Ancak:
- `.rdp` dosyaları FreeRDP (`xfreerdp`) ile açılabilir.
- Web modu modern tarayıcılarla çalışır.

---

## RDP Client

| Tür | Yol | Not |
|---|---|---|
| **mstsc.exe** | `%SystemRoot%\System32\mstsc.exe` | Windows ile birlikte gelir; yeterli. |
| **Remote Desktop App** | Microsoft Store | Modern UI, çoklu bağlantı; önerilen. |
| **Remote Desktop Manager** | Üçüncü parti | Gelişmiş yönetim için. |

### mstsc.exe Sürüm Gereksinimi

- RDP 7.1+ (Windows 7 / Server 2008 R2)
- **Önerilen:** RDP 10.0+ (Windows 10 1809+)

Eski sürümler `remoteapplicationmode:i:1` parametresini yok sayar ve tam masaüstü bağlantısı kurar.

---

## Tarayıcı (Web Modu)

`Bağlantı tipi = Web` veya `Both` seçildiğinde aşağıdaki tarayıcılardan biri gereklidir:

| Tarayıcı | Minimum | Notlar |
|---|---|---|
| **Microsoft Edge** | 100+ | Chromium tabanlı; önerilen. |
| **Google Chrome** | 100+ | Chromium tabanlı. |
| **Mozilla Firefox** | 100+ | Tam uyumlu; performans biraz düşük olabilir. |
| **Safari** | 14+ | macOS / iPadOS için. |

### Web Modu İçin Ek Bileşenler

- **WebSocket desteği** — tüm modern tarayıcılarda vardır.
- **Service Worker** — PWA install için (Edge/Chrome/Firefox).
- **HTML5 Canvas / WebGL** — RemoteApp rendering.

---

## .NET Framework

| Bileşen | Minimum | Önerilen |
|---|---|---|
| **.NET Framework** | 4.7.2 | 4.8 |
| **PowerShell** | 5.1 | 7.4 (opsiyonel) |

WinForms wizard `.NET Framework 4.7.2+` ile derlenmiştir. Windows 10 1809+ ve Windows 11 zaten 4.8 ile gelir.

---

## Ağ Erişimi

### Client → Server bağlantı noktaları

| Port | Kullanım | Tetikleyici |
|---|---|---|
| 3389/TCP | Direct RDP | Direct stratejisi seçildiyse |
| 443/TCP | RD Web / RD Gateway | Gateway stratejisi seçildiyse |
| 8443/TCP | Guacamole | Guacamole stratejisi seçildiyse |
| 5985/TCP | WinRM (ServerProbe) | Sihirbazın ilk adımında (opsiyonel, çalışmasa da devam eder) |
| 41641/UDP | Tailscale mesh | Tailscale stratejisi seçildiyse (outbound) |

### Outbound

- HTTPS (443) — Cloudflare Tunnel, RD Web, Guacamole, sertifika doğrulama.
- Tailscale DERP relay (outbound 443) — NAT arkası cihazlar için.

### Proxy / Kurumsal Firewall

Kurumsal ortamda:
- `.rdp` trafiği şifreli olduğu için genellikle proxy'den geçmez (TCP 3389 doğrudan erişim gerekir veya RD Gateway kullanılır).
- Web trafiği HTTP proxy üzerinden yönlendirilebilir.

---

## Disk Alanı

| Bileşen | Boyut |
|---|---|
| Setup EXE indirme | ~5-8 MB |
| Extract (`%TEMP%\RdpVirtualBoxApp\`) | ~3 MB |
| `.rdp` dosyaları | ~2 KB / uygulama |
| Start Menu kısayolları | ~1 KB / uygulama |
| Credential Manager | registry tabanlı (disk kullanmaz) |
| PWA manifest (opsiyonel) | ~1 KB |
| Web kısayolları | ~1 KB / uygulama |
| **Toplam (10 uygulama)** | **~5 MB** |

---

## Kurulum Öncesi Checklist

Client setup'ı çalıştırmadan önce kullanıcıdan şunları doğrulamasını isteyin:

- [ ] Windows 10 1809+ veya Windows 11
- [ ] Yönetici hakkı (Setup EXE admin olarak çalışır — sadece bu yeterli)
- [ ] Server kurulumunun tamamlandığı (IT admin ile teyit)
- [ ] Server IP / FQDN adresi biliniyor
- [ ] Kullanıcı adı + parola hazır
- [ ] Domain biliniyor (örn. `FIRMA\kullanici` veya `kullanici@firma.local`)
- [ ] Ağ bağlantısı aktif (VPN veya LAN)
- [ ] RDP port'u (3389) erişilebilir (ping ile test edilebilir)

> **Not:** Kullanıcının RDP portuna doğrudan erişimi yoksa bile setup çalışır; web modu (RD Web / Guacamole) otomatik kullanılabilir.

---

## İlgili Belgeler

- [client-setup-guide.md](client-setup-guide.md) — Adım adım kullanıcı kurulumu
- [troubleshooting.md](troubleshooting.md) — Yaygın sorunlar
- [../README.md](../README.md) — Proje özeti
