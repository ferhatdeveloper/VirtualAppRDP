# iOS Client Kurulum Kilavuzu

Bu belge, **EXFIN RemoteAPP** iPhone / iPad istemcisini Xcode ile derleme ve Windows Server Probe API'sine baglama adimlarini anlatir.

> IT admin, sunucuda Probe REST API'nin (TCP **8444**) acik oldugunu teyit ettikten sonra bu kilavuzu izleyin.

---

## Gereksinimler

| Bilesen | Minimum | Notlar |
|---|---|---|
| **iOS / iPadOS** | 16.0 | 17+ onerilir |
| **Xcode** | 15 | Mac'te derleme |
| **XcodeGen** | son surum | `brew install xcodegen` — `.xcodeproj` uretir |
| **Microsoft Remote Desktop** | App Store | `.rdp` acmak icin zorunlu |
| **Apple Developer** | ucretsiz veya ucretli | Cihaza imzali kurulum icin Team ID |

Kaynak: `src/ios/ExfinRemoteApp/`

---

## Xcode projesi

```bash
brew install xcodegen
cd src/ios/ExfinRemoteApp
bash generate-xcode.sh
open ExfinRemoteApp.xcodeproj
```

1. Signing & Capabilities > **Team** secin (Apple ID yeter).
2. Bundle ID `com.exfin.remoteapp` cakisirsa degistirin.
3. Hedef cihaz veya simulatore **Run**.

App Store / TestFlight icin **Product > Archive**, ardından Organizer'dan Distribute.

---

## 4 adimlik sihirbaz

Android ve Windows ile ayni:

1. Sunucu IP + port **8444** + Windows kullanici adi
2. Sunucuyu tara
3. RemoteApp + Public / LAN / VPN
4. Kaydet ve baglan — `POST /api/clients`, `.rdp` indirme, Paylas / Remote Desktop

HTTP LAN icin `NSAllowsArbitraryLoads` aciktir. Caddy ic sertifika (8445) iOS'ta guvenilmez; 8444 kullanin.

---

## Microsoft Remote Desktop

App Store: [Microsoft Remote Desktop](https://apps.apple.com/app/microsoft-remote-desktop/id714464092)

Uygulama gomulu RDP motoru icermez; sunucudan alinan `.rdp` Microsoft istemcisine verilir.

---

## Ag

| Hedef | Port |
|---|---|
| Probe / panel | **8444** HTTP |
| RDP | musterinin Public / LAN / VPN portu |

`requireApproval` aciksa WAN `.rdp` icin panelde **Istemciler > Izin ver** gerekir. iOS `identifierForVendor` + kullanici adi ile kaydolur.
