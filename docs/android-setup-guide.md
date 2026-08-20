# Android Client Kurulum Kilavuzu

Bu belge, **EXFIN RemoteAPP** Android istemcisini derleme, kurma ve Windows Server Probe API'sine baglama adimlarini anlatir.

> IT admin, sunucu kurulumunu tamamladiktan ve Probe REST API'nin (TCP **8444**) acik oldugunu teyit ettikten sonra bu kilavuzu izleyin.

---

## Icindekiler

- [Gereksinimler](#gereksinimler)
- [APK'yi derleme](#apkyi-derleme)
- [Play Store imzasi](#play-store-imzasi)
- [Telefona kurulum](#telefona-kurulum)
- [4 adimlik sihirbaz](#4-adimlik-sihirbaz)
- [Microsoft Remote Desktop](#microsoft-remote-desktop)
- [Ag ve NAT](#ag-ve-nat)
- [Sorun giderme](#sorun-giderme)

---

## Gereksinimler

| Bilesen | Minimum | Notlar |
|---|---|---|
| **Android** | 8.0 (API 26) | 12+ onerilir |
| **Microsoft Remote Desktop** | Play Store son surumu | `.rdp` acmak icin zorunlu (paket: `com.microsoft.rdc.androidx`) |
| **Ag** | LAN / VPN / internet | Probe API'ye erisim (HTTP 8444) |
| **Derleme (yalniz gelistirici)** | Android Studio Ladybug + JDK 17 | Son kullanici APK kurar |

Kaynak: `src/android/ExfinRemoteApp/`

---

## APK'yi derleme

1. [Android Studio](https://developer.android.com/studio) yukleyin.
2. **Open** ile `src/android/ExfinRemoteApp` klasorunu acin.
3. Gradle senkronu bitsin.
4. **Build > Build Bundle(s) / APK(s) > Build APK(s)** (debug) veya **Generate Signed Bundle / APK** (dagitim).
5. Cikti:
   - Debug: `app/build/outputs/apk/debug/app-debug.apk`
   - Release: `app/build/outputs/apk/release/app-release-unsigned.apk` (imza yoksa)

Komut satiri (JDK 17 + Android SDK gerekir):

```powershell
cd src\android
.\build-apk.ps1              # imzasiz veya keystore varsa imzali APK
.\build-apk.ps1 -Bundle      # Play Store AAB
.\build-apk.ps1 -DebugApk    # debug APK
```

GitHub Actions `build-android` isi de APK uretir (`continue-on-error`; Windows kurucularini bozmaz).

---

## Play Store imzasi

Repoya keystore **konmaz**. Yerel upload anahtari:

```powershell
cd src\android
.\New-ReleaseKeystore.ps1
```

`%USERPROFILE%\.exfin\exfin-upload.jks` ve gitignored `ExfinRemoteApp\keystore.properties` olusur. Ardından `.\build-apk.ps1 -Bundle` Play Console'a yuklenecek `.aab` uretir.

CI / baska makine icin ortam degiskenleri: `EXFIN_KEYSTORE_FILE`, `EXFIN_KEYSTORE_PASSWORD`, `EXFIN_KEY_ALIAS`, `EXFIN_KEY_PASSWORD`.

Sablon: `src/android/ExfinRemoteApp/keystore.properties.template`

JKS'yi yedekleyin. Kaybederseniz ayni paket adiyla guncelleme yayinlayamazsiniz.

---

## Telefona kurulum

1. APK'yi cihaza kopyalayin (USB, Drive, dahili indirme).
2. **Bilinmeyen kaynaklardan kurulum** iznini verin.
3. APK'ya dokunup **EXFIN RemoteAPP**'i kurun.
4. Play Store'dan **Microsoft Remote Desktop** (veya Windows App) yukleyin.

---

## 4 adimlik sihirbaz

Windows ve macOS istemcisiyle ayni mantik:

1. **Sunucu** — IP veya DNS, Probe portu (varsayilan **8444**), Windows kullanici adi, istege bagli Bearer token. HTTPS kutusu yalnizca gercek sertifika (Let's Encrypt) varsa.
2. **Tarama** — `GET /health`, `GET /api/apps`, `GET /rdp`. Sunucu adi, surum, RDP portu ve musteri listesi.
3. **Uygulama** — yayinli RemoteApp kartlari + Public / LAN / VPN hedefi.
4. **Baglan** — `POST /api/clients` ile cihaz kaydi, `.rdp` indirme, Microsoft RD Client ile acma.

**Web portalini ac** dugmesi `http://<sunucu>:8444/download` yonetim panelini tarayicida acar (yonetici icin).

Windows parolasi uygulamada saklanmaz; RDP istemcisi sorar.

---

## Microsoft Remote Desktop

RDP oturumu bu uygulamada gomulu degildir. EXFIN, sunucudan `.rdp` alir ve Microsoft istemcisine verir.

Play Store: [Microsoft Remote Desktop](https://play.google.com/store/apps/details?id=com.microsoft.rdc.androidx)

Yuklu degilse 4. adimda uyari ve magaza baglantisi gorunur.

---

## Ag ve NAT

| Hedef | Adres | Port |
|---|---|---|
| Probe / panel | LAN IP veya genel IP | **8444** HTTP |
| Caddy HTTPS (opsiyonel) | ayni | **8445** — ic CA Android'de guvenilmez; HTTP 8444 kullanin |
| RDP (LAN) | `lanIp` | `lanRdpPort` / dinleme portu |
| RDP (WAN) | `publicIp` | musterinin `rdpPort` degeri (NAT) |

Yoneticinin **Istemciler** sekmesinde `requireApproval` aciksa, WAN uzerinden `.rdp` almak icin cihazin **Izin ver** ile onaylanmasi gerekir. Android `ANDROID_ID` + kullanici adi ile kaydolur.

---

## Sorun giderme

| Belirti | Olası neden | Cozum |
|---|---|---|
| Tarama zaman asimi | 8444 kapali / NAT yok | Sunucuda Probe API, guvenlik duvari, modem NAT |
| `HTTP 403 client_not_approved` | Onay zorunlu | Panel > Istemciler > Izin ver |
| `.rdp` acilmiyor | RD Client yok | Play Store'dan Microsoft Remote Desktop |
| HTTPS hata | Caddy ic sertifika | HTTP 8444; HTTPS kutusunu kapatın |
| Uygulama listesi bos | TSAppAllowList bos | Panel > Uygulamalar ile EXE yayinlayin |
| RDP baglanamiyor | Yanlis Public/LAN/VPN | LAN'daysaniz LAN; disaridan Public + NAT portu |

---

## Kaldirma

Ayarlar > Uygulamalar > **EXFIN RemoteAPP** > Kaldir. Kayitli sunucu bilgisi uygulamayla silinir; sunucudaki istemci kaydi panelden ayrica silinebilir.
