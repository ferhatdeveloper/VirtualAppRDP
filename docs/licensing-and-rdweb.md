# Lisanslama ve RD Web Access / Guacamole Karşılaştırması

Bu belge, **RD Web Access** ile **Apache Guacamole** arasındaki farkları, lisanslama stratejilerini, maliyet/performans/güvenlik karşılaştırmasını açıklar.

---

## İçindekiler

- [RD Web Access Lisansı Nasıl Alınır](#rd-web-access-lisansı-nasıl-alınır)
- [Grace Period Açıklaması](#grace-period-açıklaması)
- [Apache Guacamole Nedir](#apache-guacamole-nedir)
- [Ne Zaman Hangisi Tercih Edilir](#ne-zaman-hangisi-tercih-edilir)
- [Maliyet Karşılaştırması](#maliyet-karşılaştırması)
- [Performans Karşılaştırması](#performans-karşılaştırması)
- [Güvenlik Karşılaştırması](#güvenlik-karşılaştırması)
- [Karar Matrisi](#karar-matrisi)

---

## RD Web Access Lisansı Nasıl Alınır

### Adım 1 — RDS CAL'i Edinin

Microsoft Volume Licensing Service Center'dan (VLSC) veya bir Microsoft Licensing Partner'dan:

| Tür | Açıklama | Fiyat (yaklaşık) |
|---|---|---|
| **RDS CAL (User)** | Adlandırılmış kullanıcı başına | ~$100 / kullanıcı (5 yıl) |
| **RDS CAL (Device)** | Cihaz başına | ~$50 / cihaz (5 yıl) |

> 2022 itibarıyla Microsoft, **User CAL**'i önermektedir.

### Adım 2 — License Server Kurulumu

1. **RDS-Licensing** rolünü kurun (Server Setup sihirbazı otomatik kurar).
2. License Manager'ı (`licmgr.exe`) açın.
3. **"Activate server now"** seçeneğini tıklayın.
4. Aktivasyon yöntemini seçin:
   - **Web browser** (önerilen) → Microsoft hesabıyla giriş yapın.
   - **Telephone** → Microsoft çağrı merkezini arayın.
5. **License server ID** not alın (sonradan gerekli).

### Adım 3 — RD Session Host'a Lisans Sunucusunu Tanıtın

```powershell
# Lisans sunucusunu RD Session Host'a ekleyin
$obj = gwmi -namespace "Root\cimv2" -class "Win32_TSProductKey" -Filter "Index = 0"
$obj.SetSpecifiedLicenseServerList("lic.firma.local")
```

Veya Group Policy ile:
```
Computer Configuration
  └ Administrative Templates
    └ Windows Components
      └ Remote Desktop Services
        └ Remote Desktop Session Host
          └ Licensing
            ├ Use the specified Remote Desktop license servers = lic.firma.local
            └ Set the Remote Desktop licensing mode = Per User (or Per Device)
```

### Adım 4 — Lisansları Yükleyin

License Manager → Server activation → Install Licenses → Lisans anahtarını girin.

---

## Grace Period Açıklaması

**120 günlük grace period**, RD Web Access'in Microsoft tarafından sağlanan "deneme süresi"dir.

| Gün | Davranış |
|---|---|
| 0-120 | RD Web çalışır, lisans uyarısı verilir |
| 120 | RD Web bağlantıları kesilir, kullanıcı RDP native ile devam edebilir |

### Grace Period Nasıl Tespit Edilir

`LicenseDetector.ps1` registry anahtarını okur:

```
HKLM:\SYSTEM\CurrentControlSet\Services\TermService\Parameters\License\
    GracePeriod         (REG_DWORD)
    RemainingGracePeriodDays (REG_DWORD)
    LlsGracePeriod      (REG_DWORD)
```

Eğer bu anahtarlar yoksa veya `0` ise, grace period aktif değildir.

### Grace Period Sonrası Seçenekler

| Seçenek | Efor |
|---|---|
| RDS CAL satın al | Kolay, ~$100 / kullanıcı |
| **Apache Guacamole kur** | Ücretsiz, ~15-25 dakika iş |
| Hibrit: Native RDP + Guacamole | Her ikisi birden |

> Server Setup sihirbazı, grace period tespit edildiğinde **otomatik olarak Guacamole kurulumunu önerir**.

---

## Apache Guacamole Nedir

**Apache Guacamole**, RDP / VNC / SSH bağlantılarını **HTML5 üzerinden** sunan clientless gateway'dir. Tarayıcıda çalışır, istemci yazılımı gerektirmez.

### Bileşenler

```
┌─────────────────┐
│ Web Tarayıcı    │   (Edge/Chrome/Firefox)
└────────┬────────┘
         │ HTTPS 8443
         ▼
┌─────────────────┐
│ Apache Tomcat 9 │   (Servlet container)
│  + Guacamole.war│   (Web uygulaması)
└────────┬────────�
         │ localhost:4822
         ▼
┌─────────────────┐
│ guacd (daemon)  │   (RDP protokolü tercümanı)
└────────┬────────┘
         │ TCP 3389
         ▼
┌─────────────────┐
│ RDP Server      │
└─────────────────┘

     ┌─────────────┐
     │ MySQL 8     │   (Kullanıcı/bağlantı veritabanı)
     └─────────────┘
```

### Kurulum Adımları (özet)

1. JDK 17 (~200 MB)
2. Apache Tomcat 9.x (~30 MB)
3. MySQL / MariaDB 8 (~500 MB)
4. guacd daemon (~50 MB)
5. guacamole.war (~50 MB) Tomcat'e deploy
6. Veritabanı şema import
7. Firewall 8443 aç
8. Self-signed cert (HTTPS)

**Toplam disk:** ~1.5 GB
**Toplam süre:** ~15-25 dakika
**Toplam maliyet:** $0 (Apache 2.0 lisansı)

### Lisans

Apache License 2.0 — tamamen ücretsiz, ticari kullanıma açık.

---

## Ne Zaman Hangisi Tercih Edilir

| Senaryo | Öneri | Neden |
|---|---|---|
| **Kurumsal, 50+ kullanıcı, bütçe var** | RD Web Access | Tam Microsoft entegrasyonu, SSO, GP yönetimi |
| **KOBİ, lisans bütçesi yok** | Apache Guacamole | $0 maliyet, hızlı kurulum |
| **Sadece ofis içi, RDP native yeterli** | Hiçbiri (Direct RDP) | Karmaşıklık gereksiz |
| **Macbook / iPad kullanıcıları** | Guacamole | Tarayıcı tabanlı, native RDP yok |
| **Yüksek çözünürlük gerektiren uygulamalar** | RD Web Access | Performans daha iyi |
| **Güvenlik açısından hassas ortam** | RD Web Access | Microsoft'un audit / compliance araçları |
| **Hibrit ortam (lisanslı + lisanssız)** | RD Web Access + Guacamole birlikte | En esnek |

---

## Maliyet Karşılaştırması

### 25 Kullanıcı için 5 Yıllık Toplam Sahip Olma Maliyeti (TCO)

| Bileşen | RD Web Access | Apache Guacamole |
|---|---|---|
| **Yazılım lisansı** | 25 × $100 (User CAL) = **$2,500** | **$0** |
| **Sunucu lisansı** | Windows Server (zaten var) | Windows Server (zaten var) |
| **Ek yazılım** | Yok | JDK + Tomcat + MySQL (ücretsiz) |
| **Ek disk** | ~5 GB (RDS rolleri) | ~5 GB + 1.5 GB (Guacamole) = 6.5 GB |
| **Ek RAM** | ~2 GB (RDS rollerinin overhead'i) | ~4 GB (Tomcat + MySQL + guacd) |
| **Sertifika** | CA-signed ($0 - $200/yıl) | Self-signed (ücretsiz) |
| **Eğitim / yönetim** | ~2 saat | ~4 saat (Java bilgisi gerekir) |
| **5 yıllık toplam** | **~$2,500 + 2 saat iş** | **$0 + 4 saat iş** |

> **Önemli:** Kullanıcı sayısı arttıkça RD Web Access'in lisans maliyeti lineer büyürken Guacamole maliyeti sabit kalır.

### 100 Kullanıcı

| | RD Web | Guacamole |
|---|---|---|
| 5 yıllık lisans | ~$10,000 | **$0** |
| Ek sunucu ihtiyacı | Belki | Önerilir (yük dengeleme için) |

### Break-even

RDP lisansı almak genellikle **şu durumlarda** mantıklıdır:
- Zaten Microsoft Volume Licensing anlaşmanız varsa.
- Kurumsal SSO / Group Policy zorunluluğu varsa.
- Compliance (denetim) gereksinimleri varsa.

Diğer durumlarda **Guacamole** daha ekonomiktir.

---

## Performans Karşılaştırması

### Benchmark Tipik Değerler (1080p, 30 fps)

| Metrik | RD Web Access | Guacamole |
|---|---|---|
| **Latency (LAN)** | 30-50 ms | 50-90 ms |
| **Latency (WAN)** | 80-150 ms | 150-300 ms |
| **Frame rate** | 30-60 fps | 20-30 fps |
| **CPU kullanımı (sunucu)** | %5-10 / kullanıcı | %10-20 / kullanıcı |
| **Bant genişliği** | 1-3 Mbps | 2-5 Mbps |
| **Ses kalitesi** | Yüksek (RDP ses yönlendirme) | Orta (WebRTC Opus) |

### Nerede Performans Farkı Belirginleşir

| Uygulama | RD Web | Guacamole |
|---|---|---|
| **Ofis (Word, Excel)** | ⭐⭐⭐⭐⭐ | �⭐⭐⭐ |
| **ERP (muhasebe)** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ |
| **CAD / 3D** | ⭐⭐⭐⭐ | ⭐⭐ (yetersiz) |
| **Video playback** | ⭐⭐⭐⭐ | ⭐⭐ |
| **Yüksek yenileme (oyun)** | ⭐⭐⭐ | � |

> Yüksek çözünürlük / yüksek yenileme gerektiren uygulamalar için **Guacamole yetersiz** kalabilir.

### Ayarlanabilir Parametreler

**RD Web Access:**
- RemoteFX codec
- UDP transport
- Multi-monitor

**Guacamole:**
- Image/compression mode (PNG / JPEG)
- Framerate limit
- Read-only mode

---

## Güvenlik Karşılaştırması

| Özellik | RD Web Access | Guacamole |
|---|---|---|
| **Şifreleme (transport)** | TLS 1.2+ | TLS 1.2+ |
| **Şifreleme (uçtan uca)** | RDP CredSSP / NLA | RDP CredSSP (guacd ↔ RDP) |
| **SSO (Active Directory)** | ✅ Doğal | ⚠️ LDAP modülü gerekli |
| **MFA desteği** | ✅ (RDS + Azure MFA) | ✅ (TOTP modülü) |
| **Session recording** | ✅ (GPO) | ✅ (Session recording extension) |
| **IP allowlist** | ✅ (RD Gateway CAP/RAP) | ⚠️ Reverse proxy üzerinden |
| **Audit log** | ✅ (Windows Event Log) | ✅ (syslog + DB) |
| **Brute-force koruması** | ✅ (NLA) | �️ Fail2ban + reverse proxy |

### Güvenlik Açısından Öneriler

**RD Web Access:**
- CA-signed sertifika kullanın (Let's Encrypt olur).
- RD Gateway üzerinden yayınlayın (CAP/RAP ile IP kısıtlayın).
- NLA (Network Level Authentication) zorunlu tutun.

**Guacamole:**
- Reverse proxy (nginx) önüne koyun.
- Let's Encrypt ile sertifika yenileyin.
- Veritabanı şifrelerini güçlü tutun.
- `guacadmin` varsayılan şifresini **mutlaka** değiştirin.
- LDAP / 2FA modülü kurun.

---

## Karar Matrisi

Aşağıdaki tabloyu kullanarak kararınızı netleştirin:

| Soru | Cevap | Öneri |
|---|---|---|
| Bütçe var mı? | Evet | RD Web Access |
| Bütçe var mı? | Hayır | Guacamole |
| Kurumsal SSO gerekli mi? | Evet | RD Web Access |
| Cross-platform (Mac/iPad/Linux) kullanıcı var mı? | Evet | Guacamole |
| Yüksek performans gerekli mi? (CAD, video) | Evet | RD Web Access |
| Hızlı kurulum mu önemli? | Evet | Guacamole |
| Compliance / denetim gerekiyor mu? | Evet | RD Web Access |
| Küçük ofis / KOBİ? | Evet | Guacamole |

### Önerilen Varsayılan

Çoğu durumda **hibrit yaklaşım** idealdir:

1. **RD Web Access'i kur** (zaten RDS rolleri kurulu).
2. **Guacamole'ı yan yedek olarak kur** (lisans yenilenmezse devreye girer).
3. **Direct RDP'yi ofis içi bırak**, dışarıdan erişim için **RD Gateway** veya **Guacamole** kullan.

Bu yapı hem esneklik hem maliyet optimizasyonu sağlar.

---

## İlgili Belgeler

- [server-requirements.md](server-requirements.md) — Donanım gereksinimleri
- [server-setup-guide.md](server-setup-guide.md) — Kurulum adımları
- [troubleshooting.md](troubleshooting.md) — Yaygın hatalar
