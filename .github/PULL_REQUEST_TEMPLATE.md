## Değişiklik Özeti

Bu PR'ın ne yaptığını kısaca açıklayın (1-3 cümle).

## Bağlantılı Issue

Fixes #<issue_no>
Relates to #<issue_no>

## Değişiklik Türü

- [ ] Bug fix (davranışı değiştirmeyen, hatayı düzelten değişiklik)
- [ ] Yeni özellik (davranışı değiştiren, yeni işlevsellik ekleyen değişiklik)
- [ ] Breaking change (mevcut işlevselliği bozan değişiklik)
- [ ] Dokümantasyon / yorum güncellemesi
- [ ] Refactor / performans iyileştirmesi
- [ ] Build / CI değişikliği

## Test Edilen Senaryolar

- [ ] PSScriptAnalyzer temiz
- [ ] Pester testleri geçti
- [ ] Windows Server 2019 üzerinde manuel test
- [ ] Windows 11 client üzerinde manuel test
- [ ] Diğer: ____

## Test Komutları

```powershell
# Lint
Invoke-ScriptAnalyzer -Path ./src -Recurse

# Pester
Invoke-Pester -Path ./tests -Output Detailed

# Build
ISCC.exe src\inno\RdpVirtualBoxApp-Client.iss
ISCC.exe src\inno\RdpVirtualBoxApp-Server.iss
```

## Checklist

- [ ] Kod, repodaki mevcut stile uygun
- [ ] Değişen satırlarda ekran görüntüsü/video (UI değişikliği ise)
- [ ] `docs/` altındaki ilgili kılavuz güncellendi (gerekirse)
- [ ] `CHANGELOG.md` güncellendi (gerekirse)
- [ ] Yeni bağımlılık varsa `README.md` veya `requirements` benzeri dosyaya eklendi

## Ek Notlar

Reviewer'ın bilmesi gereken ek bilgi, breaking change uyarıları, vb.