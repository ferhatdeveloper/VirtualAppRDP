# Changelog

Tüm önemli değişiklikler bu dosyada belgelenir.

Format [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) standardına uygundur.
Versiyonlama [Semantic Versioning](https://semver.org/) kurallarına uyar.

---

## [1.0.0] - 2026-08-19

İlk resmi sürüm. `Rdp Virtual Box App` ürününün ilk kararlı release'i.

### Eklenenler (Added)

#### Server-Side
- **RDS Rolleri Kurulumu** (`RdsInstaller.ps1`)
  - Session Host, Web Access, Gateway, Licensing, Connection Broker
  - Alias tabanlı özellik adı çözümleme (`SessionHost` → `RDS-RD-Server`)
  - Otomatik rollback (`Uninstall-WindowsFeature`)
  - Management tools opsiyonu
  - `AutoRestart` parametresi
- **Sertifika Yönetimi** (`CertificateManager.ps1`)
  - Self-signed sertifika üretimi (`New-SelfSignedCertificate`)
  - CA-signed PFX import (`Import-PfxCertificate`)
  - RDP-Tcp dinleyicisine sertifika bağlama (`wmic Win32_TSGeneralSetting`)
- **RemoteApp Yayıncı** (`RemoteAppPublisher.ps1`)
  - Koleksiyon oluşturma
  - Uygulama yayını (`New-RDRemoteApp`)
  - Yayınlanan uygulamaların listesi
- **Firewall Konfigürasyonu** (`FirewallConfig.ps1`)
  - 3389, 443, 8443, 5985/5986 port kuralları
- **Lisans Tespiti** (`LicenseDetector.ps1`)
  - 3 senaryo: lisans var, yok, grace period
  - Registry tabanlı grace period okuma
  - Otomatik öneri (RD Web vs Guacamole)
- **Apache Guacamole Fallback** (`GuacamoleInstaller.ps1`)
  - JDK 17 + Tomcat 9 + guacd + MySQL otomatik kurulum
  - HTTPS port 8443
  - Self-signed cert ile HTTPS
- **Uygulama Tarayıcı** (`AppScanner.ps1`)
  - `C:\Program Files`, `Program Files (x86)`, `ProgramData` altında .exe tarama
  - Versiyon, ikon, kategori tespiti
- **Server WinForms Sihirbazı** (`ServerSetupUI.ps1`)
  - 7 adımlı kurulum
  - Türkçe varsayılan, İngilizce fallback
  - Aero modern tasarım
- **5 Bağlantı Stratejisi**
  - Direct RDP
  - RD Gateway
  - Apache Guacamole
  - Tailscale mesh VPN
  - Cloudflare Tunnel
  - Hybrid (çoklu seçim)

#### Client-Side
- **Sunucu Tespiti** (`ServerProbe.ps1`)
  - WinRM ile bileşen analizi
  - JSON formatlı sonuç
  - HTML5 endpoint tipi tespiti (RD Web / Guacamole)
- **WinForms Sihirbaz** (`SetupUI.ps1`)
  - 4 adımlı kurulum
  - Çoklu uygulama seçimi
  - Native / Web / Both bağlantı tipi
- **.rdp Üretici** (`RdpBuilder.ps1`)
  - Şablon tabanlı üretim
  - RD Gateway desteği
  - Tailscale IP routing
  - UTF-8 dosya çıktısı
- **HTML5 Erişim** (`WebShortcuts.ps1`)
  - RD Web URL kısayolu (`.url` dosyası)
  - Guacamole URL kısayolu (port 8443)
  - PWA manifest üretimi (Edge/Chrome install)
- **Credential Manager** (`Credential.ps1`)
  - Generic Credential türü
  - Sunucu IP + uygulama kimliği tabanlı hedef anahtar
- **App Registry** (`AppRegistry.ps1`)
  - JSON tabanlı uygulama kayıt defteri
  - Register / Unregister / Update operasyonları

#### CI/CD
- **GitHub Actions Build Pipeline** (`.github/workflows/build.yml`)
  - `windows-latest` runner
  - PowerShell 7.4 kurulumu
  - PSScriptAnalyzer
  - Pester testleri
  - Inno Setup ile Client + Server derleme
  - Artifact upload
- **GitHub Actions Release** (`.github/workflows/release.yml`)
  - Tag-based release (`v*`)
  - Otomatik artifact yükleme
  - SHA256SUMS üretimi

#### Dokümantasyon
- `README.md` — Proje özeti (Türkçe + İngilizce)
- `docs/server-requirements.md`
- `docs/client-requirements.md`
- `docs/server-setup-guide.md`
- `docs/client-setup-guide.md`
- `docs/licensing-and-rdweb.md`
- `docs/troubleshooting.md`

#### Testler
- **Pester 5** birim testleri
  - `tests/client/test-server-probe.ps1`
  - `tests/client/test-rdp-builder.ps1`
  - `tests/client/test-app-registry.ps1`
  - `tests/client/test-web-shortcuts.ps1`
  - `tests/server/test-rds-installer.ps1`
  - `tests/server/test-license-detector.ps1`
  - `tests/server/test-guacamole-installer.ps1`

### Bilinen Sınırlamalar (Known Limitations)

- macOS / Linux istemciler resmi olarak desteklenmiyor (web modu hariç).
- Test ortamı olmadığından gerçek sunucu entegrasyon testleri kullanıcıya ertelenmiş.
- Guacamole performansı native RDP'den düşük olabilir (özellikle CAD / yüksek yenileme gerektiren uygulamalarda).
- Cloudflare Tunnel ücretsiz tier bağlantı sınırı uygular.
- Tailscale ücretsiz tier 100 cihaz sınırı.

### Planlanan (Roadmap)

- [ ] TailscaleInstaller.ps1 ve CloudflareTunnelInstaller.ps1 ayrı modüller
- [ ] RDGatewayInstaller.ps1 ayrı modül
- [ ] Server Core GUI'siz kurulum için PowerShell-only mode
- [ ] Daha geniş test ortamı (Windows Server VM ile GitHub Actions)
- [ ] Mermaid diyagramları ile detaylı mimari dokümanı
- [ ] Powershell DSC entegrasyonu

---

## [Unreleased]

Gelecek sürümler için planlama aşamasında.

### Planlananlar
- Multi-tenant koleksiyon yönetimi
- Otomatik sertifika yenileme (Let's Encrypt ACME)
- Prometheus / OpenTelemetry metrikleri
- Webhook tabanlı olay bildirimleri
- Çoklu dil desteği (TR / EN / DE)

---

[1.0.0]: https://github.com/ferhatdeveloper/VirtualAppRDP/releases/tag/v1.0.0
[Unreleased]: https://github.com/ferhatdeveloper/VirtualAppRDP/compare/v1.0.0...HEAD
