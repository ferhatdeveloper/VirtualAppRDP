# Changelog

Tüm önemli değişiklikler bu dosyada belgelenir. Format [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) standardına uygundur ve bu proje [Semantic Versioning](https://semver.org/spec/v2.0.0.html) kullanır.

## [Unreleased]

### Planlanan
- Apache Guacamole installer (S3 ajanı)
- Tailscale mesh VPN installer (S3 ajanı)
- Cloudflare Tunnel installer (S3 ajanı)
- Client WinForms wizard (C3 ajanı)
- Pester testleri (C5 ajanı)
- Detaylı dokümantasyon (C5 ajanı)

## [1.0.0] — 2026-08-19

### Eklenen
- İlk sürüm (initial commit)
- **Server-side setup**: Windows Server'da RDS rolleri, RD Web Access, RD Gateway, sertifika yönetimi, RemoteApp yayınlama, firewall kuralları
- **Client-side setup**: WinForms 4 adımlı sihirbaz, ServerProbe (WinRM tabanlı tespit), `.rdp` üretici, Credential Manager entegrasyonu, HTML5 kısayolları
- **Bağlantı stratejileri**: Direct / RD Gateway / Apache Guacamole / Tailscale / Cloudflare / Hybrid (çoklu seçim)
- **Dinamik uygulama listesi**: Sunucudan `Get-RDRemoteApp` ile çekilir
- **Inno Setup betikleri**: Client ve Server için ayrı ayrı
- **GitHub Actions CI**:
  - `build.yml` — push / PR / manuel tetikleme ile derleme + test + artifact
  - `release.yml` — `v*` tag'i ile draft release oluşturma
- **Repo altyapısı**: `.gitignore`, `LICENSE`, `SECURITY.md`, issue/PR şablonları, CODEOWNERS