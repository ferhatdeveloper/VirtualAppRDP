# SQL Bridge — Sunucu SQL’ini localhost gibi kullanma

RemoteApp ile uygulamayı sunucuda çalıştırmak yerine (veya yanında), istemci PC’deki SSMS / Excel / yerel ERP istemcilerinin **sunucu SQL’ine `127.0.0.1` üzerinden** bağlanmasını sağlar.

## Nasıl çalışır?

```
[SSMS / yerel uygulama]
        │  Server=127.0.0.1,1433
        ▼
[İstemci SqlBridgeClient] ── Probe API CONNECT /sql-bridge (TCP 8444 + Bearer) ──► [Sunucu]
                                                                                      │
                                                                                      ▼
                                                                            127.0.0.1:<sqlPort>
                                                                            (SQL Server)
```

- SQL TCP portu (**1433**) internete **açılmaz**.
- Tünel mevcut Probe REST API portu üzerinden gider; kimlik doğrulama Bearer token ile yapılır.
- İstemci tarafında bağlantı dizesi: `Server=127.0.0.1,1433`

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

## İstemci kurulumu

Client sihirbazı adım 3’te:

> **SQL Bridge: sunucu SQL’ini localhost gibi kullan**

veya:

```powershell
.\SqlBridgeClient.ps1 -Mode Install -Server 10.0.0.10 -ProbePort 8444 -Token '<probe-token>'
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

## Güvenlik

- İnternete SQL portu açılmaz; sadece Probe API (8444) + Bearer token.
- Token’ı istemciye güvenli dağıtın (`probe-api.json` / kurulum sihirbazı).
- Üretimde Caddy HTTPS (8445) veya VPN (Tailscale) ile Probe erişimini kısıtlayın.
- `allowDirectLan` varsayılan **kapalı**dır (doğrudan 1433 yayınlanmaz).

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
