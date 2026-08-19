# Client Kurulum Kılavuzu

Bu belge, **son kullanıcılar** için **Rdp Virtual Box App — Client Setup** EXE'sini çalıştırma adımlarını açıklar.

> IT admin, server kurulumunu tamamladıktan ve gerekli bilgileri size ilettikten sonra bu kılavuzu izleyin.

---

## İçindekiler

- [Gerekli Bilgiler](#gerekli-bilgiler)
- [Adım 1: Setup İndirme](#adım-1-setup-indirme)
- [Adım 2: Setup Çalıştırma](#adım-2-setup-çalıştırma)
- [Adım 3: 4 Adımlı Sihirbaz](#adım-3-4-adımlı-sihirbaz)
  - [3.1 Sunucu Bilgisi](#31-sunucu-bilgisi)
  - [3.2 Server Probe Sonuçları](#32-server-probe-sonuçları)
  - [3.3 Uygulama ve Bağlantı Tipi Seçimi](#33-uygulama-ve-bağlantı-tipi-seçimi)
  - [3.4 İnceleme ve Install](#34-inceleme-ve-install)
- [Kısayol Kullanımı](#kısayol-kullanımı)
- [Sorun Giderme](#sorun-giderme)

---

## Gerekli Bilgiler

IT admin'den aşağıdaki bilgileri alın:

| Bilgi | Örnek | Açıklama |
|---|---|---|
| **Sunucu IP / FQDN** | `192.168.0.106` veya `rdp.firma.local` | RDP sunucusunun adresi |
| **RDP Port** | `3389` | Genellikle varsayılan; değiştirilmediyse boş bırakın |
| **Domain** | `FIRMA` veya `firma.local` | Domain üyesiyseniz; workgroup'ta boş bırakın |
| **Kullanıcı adı** | `kullanici` veya `kullanici@firma.local` | RDP giriş hesabı |
| **Parola** | `********` | RDP parolanız |
| **Web URL** *(opsiyonel)* | `https://rdp.firma.local/RDWeb/webclient` | HTML5 erişim için (admin verebilir) |

---

## Adım 1: Setup İndirme

1. IT admin veya şirket paylaşımından `RdpVirtualBoxApp-Client-vX.X.X.exe` dosyasını indirin.
2. Dosyayı masaüstüne veya `C:\Temp\` altına kaydedin.

> Alternatif olarak doğrudan çalıştırılabilir; indirme gerekmez.

---

## Adım 2: Setup Çalıştırma

1. EXE'ye sağ tıklayın → **"Run as administrator"** (önerilir; bazı bileşenler için gereklidir).
2. UAC onayını verin.
3. Açılan pencerede **"Install"** butonuna basın.

Kurulum EXE'si şu dizine dosyaları çıkarır:
```
%TEMP%\RdpVirtualBoxApp\
├── SetupUI.ps1
├── ServerProbe.ps1
├── RdpBuilder.ps1
├── WebShortcuts.ps1
├── Credential.ps1
└── AppRegistry.ps1
```

WinForms wizard otomatik olarak açılır.

---

## Adım 3: 4 Adımlı Sihirbaz

### 3.1 Sunucu Bilgisi

İlk adımda şu alanları doldurun:

| Alan | Değer |
|---|---|
| **Server IP / FQDN** | `192.168.0.106` veya `rdp.firma.local` |
| **Port** | `3389` (varsayılan) |
| **Domain** | Boş veya `FIRMA` |
| **Kullanıcı adı** | `kullanici` |
| **Parola** | `********` |

**"İleri"** butonuna basın. Setup arka planda sunucuyu WinRM ile sorgular.

### 3.2 Server Probe Sonuçları

Setup, sunucuyu otomatik olarak analiz eder ve aşağıdaki gibi bir durum gösterir:

```
✅ Sunucu:           Erişilebilir
✅ WinRM:            Açık
✅ RDS Rolü:         Kurulu
✅ RD Session Host:  Kurulu
⚠️  RD Gateway:      Kurulu değil (öneri: kurun)
✅ RD Web Access:    Kurulu
✅ RDP Port 3389:    Açık
⚠️  Sertifika:        Self-signed (tarayıcı uyarısı normal)
✅ RemoteApp'lar:    3 uygulama yayınlanmış
```

**Yeşil:** Hazır, sorun yok.
**Sarı:** Opsiyonel; varsayılan ayarlarla devam edebilirsiniz.
**Kırmızı:** Kritik eksik; admin ile iletişime geçin.

> Eğer tüm bileşenler kırmızıysa (sunucu hiç kurulmamış), setup yine de devam eder — yalnızca native RDP kullanılabilir olur.

**"İleri"** ile devam edin.

### 3.3 Uygulama ve Bağlantı Tipi Seçimi

Bu adımda:

1. **Uygulamalar** listesi (sunucudan otomatik çekilir):
   ```
   ☐ ERP Uygulaması        (erp.exe)
   ☐ Raporlama             (reports.exe)
   � Muhasebe              (accounting.exe)
   ☑ Notepad               (notepad.exe)   ← seçili
   ```
   Birden fazla uygulama seçebilirsiniz; her biri için ayrı `.rdp` ve kısayol üretilir.

2. **Bağlantı tipi** seçin:
   - **Native (.rdp)** — Windows RDP istemcisiyle (mstsc.exe) açılır.
   - **Web (HTML5)** — Tarayıcıdan açılır (RD Web veya Guacamole).
   - **Both** — Her ikisi de üretilir.

3. **Credential Manager'a kaydet:** şifrenizi Windows Credential Manager'a kaydetmek istiyorsanız işaretleyin (önerilir).

**"İleri"** ile devam edin.

### 3.4 İnceleme ve Install

Son adımda yapılacak işlemler özetlenir:

```
Sunucu:               192.168.0.106
Kullanıcı:            FIRMA\kullanici
Seçili Uygulamalar:   ERP, Raporlama
Bağlantı Tipi:        Both (Native + Web)
Credential Manager:   ✅ Etkin
Çıktı Klasörü:        C:\Users\Kullanici\Documents\RdpVirtualBoxApp\
Start Menu:           ✅ Kısayollar oluşturulacak
```

**"Install"** butonuna basın. Setup arka planda:

1. `.rdp` dosyalarını üretir (`RdpBuilder.ps1`).
2. HTML5 URL'lerini kontrol eder (`WebShortcuts.ps1`).
3. Credential Manager'a kullanıcıyı kaydeder (`Credential.ps1`).
4. Start Menu kısayollarını oluşturur.
5. Test bağlantısı yapar.

İşlem tamamlandığında "Kurulum başarılı" mesajı görürsünüz.

---

## Kısayol Kullanımı

### Start Menu

**Start → Rdp Virtual Box App** altında seçtiğiniz her uygulama için bir kısayol bulunur:

```
📂 Rdp Virtual Box App
├── 📄 ERP Uygulaması
├── 📄 Raporlama
├── 🌐 ERP (Web)
└── 🌐 Raporlama (Web)
```

`.rdp` kısayolu → mstsc.exe ile RDP bağlantısı kurar.
`Web` kısayolu → varsayılan tarayıcıyı açar.

### Masaüstü Kısayolları

Setup masaüstüne de kısayol koyabilir (Inno Setup'taki seçime bağlı).

### Çıktı Dosyaları

Tüm üretilen dosyalar şu klasördedir:

```
%USERPROFILE%\Documents\RdpVirtualBoxApp\
├── erp.rdp
├── reports.rdp
└── web\
    ├── erp.url
    └── reports.url
```

---

## Yeni Uygulama Ekleme

Yeni bir RemoteApp yayınlandığında:

1. Setup'ı tekrar çalıştırın.
2. Aynı sunucu bilgisini girin.
3. Uygulama listesinde yeni uygulamayı görün ve seçin.
4. Install ile yeni `.rdp` üretin.

> Eski `.rdp` dosyaları silinmez; gereksiz olanları manuel silebilirsiniz.

---

## Kaldırma

**Settings → Apps → Rdp Virtual Box App → Uninstall** yolunu kullanın.

Kaldırma sırasında:
- `%USERPROFILE%\Documents\RdpVirtualBoxApp\` klasörü temizlenir.
- Start Menu kısayolları kaldırılır.
- Credential Manager'daki kayıtlar temizlenir.
- **Sunucudaki RemoteApp koleksiyonu etkilenmez.**

---

## Sorun Giderme

Yaygın hatalar ve çözümleri için: [troubleshooting.md](troubleshooting.md)

Hızlı kontroller:

| Sorun | Kontrol |
|---|---|
| `.rdp` açılmıyor | Dosya sağ tık → "Bağlantıyı aç" ile deneyin |
| Sertifika uyarısı | İlk seferde "Bağlantıyı kabul et" + "Sertifika güvenilir" işaretleyin |
| Credential hatası | Credential Manager → Windows Credentials → "RdpVirtualBoxApp:..." girişini silin, tekrar kaydedin |
| Web URL çalışmıyor | Tarayıcı önbelleğini temizleyin, farklı tarayıcı deneyin |
| Uygulama görünmüyor | Server Setup'ın tamamlandığını admin'den teyit edin, AppScanner'ı yeniden çalıştırın |

---

## İlgili Belgeler

- [client-requirements.md](client-requirements.md)
- [troubleshooting.md](troubleshooting.md)
- [../README.md](../README.md)
