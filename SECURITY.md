# Güvenlik Politikası

## Desteklenen Versiyonlar

Aşağıdaki versiyonlar güvenlik güncellemeleri için desteklenmektedir:

| Versiyon | Destek Durumu |
|---|---|
| v1.0.x  | Aktif destek |
| < v1.0  | Desteklenmiyor |

## Güvenlik Açığı Bildirimi

Rdp Virtual Box App'te bir güvenlik açığı keşfettiyseniz, lütfen **public issue tracker** üzerinden değil, doğrudan aşağıdaki kanaldan bildirin:

- **E-posta:** ferhatdeveloper@gmail.com
- **GitHub Security Advisories:** https://github.com/ferhatdeveloper/VirtualAppRDP/security/advisories/new

Bildiriminizde şu bilgileri paylaşın:

- Açığın kısa açıklaması
- Yeniden üretme adımları (PoC mümkünse)
- Potansiyel etki (RCE, LPE, info disclosure vb.)
- Önerilen düzeltme (varsa)
- Etkilenen bileşen: Client / Server / Inno Setup / PowerShell modülü

### Yanıt Süresi

- **İlk yanıt:** 72 saat içinde
- **Değerlendirme:** 7 gün içinde
- **Yama (kritik):** 30 gün içinde
- **Yama (orta/düşük):** Sonraki minor release ile

### Koordineli Açıklama

Yama yayınlandıktan sonra uygun bir zamanda **GitHub Security Advisory** üzerinden kamuya açıklama yapılacaktır. Disclosure zamanlaması için lütfen bizimle koordineli çalışın.

## Bilinen Güvenlik Notları

- **Self-signed sertifika:** Varsayılan kurulumda RDP ve Guacamole HTTPS self-signed sertifika ile gelir. Üretim ortamında **CA imzalı** sertifika ile değiştirilmesi önerilir.
- **Credential Manager saklama:** Client-side setup, kullanıcı izniyle Windows Credential Manager'a parola saklar. Makine paylaşımlıysa ek koruma (DPAPI) düşünülmelidir.
- **Varsayılan Guacamole şifresi:** `guacadmin/guacadmin` — kurulum sonrası **mutlaka** değiştirilmelidir.
- **WinRM erişimi:** Client setup'ın server'a bağlanması için 5985/5986 açılır. İnternete açılmamalıdır; sadece LAN/VPN üzerinden erişilebilir olmalıdır.
- **Cloudflare Tunnel token'ı:** Repository'de commit edilmemeli, kurulum sırasında parametre olarak geçilmelidir.

Teşekkürler!