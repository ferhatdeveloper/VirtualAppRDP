# Changelog

Tüm önemli değişiklikler bu dosyada belgelenir.

Format [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) standardına uygundur.
Versiyonlama [Semantic Versioning](https://semver.org/) kurallarına uyar.

---

## [1.0.0] - 2026-08-19

İlk resmi sürüm. `Rdp Virtual Box App` ürününün ilk kararlı release'i.
Server-side ve client-side kurulum, 5 farklı bağlantı stratejisi ve HTML5 fallback içerir.

### Entegrasyon (Integration)

- `SetupUI.ps1` içindeki `Invoke-FullServerProbe` ve `Start-ClientInstall` stub'ları gerçek
  modüllere (ServerProbe.ps1, RdpBuilder.ps1, WebShortcuts.ps1, Credential.ps1,
  AppRegistry.ps1, SelfTest.ps1) bağlandı. Modül yükleme `Import-ClientModule` yardımcısı
  ile try/catch korumalı şekilde yapılıyor; her modülün yüklenme durumu
  `$script:ClientModulesLoaded` hashtable'ında izleniyor. Yüklenemeyen modül olduğunda
  wizard "graceful degrade" davranışına düşüyor (uyarı logu + yer tutucu sonuç).
- `ServerSetupUI.ps1` başlangıcına sunucu modülleri için `Import-Module` mantığı
  eklendi (RdsInstaller.ps1, CertificateManager.ps1, FirewallConfig.ps1,
  RDGatewayInstaller.ps1, RemoteAppPublisher.ps1, LicenseDetector.ps1,
  GuacamoleInstaller.ps1, TailscaleInstaller.ps1, CloudflareTunnelInstaller.ps1,
  AppScanner.ps1). Sunucu modüllerinin `Export-ModuleMember` tanımları olmadığı için
  dot-source kullanılıyor; her modülün yüklenme durumu `$script:ServerModules` hashtable'ında
  saklanıyor ve `Write-SetupLog` ile kayıt altına alınıyor. Mevcut `& $PSScriptRoot $a.Script`
  çağrıları (LicenseDetector, AppScanner) hâlâ fallback olarak çalışıyor.
- `Capture-Step3` artık `CheckedListBox.Items`'tan gelen orijinal PSCustomObject'leri
  `SelectedAppObjects` hashtable'ında saklıyor; `Start-ClientInstall` bu objeleri kullanarak
  `New-RdpFileForApps`, `New-WebShortcutBundle`, `Register-App` gibi fonksiyonları gerçek
  `alias`/`name`/`path` verisiyle çağırıyor.

### `apps.template.json` Çakışması — Çözüm

`src/config/client/` altında iki şablon dosyası var; amaçları farklı olduğu için ayrı tutulur:

| Dosya | Amaç | Aktif okuyan modül |
| --- | --- | --- |
| `apps.template.json` | Sunucudan RemoteApp tespiti başarısız olduğunda `ServerProbe.ps1`'in yüklediği **runtime fallback** şablonu (C1) | `ServerProbe.ps1` (`Get-ProbeFallbackApps`) |
| `apps.template.example.json` | Geliştiriciler için referans örnek (C2); aktif olarak okunmaz | Yok (sadece dokümantasyon) |

Her iki dosyanın `_comment`, `_role`, `_owner`, `_shares_namespace_with`, `_resolution`
alanlarıyla bu karar kapsam içinde belgelenmiştir. İleride örnek dosyada
geliştirme yapılırsa `apps.template.example.json` adı korunmalıdır; aktif şablonu
değiştirmek ServerProbe davranışını bozar.

### Eklenenler (Added)

#### Server-Side Modüller (`src/powershell/server/`)

| Modül | Açıklama |
| --- | --- |
| `RdsInstaller.ps1` | RDS rolleri kurulumu (Session Host, Web Access, Gateway, Licensing, Connection Broker). Alias tabanlı özellik adı çözümleme, otomatik rollback, management tools desteği. |
| `CertificateManager.ps1` | Self-signed sertifika üretimi (`New-SelfSignedCertificate`) veya CA-signed PFX import. RDP-Tcp dinleyicisine sertifika bağlama. |
| `RemoteAppPublisher.ps1` | RemoteApp koleksiyonu oluşturma, uygulama yayını, koleksiyon listesi. |
| `FirewallConfig.ps1` | TCP 3389 (RDP), 443 (RD Gateway), 8443 (Guacamole), 5985/5986 (WinRM) inbound kuralları. |
| `LicenseDetector.ps1` | RD Web lisansı tespiti (3 senaryo: lisans var / yok / grace period). Otomatik öneri motoru. |
| `GuacamoleInstaller.ps1` | Apache Guacamole fallback (JDK 17 + Tomcat 9 + guacd + MySQL). HTTPS port 8443, self-signed cert. |
| `AppScanner.ps1` | Sunucudaki .exe tarayıcı. Versiyon, ikon, kategori, tahmini boyut tespiti. |
| `ServerSetupUI.ps1` | 7 adımlı WinForms sihirbazı. Türkçe varsayılan, İngilizce fallback. Aero modern tasarım. |

#### Client-Side Modüller (`src/powershell/client/`)

| Modül | Açıklama |
| --- | --- |
| `ServerProbe.ps1` | WinRM ile sunucu tespiti. JSON formatlı sonuç, HTML5 endpoint tipi tespiti (RD Web / Guacamole). |
| `SetupUI.ps1` | 4 adımlı WinForms sihirbazı. Çoklu uygulama seçimi, Native / Web / Both bağlantı tipi. |
| `RdpBuilder.ps1` | `.rdp` dosyası şablon motoru. RD Gateway desteği, Tailscale IP routing, UTF-8 çıktı. |
| `WebShortcuts.ps1` | RD Web / Guacamole URL kısayolları (`.url`). PWA manifest üretimi. |
| `Credential.ps1` | Windows Credential Manager wrapper. Sunucu IP + uygulama kimliği tabanlı hedef anahtar. |
| `AppRegistry.ps1` | JSON tabanlı uygulama kayıt defteri. Register / Unregister / Update operasyonları. |
| `SelfTest.ps1` | Bağlantı test komutları. |

#### Bağlantı Stratejileri

Kurulum sırasında çoklu seçim destekli 5 strateji + 1 hybrid seçenek:

| Strateji | Port / Protokol | Gereksinim | Kullanım Senaryosu |
| --- | --- | --- | --- |
| **Direct RDP** | TCP 3389 | — | LAN, küçük ofis, NDA'lı ortam |
| **RD Gateway** | TCP 443 (HTTPS) | RD Web lisansı gerekebilir | Kurumsal, dışarıdan erişim, firewall dostu |
| **Apache Guacamole** | TCP 8443 (HTTPS) | JDK 17 + Tomcat 9 + MySQL | HTML5 erişim, RD Web lisansı yoksa fallback |
| **Tailscale** | UDP 41641 (mesh) | Cloud relay (ücretsiz tier) | Sıfır konfigürasyon, NAT arkası cihazlar |
| **Cloudflare Tunnel** | Outbound 443 | Cloudflare hesabı | Dışarıya port açmadan yayınlama |
| **Hybrid** | Çoklu port | Yukarıdakilerin kombinasyonu | Farklı kullanıcı tipleri için farklı erişim |

#### Installer (`src/inno/`)

- `RdpVirtualBoxApp-Client.iss` — Client Inno Setup wizard. PS1 modüllerini `%TEMP%\RdpVirtualBoxApp\` altına extract eder. ~5-8 MB çıktı.
- `RdpVirtualBoxApp-Server.iss` — Server Inno Setup. `PrivilegesRequired=admin`. `%ProgramFiles%\RdpVirtualBoxApp\` altına kurar. ~8-12 MB çıktı.

#### CI/CD (`.github/workflows/`)

- `build.yml` — `windows-latest` runner. PowerShell 7.4 + PSScriptAnalyzer + Pester + Inno Setup derleme. PR ve push'ta çalışır, artifact üretir.
- `release.yml` — Tag-based (`v*`) otomatik release. Client + Server artifact + SHA256SUMS yükler.
- `docs.yml` — GitHub Pages deploy. `docs/` değişikliklerinde ve manuel dispatch ile landing site yayınlar.

#### Dokümantasyon

- `README.md` — Proje özeti (Türkçe + İngilizce)
- `docs/server-requirements.md` — Donanım, yazılım, lisans gereksinimleri
- `docs/client-requirements.md` — Windows 10/11 istemci gereksinimleri
- `docs/server-setup-guide.md` — IT admin için 7 adımlı kılavuz
- `docs/client-setup-guide.md` — Son kullanıcı için 4 adımlı kılavuz
- `docs/licensing-and-rdweb.md` — RD Web Access vs Guacamole karşılaştırması
- `docs/troubleshooting.md` — Yaygın hatalar ve çözümler
- `docs/index.html` — GitHub Pages landing
- `docs/release-notes-v1.0.0.md` — v1.0.0 release notes taslağı

#### Testler

Pester 5 uyumlu birim testleri — `tests/` altında 7 dosya (~79 test case):

- `tests/client/test-server-probe.ps1`
- `tests/client/test-rdp-builder.ps1`
- `tests/client/test-app-registry.ps1`
- `tests/client/test-web-shortcuts.ps1`
- `tests/server/test-rds-installer.ps1`
- `tests/server/test-license-detector.ps1`
- `tests/server/test-guacamole-installer.ps1`

> Not: Toplam test case sayısı plan referansında **79** olarak belirtilmiştir. Bu sayı CI çıktısıyla doğrulanmalıdır; dosya başına test sayısı zamanla değişebilir.

### Değişenler (Changed)
Yok — ilk sürüm.

### Düzeltmeler (Fixed)
Yok — ilk sürüm.

### Kaldırılanlar (Removed)
Yok — ilk sürüm.

### Güvenlik (Security)

- Self-signed sertifika varsayılan: ilk bağlantıda tarayıcı/RDP istemcisi uyarı verir.
- Hassas veri: parolalar Credential Manager'a generic credential türünde yazılır, `.rdp` dosyasında düz metin bulunmaz.
- CA-signed PFX import desteklenir (üretim için önerilir).

### Bilinen Sınırlamalar (Known Limitations)

- **Platform** — macOS / Linux istemciler resmi olarak desteklenmiyor (yalnızca web modu, native RDP yok).
- **Test ortamı** — Otomatik test runner'da gerçek Windows Server yok; entegrasyon testleri kullanıcıya ertelenmiş.
- **Guacamole performansı** — Native RDP'den düşük olabilir (CAD, yüksek yenileme hızı gerektiren uygulamalarda).
- **Cloudflare Tunnel** — Ücretsiz tier bağlantı sınırı uygular.
- **Tailscale** — Ücretsiz tier 100 cihaz sınırı; DERP relay latency'si eklenir.
- **Hybrid yapılandırmalar** — Birden çok strateji birden seçilirse bakım/dokümantasyon karmaşıklığı artar.
- **Sunucu yeniden başlatma** — RDS rol kurulumu sonrası otomatik restart opsiyonel (`AutoRestart`).

### Upgrade / Migration
N/A — ilk sürüm. Önceki sürüm yok.

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

### v1.0.0 post-release code health pass (2026-08-19)

`fix(inno): fix parse errors (AppId braces, Format bracket) and remove dangerous registry uninstall entries` (2f97ef5)
- `src/inno/RdpVirtualBoxApp-Server.iss`: `AppId={8B6A8C2D-…}` → `AppId=8B6A8C2D-…`
  (süslü parantezler literal karakter değil, ISCC parser tarafından
  expression olarak yorumlanıyor ve parse hatasına neden oluyordu).
- `src/inno/RdpVirtualBoxApp-Server.iss`: Pascal `Format()` çağrısında
  `ExpandConstant('{#MyAppVersion}']` fazladan `]` nedeniyle bracket mismatch.
- `src/inno/RdpVirtualBoxApp-Server.iss`: `SetupIconFile` ve `[Files]` Source
  path'leri `src\inno\..\assets\…` → `src\assets\…` (repo root'a göre
  göreli). `OutputDir` da `build\output` olarak normalize edildi.
- `src/inno/RdpVirtualBoxApp-Client.iss`: `[UninstallDelete]` bölümünden
  `HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\ZoneMap`
  anahtarını silen satır kaldırıldı (kullanıcının Internet Explorer zone
  ayarlarını sıfırlıyordu). `__RDPVB_DELETE__` placeholder regkey de kaldırıldı.

`fix(powershell): fix real parse errors found by local pwsh parser` (fde34b8)
- `src/powershell/server/ServerSetupUI.ps1`: `.Add_CheckedChanged({…})` /
  `.Add_Click({…})` çağrıları parser reddettiği için kaldırıldı. Step-2
  checkbox/radio state'leri artık bir `Update-WizardDataFromStep2` yardımcı
  fonksiyonu ile Next handler'ında senkron okunuyor. License tespit
  butonu `.add_Click({ Invoke-LicenseDetectionButton })` ile çalışıyor.
- `src/powershell/server/AppScanner.ps1`: `$files.ForEach { $_ }` →
  `$files.ForEach({ $_ })` (parser strict modda tek argümanlı çağrı istiyor).
- `src/powershell/client/ServerProbe.ps1`: `$ComputerName:$Port` string
  interpolation'ı `${ComputerName}:${Port}` olarak escape edildi.
- Doğrulama: `pwsh` + `[System.Management.Automation.Language.Parser]` ile
  tüm 20 ps1 dosyası hatasız parse oluyor.

`fix(ci): disable cancel-in-progress on build workflow` (3845fba)
- `cancel-in-progress: true` her push'ta önceki run'ı iptal ediyordu;
  tüm run'lar 'Failure' (cancelled) görünüyordu ve gerçek build sonucunu
  göremiyorduk. Şimdi her run tamamlanıyor.

`ci(diagnose): auto-run on push/PR; always upload ISCC logs as artifact` (fc5eeee)
- `diagnose-iss.yml` artık workflow_dispatch yanında push + PR ile de
  tetikleniyor.
- `build.yml`'e `if: always()` ile ISCC + analyzer log'larını yükleyen
  bir `iscc-logs` artifact adımı eklendi (her zaman yüklenir, hata
  olsa bile).

---

[1.0.0]: https://github.com/ferhatdeveloper/VirtualAppRDP/releases/tag/v1.0.0
[Unreleased]: https://github.com/ferhatdeveloper/VirtualAppRDP/compare/v1.0.0...HEAD
