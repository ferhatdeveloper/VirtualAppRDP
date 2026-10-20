# SQL Bridge — Sunucu SQL’ini localhost gibi kullanma

RemoteApp ile uygulamayı sunucuda çalıştırmak yerine (veya yanında), istemci PC’deki SSMS / Excel / yerel ERP istemcilerinin **sunucu SQL’ine `127.0.0.1` üzerinden** bağlanmasını sağlar.

## Nasıl çalışır?

İstemci sihirbazına **sunucu adı** veya **public IP** yazılabilir; ikisi de Probe tüneline gider. SQL portu internete açılmaz.

```
[SSMS / yerel uygulama]
        │  Server=127.0.0.1,1433   ← her zaman localhost
        ▼
[İstemci SqlBridgeClient]
        │  CONNECT /sql-bridge
        │  → http://<SUNUCU_ADI|PUBLIC_IP>:8444
        │     örn. SUNUCU01  /  rdp.firma.local  /  203.0.113.50
        ▼
[Sunucu Probe API] ──► 127.0.0.1:<sqlPort> (SQL Server)
```

- SQL TCP (**1433**) internete **açılmaz**.
- Tünel ucu: hostname, FQDN veya public IP — hangisini yazarsanız.
- SSMS bağlantı dizesi her zaman: `Server=127.0.0.1,1433`

## Sunucu kurulumu

1. Server sihirbazı → **Bileşenler** → **SQL Bridge** kutusunu işaretleyin  
   veya:

```powershell
.\SqlBridge.ps1 -Mode Install
# İsteğe bağlı: SQL TCP bayrağını registry'de aç
.\SqlBridge.ps1 -Mode Install -EnableTcpIfNeeded
```

2. Probe API’nin çalıştığından emin olun (`Start-ProbeApiHost.ps1 -Mode Status`).
3. Durum:

```powershell
.\SqlBridge.ps1 -Mode Status
# veya
Invoke-RestMethod http://127.0.0.1:8444/api/sql-bridge -Headers @{ Authorization = "Bearer $token" }
```

SQL Server’da **TCP/IP protokolü açık** ve dinliyor olmalı (varsayılan 1433 veya dinamik port; kurulum registry’den algılar).

### Otomatik sertifika

`SqlBridge.ps1 -Mode Install` (veya sihirbazda SQL Bridge) şunları kendisi yapar:

1. Self-signed TLS (SAN: sunucu adı, FQDN, public/LAN IP)
2. `LocalMachine\Root`’a güven
3. `EXFIN-SqlBridge.cer` + `EXFIN-RD-Gateway.cer` export (`/sql-bridge.cer` ile indirilebilir)
4. Caddy HTTPS 8445 (yoksa kurar)

İstemci kurulumu `/sql-bridge.cer` indirip `CurrentUser\Root`’a ekler — elle sertifika işlemi gerekmez.

## İstemci kurulumu

Client sihirbazı adım 3’te:

> **SQL Bridge: sunucu SQL’ini localhost gibi kullan**

veya:

```powershell
# Public IP ile
.\SqlBridgeClient.ps1 -Mode Install -Server 203.0.113.50 -ProbePort 8444 -Token '<probe-token>'

# Sunucu adi / FQDN ile (ayni sekilde calisir)
.\SqlBridgeClient.ps1 -Mode Install -Server rdp.firma.local -ProbePort 8444 -Token '<probe-token>'
.\SqlBridgeClient.ps1 -Mode Install -Server SUNUCU01 -ProbePort 8444 -Token '<probe-token>'
```

Kurulum sonrası:

| Dosya / görev | Açıklama |
|---|---|
| `%LOCALAPPDATA%\RdpVirtualBoxApp\sql-bridge-connection.txt` | SSMS bağlantı dizesi |
| Scheduled Task `RdpVirtualBoxApp-SqlBridge` | Oturum açınca tüneli başlatır |
| `SqlBridgeClient.ps1 -Mode Status` | Dinleme durumu |

## SSMS örneği

1. SQL Bridge istemcisinin çalıştığını doğrulayın (`Status` → `listening: true`).
2. SSMS → Connect → Server name: `127.0.0.1,1433`
3. SQL kimlik bilgisi / Windows auth (sunucu SQL’inin kabul ettiği yöntem).

## Sunucu adı veya public IP

İstemci adım 1’de ne yazdıysanız tünel onu kullanır:

| Giriş | Örnek |
|---|---|
| Sunucu adı (NetBIOS) | `SUNUCU01` |
| FQDN | `rdp.firma.local` |
| Public IP | `203.0.113.50` |

Sunucu tarafı durum çıktısı kabul edilen host’ları listeler:

```powershell
.\SqlBridge.ps1 -Mode Status
# probe.acceptHosts / probe.serverName / probe.publicHost / probe.examples
```

Firewall / NAT (WAN için): **TCP 8444** public IP’ye yönlendirilmiş olmalı. **1433 yönlendirmeyin.** DNS ile sunucu adı kullanıyorsanız A kaydı Probe’un dinlediği adrese işaret etmeli.

## Güvenlik

- İnternete SQL portu açılmaz; sadece Probe API (8444) + Bearer token.
- Token’ı istemciye güvenli dağıtın (`probe-api.json` / kurulum sihirbazı).
- Üretimde Caddy HTTPS (8445) veya IP kısıtı ile Probe erişimini daraltın.
- `allowDirectLan` / doğrudan 1433 varsayılan **kapalı**dır.

## Sorun giderme

| Belirti | Kontrol |
|---|---|
| `sql_bridge_disabled` | Sunucuda `SqlBridge.ps1 -Mode Enable` veya Install |
| `sql_not_reachable` | SQL Server TCP/IP, servis, port (Configuration Manager) |
| `unauthorized` | Bearer token Probe API ile aynı mı? |
| Yerel 1433 meşgul | `SqlBridgeClient.ps1 -Mode Install -LocalPort 14333` sonra SSMS’te `127.0.0.1,14333` |

## API

| Method | Path | Auth | Açıklama |
|---|---|---|---|
| GET | `/api/sql-bridge` | Bearer | Durum JSON |
| CONNECT | `/sql-bridge` | Bearer | Ham TCP tüneli → yerel SQL |
