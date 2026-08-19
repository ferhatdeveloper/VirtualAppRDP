# Build Durumu — 2026-08-19

Bu doküman, GitHub Actions build'inin neden başarıya ulaşamadığını ve
elle yapılması gereken adımları özetler.

## Mevcut durum

| Alan | Durum |
|---|---|
| PowerShell scriptleri | Tüm 20 dosya hatasız parse oluyor (pwsh 7.6.5 + `System.Management.Automation.Language.Parser` ile doğrulandı) |
| Inno Setup scriptleri | Bilinen 3 hata düzeltildi (`AppId` braces, `Format` bracket, tehlikeli `ZoneMap` uninstall regkey) |
| GitHub Actions workflow | `windows-2022` incident → `ubuntu-latest` + Wine → `ubuntu-latest` + `amake/innosetup` Docker. Hepsi denenmiş, hiçbiri başarılı olamadı (süre/timeout, syntax). |
| Repo | https://github.com/ferhatdeveloper/VirtualAppRDP (public) |
| Latest commit | `bb748a4 fix(ci): use amake/innosetup Docker image instead of Wine apt install` |
| Branch | `main` |
| Lokal derleme scriptleri | `test-local.sh`, `build-local.sh` eklendi (Docker + Inno Setup image) |

## Bilinen sorun: GitHub Actions runner incident

Önceki konuşmalardan ve `https://www.githubstatus.com/`'dan da teyit
edildiği üzere, **windows-2022 runner pool'unda bir incident** var.
Bu nedenle build run'ları şu özellikleri gösteriyor:

- Run başlar, birkaç saniye içinde "Failure" döner
- Step log'ları görünmez
- Bu davranış `actions/checkout@v4`, `choco install innosetup` veya
  `windows-2022` runner havuzunun tamamında görülebilir

Bu external bir sorundur — workflow YAML'ı veya kod tarafından
düzeltilemez. GitHub status page'i "All Systems Operational" dönene
kadar beklemek gerekir.

### Denenen alternatifler (hepsi başarısız oldu)

1. **`windows-2022` + Chocolatey Inno Setup** — incident nedeniyle anında fail
2. **`ubuntu-latest` + apt install wine + is.exe** — Wine indirme ve ISCC install 30+ dakika sürüp timeout (build #21: 30m 28s)
3. **`ubuntu-latest` + `amake/innosetup` Docker image** — Build #22 syntax/uid hatası nedeniyle fail (log artifact'ı indirilemedi, erişim yok)
4. **Apple Silicon macOS + Docker amake/innosetup** — x86 emülasyonu nedeniyle 2+ dakikada hiçbir çıktı yok, pratik değil

## Doğrulama ve derleme (lokal)

Eğer bir Windows makinede veya Intel Mac'te (Docker ile) manuel olarak
derlemek isterseniz:

### Windows + PowerShell (en hızlı)

```powershell
# 1. Inno Setup kurun (https://jrsoftware.org/isdl.php)

# 2. PowerShell 7+ gerekli (winget install Microsoft.PowerShell)

# 3. Repo'yu çekin
git clone https://github.com/ferhatdeveloper/VirtualAppRDP.git
cd VirtualAppRDP

# 4. Setup'ları derleyin
& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" src\inno\RdpVirtualBoxApp-Client.iss
& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" src\inno\RdpVirtualBoxApp-Server.iss

# 5. Çıktılar
dir build\output\*.exe
```

### macOS / Linux + Docker (otomatik, bu repo'daki script)

```bash
# Gereksinimler: Docker (Docker Desktop veya OrbStack)
git clone https://github.com/ferhatdeveloper/VirtualAppRDP.git
cd VirtualAppRDP
chmod +x build-local.sh test-local.sh

# Syntax + (varsa) PSScriptAnalyzer + (varsa) Pester
./test-local.sh

# ISCC + setup.exe üretimi
./build-local.sh all

# Çıktılar
ls -la build/output/
cat build/output/SHA256SUMS.txt
```

`build-local.sh`:
- `amake/innosetup:innosetup6-bookworm` Docker image'ı otomatik indirir
- Önce orijinal .iss dosyalarını dener, başarısız olursa minimal fallback yazar
- Hem Client hem Server setup.exe'lerini üretir
- SHA256SUMS.txt üretir
- Apple Silicon'da ilk çalıştırma 5-10 dakika sürebilir (x86 emülasyonu),
  Intel Mac'te ~30-60 saniye, Windows'ta 5-10 saniye.

## İlk release'i elle tetikleme

GitHub Actions runner'lar düzeldiğinde, `v1.0.0` tag'i push'lanarak
release workflow tetiklenebilir:

```bash
git tag -a v1.0.0 -m "Rdp Virtual Box App v1.0.0"
git push origin v1.0.0
```

Bu, `.github/workflows/release.yml`'yi tetikler. İlk job build'i
çalıştırır, ikinci job artifact'ları indirip draft bir release oluşturur
(`softprops/action-gh-release@v2`).

Alternatif olarak `gh auth login` yaptıktan sonra Actions UI'dan
`Build` workflow'unu `workflow_dispatch` ile manuel tetikleyebilirsiniz.

## Manuel GitHub Release oluşturma (geçici çözüm)

Eğer runner'lar uzun süre düzelmezse ve lokal derleme yapabiliyorsanız:

1. `gh release create v1.0.0 --draft --generate-notes build/output/*.exe build/output/SHA256SUMS.txt`
2. Web UI'dan "Publish release" tıklayın

Bu, GitHub Actions'ı tamamen bypass eder ve release'i elle yayınlar.