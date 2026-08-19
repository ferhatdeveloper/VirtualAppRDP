# Release Notes — v1.0.0

**Tarih:** 2026-08-19
**Etiket:** [`v1.0.0`](https://github.com/ferhatdeveloper/VirtualAppRDP/releases/tag/v1.0.0)
**Lisans:** MIT
**İlk kararlı sürüm** — Initial Stable Release

---

## Highlights

- **İki parçalı generic ürün:** Windows Server'a herhangi bir uygulamayı (ERP, muhasebe, raporlama, özel exe) RemoteApp olarak yayınlayın. Ürün adı "Rdp Virtual Box App" — uygulamadan bağımsız.
- **5 bağlantı stratejisi + Hybrid:** Direct RDP, RD Gateway, Apache Guacamole, Tailscale, Cloudflare Tunnel. Çoklu seçim destekli.
- **HTML5 fallback otomatik:** RD Web lisansı yoksa Apache Guacamole devreye girer — ek konfigürasyon gerekmez.
- **Native RDP + HTML5 erişim:** Kullanıcı seçimine göre `.rdp` dosyası, Start Menu kısayolu, web URL kısayolu (RD Web veya Guacamole), opsiyonel PWA manifest.
- **Otomatik sunucu tespiti:** WinRM ile RDS rolleri, RD Web lisansı, HTML5 endpoint tipi, sertifika durumu, uygulama listesi — JSON formatlı rapor.
- **GitHub Actions CI/CD:** Push'ta derleme + test, tag'de otomatik GitHub Release + SHA256SUMS.

---

## Features

### Server-Side

#### RDS Altyapısı
- `RdsInstaller.ps1` — RDS rolleri kurulumu (Session Host, Web Access, Gateway, Licensing, Connection Broker). Alias tabanlı özellik adı çözümleme, otomatik rollback, management tools opsiyonu, `AutoRestart` parametresi.
- `CertificateManager.ps1` — Self-signed veya CA-signed PFX import. RDP-Tcp dinleyicisine sertifika bağlama (`wmic Win32_TSGeneralSetting`).
- `RemoteAppPublisher.ps1` — RemoteApp koleksiyonu oluşturma, uygulama yayını (`New-RDRemoteApp`), koleksiyon listesi.
- `FirewallConfig.ps1` — TCP 3389 / 443 / 8443 / 5985/5986 inbound kuralları.

#### Lisans ve HTML5 Fallback
- `LicenseDetector.ps1` — 3 senaryo: lisans var / yok / 120-gün grace period. Registry tabanlı grace period okuma. Otomatik öneri.
- `GuacamoleInstaller.ps1` — JDK 17 + Tomcat 9 + guacd + MySQL otomatik kurulum. HTTPS port 8443, self-signed cert. ~15-25 dakika, ~1.5 GB disk.
- `TailscaleInstaller.ps1` *(plan referansı)* — Tailscale MSI kurulumu, mesh VPN auth.
- `CloudflareTunnelInstaller.ps1` *(plan referansı)* — cloudflared service kurulumu, DNS route konfigürasyonu.
- `RDGatewayInstaller.ps1` *(plan referansı)* — HTTPS üzerinden RDP tünelleme, CAP/RAP politikaları.

#### Uygulama Yönetimi
- `AppScanner.ps1` — `C:\Program Files`, `Program Files (x86)`, `ProgramData` altında .exe tarama. Versiyon, ikon, kategori, boyut. Kategorize çıktı: ERP, Office, Browser, Tools, Custom.

#### Server Sihirbazı
- `ServerSetupUI.ps1` — 7 adımlı WinForms sihirbazı. Türkçe varsayılan, İngilizce fallback. Aero modern tasarım. Tüm adımlar undo destekli. Log: `%ProgramData%\RdpVirtualBoxApp\Logs\server-setup.log`.

### Client-Side

#### Sunucu Tespiti
- `ServerProbe.ps1` — WinRM bileşen analizi. JSON çıktı: `server`, `os`, `reachable`, `winrm`, `components{}`, `existingRemoteApps[]`, `webEndpoint{type, url}`, `recommendations[]`.

#### Client Sihirbazı
- `SetupUI.ps1` — 4 adımlı WinForms:
  1. Welcome / Server (IP, port, domain\user, parola)
  2. Server Probe Sonuçları (yeşil/sarı/kırmızı durum)
  3. Applications & Connection Type (çoklu checkbox, Native/Web/Both)
  4. Review & Install

#### Çıktı Üretimi
- `RdpBuilder.ps1` — `rdp.template.txt` şablon motoru. Her seçilen uygulama için ayrı `.rdp`. RD Gateway desteği, Tailscale IP routing, UTF-8.
- `WebShortcuts.ps1` — RD Web URL kısayolu veya Guacamole URL kısayolu (port 8443). PWA manifest (`manifest.json` + `service-worker.js`).
- `Credential.ps1` — Generic Credential, sunucu IP + uygulama kimliği tabanlı hedef anahtar.
- `AppRegistry.ps1` — JSON tabanlı uygulama kayıt defteri.
- `SelfTest.ps1` — Bağlantı test komutları.

### CI/CD

- `.github/workflows/build.yml` — `windows-latest` runner. PowerShell 7.4 + PSScriptAnalyzer + Pester + Inno Setup derleme. Artifact upload.
- `.github/workflows/release.yml` — `v*` tag ile otomatik GitHub Release. Client + Server + SHA256SUMS yükler.
- `.github/workflows/docs.yml` — GitHub Pages deploy. `docs/` değişikliklerinde veya manuel dispatch.

---

## Screenshots

> Aşağıdaki ekran görüntüleri ilk çalıştırma sonrası eklenecek.

| Ekran | Açıklama |
| --- | --- |
| Server wizard — Welcome | 1/7 adım: sunucu bilgisi, lisans kabul |
| Server wizard — Component selection | 2/7 adım: RDS rolleri, sertifika, RD Web, Gateway, Guacamole, App kütüphanesi |
| Server wizard — Connection strategy | 4/7 adım: Direct / Gateway / Guacamole / Tailscale / Cloudflare / Hybrid |
| Server wizard — Application picker | 5/7 adım: `AppScanner` çıktısı + çoklu seçim |
| Client wizard — Server probe results | 2/4 adım: yeşil/sarı/kırmızı durum göstergesi |
| Client wizard — Apps + Connection type | 3/4 adım: çoklu uygulama seçimi, Native/Web/Both |
| Start Menu kısayolları | Her uygulama için ayrı `.rdp` kısayolu |
| HTML5 web erişim | RD Web Access veya Guacamole arayüzü |

---

## Installation

### Server-Side (IT Admin)

1. **Önkoşulları doğrulayın:** [server-requirements.md](server-requirements.md)
2. **`RdpVirtualBoxApp-Server-v1.0.0.exe`**'yi yönetici olarak çalıştırın.
3. 7 adımlı sihirbazı izleyin:
   - Bileşen seçimi (RDS, sertifika, RD Web, vb.)
   - Lisans kontrolü (otomatik)
   - Bağlantı stratejisi seçimi
   - Uygulama seçimi (`AppScanner` çıktısından)
   - İnceleme ve kurulum
4. Detaylı kılavuz: [server-setup-guide.md](server-setup-guide.md)
5. Log: `%ProgramData%\RdpVirtualBoxApp\Logs\server-setup.log`

### Client-Side (Son Kullanıcı)

1. IT admin'den şunları alın:
   - Sunucu IP adresi (veya Tailscale IP / Cloudflare hostname)
   - Domain kullanıcı adı ve parola
2. **`RdpVirtualBoxApp-Client-v1.0.0.exe`**'yi çalıştırın.
3. 4 adımlı sihirbazı izleyin:
   - Server bilgisi (IP, port, kullanıcı, parola)
   - Server Probe sonuçları (otomatik)
   - Uygulama seçimi + bağlantı tipi (Native/Web/Both)
   - İnceleme ve kurulum
4. Start Menu'den veya web URL'den uygulamaları açın.
5. Detaylı kılavuz: [client-setup-guide.md](client-setup-guide.md)

### Doğrulama

```bash
# SHA256 doğrulama
sha256sum -c SHA256SUMS.txt
```

---

## Known Issues

- **macOS / Linux istemciler** resmi olarak desteklenmiyor. Yalnızca web modu (RD Web / Guacamole) ile erişim mümkün.
- **Gerçek sunucu entegrasyon testi** CI'da yok — `ServerProbe` ve installer'lar yalnızca birim test kapsamında. İlk kurulumda manuel doğrulama gerekir.
- **Self-signed sertifika** ilk bağlantıda RDP istemcisi / tarayıcı uyarısı verir. Üretim için CA-signed PFX önerilir.
- **Guacamole performansı** native RDP'den düşük olabilir (CAD, video, yüksek yenileme hızı gerektiren uygulamalarda).
- **Tailscale** ücretsiz tier 100 cihazla sınırlı; DERP relay ek latency ekler.
- **Cloudflare Tunnel** ücretsiz tier bağlantı sayısı sınırlı.
- **Hybrid mod** seçildiğinde birden çok strateji bakım/dokümantasyon karmaşıklığı ekler.

Sorun giderme: [troubleshooting.md](troubleshooting.md)

---

## Upgrade Path

**N/A** — İlk sürüm. Önceki release yok.

---

## Links

- **Repository:** [github.com/ferhatdeveloper/VirtualAppRDP](https://github.com/ferhatdeveloper/VirtualAppRDP)
- **Release:** [github.com/ferhatdeveloper/VirtualAppRDP/releases/tag/v1.0.0](https://github.com/ferhatdeveloper/VirtualAppRDP/releases/tag/v1.0.0)
- **Issues:** [github.com/ferhatdeveloper/VirtualAppRDP/issues](https://github.com/ferhatdeveloper/VirtualAppRDP/issues)
- **Changelog:** [CHANGELOG.md](../CHANGELOG.md)
- **License:** [MIT](../LICENSE)
- **Docs site:** GitHub Pages (bu dizin)

---

## Katkıda Bulunanlar

Bu sürümün tüm modülleri @ferhatdeveloper tarafından geliştirilmiştir.

Rapor edilen hatalar ve öneriler için [Issues](https://github.com/ferhatdeveloper/VirtualAppRDP/issues) sayfasını kullanın.
