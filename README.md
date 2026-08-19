# Rdp Virtual Box App

> **Generic RemoteApp setup wizard** — Windows Server üzerinde herhangi bir uygulamayı (ERP, muhasebe, raporlama, özel exe vb.) RemoteApp olarak yayınlayın ve kullanıcılarınıza kolayca dağıtın.

[![Build Status](https://img.shields.io/badge/build-GitHub_Actions-blue?logo=github-actions)](https://github.com/ferhatdeveloper/VirtualAppRDP/actions)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![GitHub release](https://img.shields.io/badge/release-v1.0.0-blue)](https://github.com/ferhatdeveloper/VirtualAppRDP/releases)

---

## İki Parçalı Mimari

| Mod | Hedef | Çalıştırıldığı Yer | Yaptığı İşler |
|---|---|---|---|
| **Server-Side Setup** | Windows Server 2016/2019/2022 | Server üzerinde (elevated) | RDS rolleri, RD Gateway, RemoteApp koleksiyonu, sertifika, firewall |
| **Client-Side Setup** | Windows 10/11 (kullanıcı) | Kullanıcı makinesinde | `.rdp` dosyası, Start Menu kısayolu, Credential Manager, HTML5 URL |

> **Kurulum sırası:** Önce **sunucu** kurulur, sonra **istemci**.

## Bağlantı Stratejileri

Kurulum sırasında birden çok strateji seçilebilir:

| Strateji | Port | Senaryo |
|---|---|---|
| **Direct RDP** | TCP 3389 | LAN / NDA ortamı |
| **RD Gateway** | TCP 443 | Kurumsal, dışarıdan erişim |
| **Apache Guacamole** | TCP 8443 | RD Web lisansı yoksa HTML5 fallback |
| **Tailscale** | UDP 41641 (mesh) | NAT arkası, sıfır konfigürasyon |
| **Cloudflare Tunnel** | Outbound 443 | Dışarıya port açmadan yayınlama |
| **Hybrid** | Çoklu port | Birden çok strateji birlikte |

## Quick Start

### 1. Server tarafı (IT admin)

1. `RdpVirtualBoxApp-Server-vX.X.X.exe` indirin.
2. **Yönetici olarak** çalıştırın.
3. 7 adımlı wizard: Hoşgeldiniz → Bileşen → Lisans → Bağlantı Stratejisi → Uygulama → İnceleme → Kurulum.
4. Kurulum bittiğinde size bir **manifest** verir (client setup'a yapıştırılır).

### 2. Client tarafı (son kullanıcı)

1. `RdpVirtualBoxApp-Client-vX.X.X.exe` indirin ve çalıştırın.
2. Server IP + kullanıcı bilgisi girin.
3. ServerProbe otomatik sunucuyu tarar.
4. Yayınlanan uygulamaları seçin.
5. `.rdp` dosyaları, Start Menu kısayolları ve opsiyonel Credential Manager kaydı otomatik oluşur.

## Build

Yerel makinede (Windows + Inno Setup) veya GitHub Actions üzerinden:

```powershell
# PSScriptAnalyzer
Invoke-ScriptAnalyzer -Path ./src -Recurse

# Pester
Invoke-Pester -Path ./tests -Output Detailed

# Inno Setup ile build
ISCC.exe src\inno\RdpVirtualBoxApp-Client.iss
ISCC.exe src\inno\RdpVirtualBoxApp-Server.iss
```

CI/CD: Her push / PR'da `.github/workflows/build.yml` otomatik çalışır. Tag push'unda (örn. `v1.0.0`) `.github/workflows/release.yml` tetiklenir ve GitHub Releases'e artifact yüklenir.

## Proje Yapısı

```
.
├── .github/
│   ├── workflows/
│   │   ├── build.yml            # Build pipeline
│   │   └── release.yml          # Tag → Release draft
│   ├── ISSUE_TEMPLATE/
│   ├── PULL_REQUEST_TEMPLATE.md
│   └── CODEOWNERS
├── src/
│   ├── inno/                    # Inno Setup betikleri
│   ├── powershell/
│   │   ├── client/              # Client modülleri
│   │   └── server/              # Server modülleri
│   ├── config/                  # Şablon dosyaları
│   └── assets/                  # İkon, banner
├── tests/                       # Pester testleri
├── docs/                        # Kılavuzlar
├── build/                       # Build çıktıları (gitignore)
├── README.md
├── LICENSE                      # MIT
├── SECURITY.md
└── CHANGELOG.md
```

## Gereksinimler

**Server** (otomatik tespit edilir):
- Windows Server 2016/2019/2022
- 8 GB RAM min (Guacamole ile +4 GB)
- Active Directory üyesi veya workgroup
- WinRM aktif

**Client**:
- Windows 10 1809+ / Windows 11
- .NET 4.7.2+
- RDP istemcisi (built-in `mstsc.exe`)

## Dokümantasyon

Detaylı kılavuzlar için `docs/` klasörüne bakın:

- [`docs/server-requirements.md`](docs/server-requirements.md)
- [`docs/client-requirements.md`](docs/client-requirements.md)
- [`docs/server-setup-guide.md`](docs/server-setup-guide.md)
- [`docs/client-setup-guide.md`](docs/client-setup-guide.md)
- [`docs/troubleshooting.md`](docs/troubleshooting.md)
- [`docs/licensing-and-rdweb.md`](docs/licensing-and-rdweb.md)

## Güvenlik

Güvenlik açıkları için lütfen [SECURITY.md](SECURITY.md) dosyasına bakın — public issue açmayın.

## Lisans

MIT — Detaylar için [LICENSE](LICENSE).

## Katkıda Bulunma

PR açmadan önce [PULL_REQUEST_TEMPLATE.md](.github/PULL_REQUEST_TEMPLATE.md) dosyasını doldurun. Tüm PR'lar CODEOWNERS onayı gerektirir.

---

**Repository:** https://github.com/ferhatdeveloper/VirtualAppRDP