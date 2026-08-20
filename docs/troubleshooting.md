# Sorun Giderme Kılavuzu

Bu belge, **Rdp Virtual Box App** kullanırken karşılaşılabilecek yaygın hataları ve çözümlerini içerir.

---

## İçindekiler

- [WinRM Erişilemez](#winrm-erişilemez)
- [RDP Port Kapalı](#rdp-port-kapalı)
- [Sertifika Uyarısı](#sertifika-uyarısı)
- [Guacamole Başlamıyor](#guacamole-başlamıyor)
- [Cloudflare Tunnel Timeout](#cloudflare-tunnel-timeout)
- [Tailscale Auth Hatası](#tailscale-auth-hatası)
- [Credential Manager Sorunları](#credential-manager-sorunları)
- [.rdp Dosyası Açılmıyor](#rdp-dosyası-açılmıyor)
- [Lisans Hatası](#lisans-hatası)
- [Uygulama Yayınlanmadı](#uygulama-yayınlanmadı)
- [Log Dosyaları](#log-dosyaları)

---

## WinRM Erişilemez

**Belirti:** Server Probe "WinRM bağlantısı başarısız" veya "Test-WSMan: timeout" döndürür.

**Sebep:** WinRM servisi kapalı, firewall kuralı eksik veya kimlik doğrulama başarısız.

### Çözüm

1. **WinRM servisini kontrol edin (server'da):**
   ```powershell
   Get-Service WinRM
   # Running olmalı
   Enable-PSRemoting -Force
   ```

2. **Firewall kuralını ekleyin:**
   ```powershell
   Enable-PSRemoting -Force
   New-NetFirewallRule -DisplayName "WinRM 5985" -Direction Inbound -LocalPort 5985 -Protocol TCP -Action Allow
   New-NetFirewallRule -DisplayName "WinRM 5986" -Direction Inbound -LocalPort 5986 -Protocol TCP -Action Allow
   ```

3. **TrustedHosts'a ekleyin (workgroup ortamında):**
   ```powershell
   Set-Item WSMan:\localhost\Client\TrustedHosts -Value '*' -Force
   ```

4. **Client'tan test edin:**
   ```powershell
   Test-WSMan -ComputerName 192.168.0.106
   ```

> Eğer WinRM hiç çalışmıyorsa Server Probe uyarı verir ama setup devam eder — yalnızca otomatik uygulama listesi alınamaz.

---

## RDP Port Kapalı

**Belirti:** "Remote Desktop can't connect", "Port 3389 closed" uyarısı.

### Çözüm

1. **RDP servisinin çalıştığını doğrulayın:**
   ```powershell
   Get-Service TermService
   # Running olmalı
   Start-Service TermService
   Set-Service TermService -StartupType Automatic
   ```

2. **Firewall kuralını açın:**
   ```powershell
   New-NetFirewallRule -DisplayName "RDP 3389" -Direction Inbound -LocalPort 3389 -Protocol TCP -Action Allow -Profile Any
   ```

3. **Port açık mı kontrol edin:**
   ```powershell
   Test-NetConnection -ComputerName 192.168.0.106 -Port 3389
   # TcpTestSucceeded: True olmalı
   ```

4. **Network Level Authentication'ı etkinleştirin:**
   - `gpedit.msc` → Computer Configuration → Administrative Templates → Windows Components → Remote Desktop Services → Remote Desktop Session Host → Security → **"Require user authentication for remote connections by using Network Level Authentication"** = Enabled

5. **Kullanıcı RDP yetkisi:**
   ```powershell
   Add-LocalGroupMember -Group "Remote Desktop Users" -Member "FIRMA\kullanici"
   ```

---

## Sertifika Uyarısı

**Belirti:** "The certificate is not trusted", "There is a problem with the security certificate".

### Self-signed Sertifika için

**Tarayıcıda (RD Web / Guacamole):**
1. Sertifika hatası sayfasında **"Advanced"** → **"Proceed to ..."** tıklayın.
2. **"Add to trusted"** seçeneği varsa kullanın.

**mstsc.exe (.rdp):**
1. RDP bağlantısı başlamadan önce uyarı penceresi gelir.
2. **"Don't ask me again for connections to this computer"** kutusunu işaretleyin → **"Connect"**.

### Kalıcı Çözüm — CA-signed Sertifika

**Probe API HTTPS (Caddy, 8445):**

```powershell
Get-ScheduledTask -TaskName RdpVirtualBoxApp-Caddy | Start-ScheduledTask
Invoke-WebRequest -Uri https://127.0.0.1:8445/health -SkipCertificateCheck
```

Let's Encrypt için `RDPVB_CADDY_DOMAIN` gerekir; 443 IIS/RD Gateway'dedir.

**RD Gateway / RDP için Let's Encrypt (ücretsiz):**

1. **win-acme** indirin: <https://www.win-acme.com/>
2. `wacs.exe` çalıştırın → Simple ACME → Manual → CSR oluşturun.
3. Challenge doğrulaması için 80 port kısa süre açık olmalı.
4. Üretilen `.pfx`'i Server Setup'ta **CA-signed Sertifika** olarak seçin.

**Active Directory CA (kurumsal):**

1. `certsrv.msc` üzerinden Web Server template'i ile cert oluşturun.
2. Subject: sunucu FQDN'i.
3. `.pfx` export edin (private key dahil).
4. Server Setup'a import edin.

---

## Guacamole Başlamıyor

**Belirti:** `https://server:8443/guacamole` 404 veya 503 döndürür.

### Çözüm Adımları

1. **Tomcat çalışıyor mu?**
   ```powershell
   Get-Service Tomcat9
   Start-Service Tomcat9
   ```

2. **guacd çalışıyor mu?**
   ```powershell
   Get-Service guacd
   # eğer yoksa:
   & "C:\Program Files\Apache Software Foundation\Tomcat\bin\guacd.exe" -l
   ```

3. **Log dosyaları:**
   ```
   C:\Program Files\Apache Software Foundation\Tomcat\logs\catalina.out
   C:\guacd\guacd.log
   %ProgramData%\RdpVirtualBoxApp\Logs\guacamole-installer.log
   ```

4. **MySQL bağlantısı:**
   ```powershell
   & "C:\Program Files\MySQL\MySQL Server 8.0\bin\mysql.exe" -u guacamole -p
   # Guacamole şeması yüklü mü?
   USE guacamole;
   SHOW TABLES;
   ```

5. **Tomcat 9 Manager üzerinden kontrol:**
   - `https://localhost:8443/manager/html`
   - `guacamole` deploy edilmiş mi?

6. **Yeniden deploy:**
   ```powershell
   Copy-Item "guacamole.war" "C:\Program Files\Apache Software Foundation\Tomcat\webapps\" -Force
   ```

---

## Cloudflare Tunnel Timeout

**Belirti:** `cloudflared tunnel create` sırasında "Failed to fetch token" veya tunnel bağlantı kurulamıyor.

### Çözüm

1. **cloudflared güncel mi?**
   ```powershell
   cloudflared update
   cloudflared --version
   ```

2. **Login token'ı kontrol edin:**
   ```powershell
   cloudflared tunnel login
   # Browser'da Cloudflare hesabınıza giriş yapın
   ```

3. **Tunnel listesini kontrol edin:**
   ```powershell
   cloudflared tunnel list
   ```

4. **DNS route kontrolü:**
   - Cloudflare dashboard → DNS → Records → `rdp.alanadiniz.com` CNAM `tunnel-id.cfargotunnel.com`

5. **Service çalışıyor mu?**
   ```powershell
   Get-Service cloudflared
   Restart-Service cloudflared
   ```

6. **Log'lar:**
   ```
   C:\Windows\System32\config\systemprofile\AppData\Local\cloudflared\logs\
   ```

---

## Tailscale Auth Hatası

**Belirti:** `tailscale up` sırasında "Authentication failed" veya "key expired".

### Çözüm

1. **Tailscale auth key'i yenileyin:**
   - <https://login.tailscale.com/admin/settings/keys>
   - Yeni **reusable** + **pre-approved** key oluşturun.
   - Server Setup'ta bu key'i girin.

2. **Magic DNS ile login:**
   ```powershell
   tailscale login
   # Browser'da hesap doğrulaması
   ```

3. **Mevcut durumu kontrol edin:**
   ```powershell
   tailscale status
   ```

4. **ACL kontrolü:**
   - Tailscale admin → Access Controls
   - Sunucu ve client aynı tag altında olmalı.

5. **Tamamen yeniden kurulum:**
   ```powershell
   tailscale logout
   & msiexec /x tailscale.msi /quiet
   & msiexec /i tailscale.msi /quiet
   tailscale up --authkey=YOUR_NEW_KEY
   ```

---

## Credential Manager Sorunları

**Belirti:** RDP bağlantısı her seferinde parola soruyor veya "Incorrect password" hatası.

### Çözüm

1. **Credential Manager'daki girişi kontrol edin:**
   - Control Panel → Credential Manager → Windows Credentials
   - `RdpVirtualBoxApp:192.168.0.106` gibi bir girdi olmalı.

2. **Eski girdiyi silin ve yeniden ekleyin:**
   ```powershell
   # Mevcut
   cmdkey /list | Select-String -Pattern 'RdpVirtualBoxApp'
   cmdkey /delete:LegacyGeneric:target="RdpVirtualBoxApp:192.168.0.106"

   # Yeni ekleme (Setup sihirbazından tekrar Install yapın)
   ```

3. **Generic Credential Türü:**
   - Target: `RdpVirtualBoxApp:<server>:<app>`
   - Username: `FIRMA\kullanici`
   - Password: RDP parolanız

4. **Permission sorunu (workgroup):**
   - Credential Manager'a erişim için yönetici hakkı gerekebilir.
   - Setup'ı **"Run as administrator"** ile çalıştırın.

5. **PowerShell modülü:**
   ```powershell
   Install-Module CredentialManager
   New-StoredCredential -Target "RdpVirtualBoxApp:192.168.0.106" -UserName "FIRMA\kullanici" -Password (Read-Host -AsSecureString)
   ```

---

## .rdp Dosyası Açılmıyor

**Belirti:** Çift tıklayınca bir şey olmuyor veya "Bu dosyayı açacak uygulama yok" hatası.

### Çözüm

1. **Dosya ilişkilendirmesi:**
   - `.rdp` dosyasına sağ tıklayın → "Open with" → "Remote Desktop Connection".
   - Veya: Default Apps → `.rdp` → Remote Desktop Connection.

2. **Manuel açma:**
   ```powershell
   mstsc.exe "C:\Users\Kullanici\Documents\RdpVirtualBoxApp\erp.rdp"
   ```

3. **Dosya içeriği doğrulama:**
   ```powershell
   Get-Content "erp.rdp"
   # full address:s:192.168.0.106 olmalı
   ```

4. **Encoding sorunu:**
   - `.rdp` UTF-8 BOM'suz olmalı.
   - PowerShell'de üretildiyse `Set-Content -Encoding UTF8 -NoNewline` kullanın.

5. **Windows 10 1809 öncesi:**
   - `remoteapplicationmode:i:1` yok sayılır.
   - Tam masaüstü bağlantısı kurar (RemoteApp çalışmaz).
   - **Çözüm:** Windows'u güncelleyin.

---

## Lisans Hatası

**Belirti:** "Remote Desktop license issue", "No license server available", RD Web 120 gün sonra durdu.

### Çözüm

1. **License Server çalışıyor mu?**
   ```powershell
   Get-Service TermServLicensing
   ```

2. **License Manager:**
   ```powershell
   licmgr.exe
   ```
   - Server'ın activated olduğunu doğrulayın.
   - Lisanslar yüklü mü?

3. **Specified license server:**
   ```powershell
   $obj = gwmi -namespace "Root\cimv2" -class "Win32_TSProductKey"
   $obj.GetSpecifiedLicenseServerList()
   ```

4. **Lisans modu:**
   - Group Policy → Remote Desktop Session Host → Licensing → **"Set the Remote Desktop licensing mode"** = Per User veya Per Device
   - `gpupdate /force`

5. **RDS CAL ekleme:**
   - License Manager → Server activation → Install Licenses → Lisans anahtarı

6. **Geçici çözüm (lisans yenilenene kadar):**
   - Apache Guacamole fallback'i etkinleştirin.
   - Kullanıcılar web üzerinden devam edebilir.

---

## Uygulama Yayınlanmadı

**Belirti:** Server Probe'da uygulama görünüyor ama Client Setup'ta listelenmiyor.

### Çözüm

1. **RemoteApp koleksiyonu kontrolü:**
   ```powershell
   Get-RDSessionCollection
   Get-RDRemoteApp -CollectionName "RdpVirtualBoxApp"
   ```

2. **Uygulama yolu doğru mu?**
   ```powershell
   Test-Path "C:\Program Files\App\erp.exe"
   ```

3. **AppScanner yeniden çalıştırma:**
   ```powershell
   & "C:\Program Files\RdpVirtualBoxApp\AppScanner.ps1"
   ```

4. **RemoteApp izinleri:**
   - Collection properties → User Groups → İlgili grup eklendi mi?

5. **Session Host ayarları:**
   ```powershell
   Set-RDSessionHostConfiguration -CollectionName "RdpVirtualBoxApp" -UserGroup "FIRMA\RDPUsers"
   ```

6. **RDS Health Check:**
   ```powershell
   Get-RDServer -ConnectionBroker <broker>
   Get-RDVirtualDesktopCollection
   ```

---

## Log Dosyaları

Tüm log'lar `%ProgramData%\RdpVirtualBoxApp\Logs\` altındadır:

| Dosya | İçerik |
|---|---|
| `server-setup.log` | Ana kurulum sihirbazı |
| `rds-installer.log` | RDS rol kurulumu |
| `certificate-manager.log` | Sertifika üretimi / import |
| `remoteapp-publisher.log` | RemoteApp yayını |
| `firewall-config.log` | Firewall kuralları |
| `license-detector.log` | Lisans tespiti |
| `guacamole-installer.log` | Guacamole kurulumu |
| `tailscale-installer.log` | Tailscale kurulumu |
| `cloudflare-tunnel.log` | Cloudflare kurulumu |
| `gateway-installer.log` | RD Gateway kurulumu |
| `client-setup.log` | Client sihirbaz (user profile'da) |

### Client Log Konumu

```
%LOCALAPPDATA%\RdpVirtualBoxApp\Logs\client-setup.log
%APPDATA%\RdpVirtualBoxApp\setup-<timestamp>.log
```

### Real-time İzleme

```powershell
# Son 50 satır
Get-Content "$env:ProgramData\RdpVirtualBoxApp\Logs\server-setup.log" -Tail 50 -Wait
```

---

## Hızlı Checklist

Setup başarısız olduğunda sırayla kontrol edin:

- [ ] Windows Update güncel mi?
- [ ] Yönetici olarak mı çalıştırıyorum?
- [ ] WinRM açık mı?
- [ ] Firewall kuralları uygulandı mı?
- [ ] RDS rolleri kurulu mu?
- [ ] Sertifika atanmış mı?
- [ ] RDP-Tcp dinleyicisi aktif mi?
- [ ] Lisans durumu nedir? (grace period dahil)
- [ ] Log dosyaları ne diyor?
- [ ] Farklı bir client'tan denediniz mi?

---

## Destek

Sorun devam ediyorsa:

1. GitHub Issues: <https://github.com/ferhatdeveloper/VirtualAppRDP/issues>
2. Log dosyalarını ekleyin (anonimleştirilmiş).
3. Hata mesajının tam metnini paylaşın.

---

## İlgili Belgeler

- [server-requirements.md](server-requirements.md)
- [server-setup-guide.md](server-setup-guide.md)
- [client-setup-guide.md](client-setup-guide.md)
- [licensing-and-rdweb.md](licensing-and-rdweb.md)
