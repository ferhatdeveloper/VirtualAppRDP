# Windows'ta Setup Derleme

GHA'daki `amake/innosetup` Docker image'ı Wine layer'ında sorunlar çıkardığı için,
orijinal `.iss` dosyalarını **doğrudan Windows'ta Inno Setup ile derlemek** en hızlı yoldur.

## 1. Inno Setup Kur

1. https://jrsoftware.org/isdl.php adresinden **Inno Setup 6** indir
2. Kurulumu varsayılan ayarlarla tamamla (`C:\Program Files (x86)\Inno Setup 6\`)
3. Kurulum sonrası `ISCC.exe` şu yolda olur:
   ```
   C:\Program Files (x86)\Inno Setup 6\ISCC.exe
   ```

## 2. Repo'yu Klonla

```powershell
git clone https://github.com/ferhatdeveloper/VirtualAppRDP.git
cd VirtualAppRDP
```

## 3. Setup'ları Derle

```powershell
# PowerShell'i yönetici olarak aç

# Client Setup
& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" src\inno\RdpVirtualBoxApp-Client.iss

# Server Setup (ayrı pencerede veya sırayla)
& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" src\inno\RdpVirtualBoxApp-Server.iss
```

## 4. Çıktı

ISCC varsayılan olarak `.iss` dosyasının bulunduğu dizinde `Output` alt-klasörü oluşturur:

```
src\inno\Output\RdpVirtualBoxApp-Client-v1.0.1.exe
src\inno\Output\RdpVirtualBoxApp-Server-v1.0.1.exe
```

Bu `.exe` dosyaları **~7-10 MB** boyutunda olur (PowerShell wizard + config + assets dahil).

## 5. Hata Durumunda

ISCC hata verirse **hangi satırda** ve **neden** olduğunu açıkça söyler.
En sık karşılaşılan hatalar:

| Hata | Çözüm |
|------|-------|
| `Unknown constant "X"` | Sabit ismini düzelt (örn. `{userlocalappdata}` → `{localappdata}`) |
| `Parameter "Flags" includes an unknown flag` | Geçersiz flag ismi, kaldır veya düzelt |
| `Could not read "X\..\Y"` | `.iss` dosyası kendi dizininde olmalı, `..\` sadece bir seviye |
| `Out of memory` | `Compression=lzma2/ultra64` → `lzma2/ultra` |

Düzeltmeleri yaptıktan sonra `git commit -am "fix(iss): ..."` ile push et — GHA da faydalanır.

## 6. Kurulum (Server'da)

1. `RdpVirtualBoxApp-Server-v1.0.1.exe` → **Yönetici olarak çalıştır**
2. Pre-flight check'ler (Windows sürümü, .NET, PowerShell) geçer
3. Kurulum yolu: `C:\Program Files\RdpVirtualBoxApp\`
4. **Server Setup Wizard** otomatik başlar → RDS rolü, RD Gateway, RD Web Access vb. adımlar
5. Web erişim için **Apache Guacamole** veya **RD Web Access** wizard'da seçilebilir

## 7. Kurulum (Client'ta)

1. `RdpVirtualBoxApp-Client-v1.0.1.exe` → Normal çalıştır (yönetici gerekmez)
2. Sunucu adresi, port, kimlik bilgileri girilir
3. Sunucu taranır, **yayınlanan uygulamalar listelenir**
4. Seçilen uygulamalar için `.rdp` kısayolları oluşturulur
5. **Web erişim** için `Start Menu → Rdp Virtual Box App → Web Access` kısayolu

## Notlar

- `.iss` dosyaları `src\inno\` altında, içerideki relative path'ler `..\powershell\`, `..\config\`, `..\assets\` Windows'ta doğru çözülür
- `MyAppVersion = "1.0.1"` (commit 0bbd57b itibarıyla) — `.exe` dosya adında bu görünür
- GHA tekrar çalışırsa otomatik olarak GitHub release'e push edilir
