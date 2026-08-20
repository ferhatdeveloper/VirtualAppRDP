# macOS Client Kurulum Kilavuzu

Bu belge, **Rdp Virtual Box App - macOS Native Client** DMG'sini macOS bilgisayarlara kurma ve kullanma adimlarini anlatir.

> IT admin, server kurulumunu tamamladiktan ve sunucuda Probe REST API'sinin aktif oldugunu teyit ettikten sonra bu kilavuzu izleyin.

---

## Icindekiler

- [Gereksinimler](#gereksinimler)
- [DMG Kurulumu](#dmg-kurulumu)
- [Ilk Calistirma](#ilk-calistirma)
- [4 Adimlik Sihirbaz](#4-adimlik-sihirbaz)
- [Microsoft Remote Desktop Entegrasyonu](#microsoft-remote-desktop-entegrasyonu)
- [Kisayol Kullanimi](#kisayol-kullanimi)
- [Kaldirma](#kaldirma)
- [Sorun Giderme](#sorun-giderme)

---

## Gereksinimler

| Bilesen | Minimum | Notlar |
|---|---|---|
| **macOS** | 12.0 Monterey | 14.0 Sonoma veya 13.0 Ventura onerilir |
| **Microsoft Remote Desktop** | App Store son surumu | RDP baglantisi icin zorunlu |
| **Internet Explorer / Safari** | macOS ile gelir | Web Modu (HTML5) icin |
| **Baglanti** | LAN / VPN / internet | Sunucunun erisebilir olmasi gerekir |

> **Not:** DMG indirmek icin minimum 30 MB bos disk alani yeterlidir.

---

## DMG Kurulumu

### Adim 1: DMG'yi Indirin

IT admin'inizden veya GitHub Releases sayfasindan `RdpVirtualBoxApp-Client-macOS-vX.X.X.dmg` dosyasini indirin.

### Adim 2: DMG'yi Acip Kurun

1. Indirilen `.dmg` dosyasina **cift tiklayin**.
2. Acilan pencerede:
   ```
   Rdp Virtual Box App      Applications
   (soldaki .app)            (sagdaki kisayol)
   ```
3. `Rdp Virtual Box App` uygulamasini **Applications** klasorune **surukleyip birakin**.

### Adim 3: Microsoft Remote Desktop Kurulumu

1. **Mac App Store**'u acin.
2. **"Microsoft Remote Desktop"** aramasi yapin (gelistirici: Microsoft Corporation).
3. **"Get"** ile ucretsiz yukleyin.

> RDP baglantisi Microsoft Remote Desktop uzerinden saglanir. Bu uygulama yuklenmeden .rdp dosyalari acilamaz.

---

## Ilk Calistirma

ilk acilista Gatekeeper "acilamadi" uyarisi verebilir (imzasiz veya Apple tarafindan dogrulanmamis gelistirici oldugu icin). Bu durumda:

1. **System Settings → Privacy & Security** acin.
2. Asagi kaydirip **"Open Anyway"** / **"Yine de Ac"** butonuna tiklayin.
3. Sifre sorulursa macOS kullanici sifrenizi girin.

Bir sonraki acilista uygulama normal sekilde calisacaktir.

---

## 4 Adimlik Sihirbaz

Sihirbaz, Windows istemcisiyle ayni 4 adimi takip eder:

### 3.1 Sunucu Bilgisi

```
Sunucu IP:        192.168.0.106       (ornek)
Port:             3389                (RDP, varsayilan)
Kullanici adi:    FIRMA\kullanici     (veya kullanici@firma.local)
Parola:           ********
```

"Sunucuyu Tara" butonuna tiklayip **Probe REST API** uzerinden sunucu taramasi yapilir. macOS istemcisi WinRM kullanmaz; bunun yerine `http://<server>:8444/probe/api/probe` adresine Bearer token ile istek atar. Sonuclar tablo halinde gosterilir.

> **Onemli:** Sunucu tarafinda Probe REST API (port 8444) calisiyor olmalidir. IT admin `Start-ProbeApiHost.ps1 -Mode Install` ile kurar; token `%ProgramData%\RdpVirtualBoxApp\Config\probe-api.json` icindedir.

### 3.2 Server Probe Sonuclari

Bilesen durumu tablosu:

| Bilesen | Durum | Aciklama |
|---|---|---|
| RDS_Role | TAMAM | Rol kurulu |
| RD_SessionHost | TAMAM | Oturum ana bilgisayar aktif |
| RDP_Port | TAMAM | 3389 erisilebilir |
| RD_WebAccess | UYARI | HTML5 endpoint tespit edilmedi |
| RemoteApps | TAMAM | 3 uygulama yayinlanmis |

"Oneriler" bolumunde kritik eksik varsa IT admin ile iletisime gecin.

### 3.3 Uygulama ve Baglanti Tipi Secimi

1. **Uygulama listesi** (sunucudan gelen RemoteApp):
   ```
   [x] ERP Uygulamasi         (erp)
   [x] Raporlama              (rapor)
   [ ] Muhasebe               (muhasebe)
   ```
2. **Baglanti tipi**:
   - **Native (.rdp)** — Microsoft RDP.app ile calisir (onerilen)
   - **Web (HTML5)** — Safari ile tarayici
   - **Both** — Her ikisi
3. **Kimlik Bilgisi Yonetimi**:
   - **Her baglantida sor** — macOS Keychain'e yazilmaz
   - **macOS Keychain'e kaydet** — Guvenli saklama (onerilen)
   - **RDP dosyasina gom** — Onerilmez

### 3.4 Inceleme ve Install

Secimlerin ozeti gosterilir. "Kurulumu Baslat" butonu ile:

1. `.rdp` dosyalari `~/Documents/RdpVirtualBoxApp/` altina yazilir.
2. macOS Keychain'e parola kaydedilir (secildiyse).
3. `~/Library/Application Support/RdpVirtualBoxApp/apps.json` guncellenir.

Kurulum tamamlaninca uretilen dosyalarin listesi gosterilir.

---

## Microsoft Remote Desktop Entegrasyonu

SwiftUI wizard `rdp://` URL semasini kullanir. Ornek:

```
rdp://192.168.0.106:3389/%23|erp
```

Bu URL'yi alan **Microsoft Remote Desktop.app**:

1. Baglanti icin gereken `.rdp` dosyasini gecici olarak yaratir.
2. Parolayi Keychain'den okur.
3. RemoteApp penceresini acar.

`rdp://` URL'sinin **dogru calismasi icin** Microsoft Remote Desktop uygulamasinin yuklenmis olmasi zorunludur.

### Yerel RDP Dosyasi

Eger `.rdp` dosyasini manuel olarak acmak isterseniz:

1. **Finder → Documents → RdpVirtualBoxApp/**
2. `erp.rdp` uzerine cift tiklayin.
3. "Open With: Microsoft Remote Desktop" secin.

---

## Kisayol Kullanimi

### Spotlight

`Cmd + Space` ile **"Rdp Virtual Box App"** aratip calistirin.

### Applications Klasoru

`/Applications/Rdp Virtual Box App.app` uzerinden calistirin.

### Tekrar Calistirma

Sihirbaz son adimda kuruluma ek olarak, kurulu uygulamalari `~/Library/Application Support/RdpVirtualBoxApp/apps.json` dosyasinda takip eder. Ayni uygulamayi yeniden kurmak icin sihirbazi tekrar calistirip "Mevcut Kurulumlari Guncelle" secenegini kullanin.

---

## Kaldirma

### Uygulamayi Kaldirma

1. **/Applications/Rdp Virtual Box App.app**'i **Cope** klasorune surukleyin.
2. Kullanici sifrenizle onaylayin.

### Verileri Temizleme

Asagidaki dizinleri manuel silebilirsiniz:

```bash
rm -rf ~/Documents/RdpVirtualBoxApp/
rm -rf ~/Library/Application\ Support/RdpVirtualBoxApp/
# Keychain kayitlari:
security delete-generic-password -s RdpVirtualBoxApp
```

> Keychain kayitlari tek tek silmek isterseniz **Keychain Access** uygulamasinda `RdpVirtualBoxApp` aratabilirsiniz.

---

## Sorun Giderme

| Sorun | Cozum |
|---|---|
| "Microsoft Remote Desktop is not installed" | App Store'dan Microsoft Remote Desktop yukleyin |
| "Failed to open rdp://..." | `~/Documents/RdpVirtualBoxApp/erp.rdp` dosyasina sag tiklayip "Open With > Microsoft Remote Desktop" secin |
| Probe basarisiz (HTTP 401) | Sunucuda Bearer token gerekli; IT admin'den `RDPVB_PROBE_TOKEN` degerini isteyin |
| Probe basarisiz (HTTP 404) | Sunucuda Probe API (port 8444) calismiyor; `Start-ProbeApiHost.ps1 -Mode Install` |
| Self-signed sertifika uyarisi | RD Web / Guacamole HTTPS baglantisinda sertifika uyarisi normal; "Visit this website" ile devam edin |
| Keychain erisim izni soruyor | macOS sifrenizi girin veya Touch ID ile onaylayin |
| DMG acilmiyor | `xattr -d com.apple.quarantine /Applications/Rdp\ Virtual\ Box\ App.app` komutunu calistirin |

### Debug Loglari

`Console.app` (macOS ile gelir) uzerinden **"Rdp Virtual Box App"** filtresi ile loglari inceleyebilirsiniz.

---

## Gelistirici Notlari

Bu proje acik kaynaklidir; detayli gelistirme kilavuzu icin:

- [src/swift/RdpVirtualBoxApp/README.md](../src/swift/RdpVirtualBoxApp/) — Swift paket yapisi
- [../README.md](../README.md) — Proje genel bakis
- GitHub: <https://github.com/ferhatdeveloper/VirtualAppRDP>

---

## Ilgili Belgeler

- [client-requirements.md](client-requirements.md) — Istemci gereksinimleri
- [client-setup-guide.md](client-setup-guide.md) — Windows istemci kurulumu
- [macos-architecture.md](macos-architecture.md) — SwiftUI mimari kararlari (gelistiriciler icin)
- [troubleshooting.md](troubleshooting.md) — Genel sorun giderme