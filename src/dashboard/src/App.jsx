import { useCallback, useEffect, useMemo, useState } from 'react'

const TEXT_EXTS = ['.txt', '.log', '.csv', '.json', '.xml', '.ini', '.rdp', '.ps1', '.md']
const ICON_EXTS = ['.exe', '.ico', '.png']

function authHeaders() {
  const h = { 'Content-Type': 'application/json' }
  const t = sessionStorage.getItem('rdpvb_token') || ''
  if (t) h.Authorization = 'Bearer ' + t
  return h
}

async function readJson(res) {
  const text = await res.text()
  try { return JSON.parse(text) } catch { return { error: text || res.status } }
}

function formatSize(n) {
  if (n == null || n === 0) return ''
  if (n < 1024) return n + ' B'
  if (n < 1048576) return (n / 1024).toFixed(1) + ' KB'
  return (n / 1048576).toFixed(1) + ' MB'
}

function canPreview(entry) {
  if (!entry || entry.kind === 'dir') return false
  if (entry.previewable) return true
  const ext = (entry.extension || '').toLowerCase()
  return TEXT_EXTS.indexOf(ext) >= 0
}

function AppIcon({ alias, path, size = 32 }) {
  const [dataSrc, setDataSrc] = useState('')

  useEffect(() => {
    let cancelled = false
    setDataSrc('')
    const url = alias
      ? '/api/icon?alias=' + encodeURIComponent(alias)
      : (path ? '/api/icon?path=' + encodeURIComponent(path) : '')
    if (!url) return undefined
    fetch(url, { headers: authHeaders() })
      .then(readJson)
      .then((j) => {
        if (cancelled) return
        if (j && j.png) setDataSrc('data:image/png;base64,' + j.png)
        else setDataSrc('')
      })
      .catch(() => {
        if (!cancelled) setDataSrc('')
      })
    return () => { cancelled = true }
  }, [alias, path])

  if (!dataSrc) {
    return <span className="icon-ph" style={{ width: size, height: size }} aria-hidden="true" />
  }
  return (
    <img
      className="app-icon"
      width={size}
      height={size}
      alt=""
      src={dataSrc}
      onError={() => setDataSrc('')}
    />
  )
}

export default function App() {
  const [tab, setTab] = useState('apps')
  const [health, setHealth] = useState(null)
  const [apps, setApps] = useState([])
  const [selectedAlias, setSelectedAlias] = useState('')
  const [path, setPath] = useState('C:\\LOGO\\TIGER3ENT\\Tiger3Enterprise.exe')
  const [alias, setAlias] = useState('Tiger3Ent')
  const [appName, setAppName] = useState('Tiger3 Enterprise')
  const [iconPath, setIconPath] = useState('')
  const [iconNonce, setIconNonce] = useState(0)
  const [portal, setPortal] = useState({ customers: [], webPort: 8001, listenRdpPort: 3389 })
  const [customerId, setCustomerId] = useState('default')
  const [form, setForm] = useState({
    name: '', publicIp: '', lanIp: '', vpnIp: '', rdpPort: 3389, lanRdpPort: 3389,
    connectMode: 'direct', gatewayHost: '', gatewayPort: 443, webKind: 'auto', webUrl: ''
  })
  const [webInfo, setWebInfo] = useState(null)
  const [webPort, setWebPort] = useState(8001)
  const [token, setToken] = useState(sessionStorage.getItem('rdpvb_token') || '')
  const [status, setStatus] = useState('')
  const [statusKind, setStatusKind] = useState('')
  const [files, setFiles] = useState([])
  const [browseOpen, setBrowseOpen] = useState(false)
  const [browseMode, setBrowseMode] = useState('exe')
  const [browse, setBrowse] = useState(null)
  const [preview, setPreview] = useState(null)
  const [busy, setBusy] = useState(false)
  const [clients, setClients] = useState({ requireApproval: false, clients: [] })
  const [totp, setTotp] = useState({ enrolled: false, enabled: false })
  const [totpEnroll, setTotpEnroll] = useState(null)
  const [totpCode, setTotpCode] = useState('')
  const [totpGate, setTotpGate] = useState(false)
  const [totpOk, setTotpOk] = useState(sessionStorage.getItem('exfin_totp_ok') === '1')

  const selected = useMemo(
    () => apps.find((a) => a.alias === selectedAlias) || apps[0] || null,
    [apps, selectedAlias]
  )

  const note = (msg, kind = '') => {
    setStatus(msg)
    setStatusKind(kind)
  }

  const loadApps = useCallback(async () => {
    const res = await fetch('/api/apps')
    const data = await readJson(res)
    const list = data.apps || []
    setApps(list)
    setSelectedAlias((cur) => {
      if (cur && list.some((a) => a.alias === cur)) return cur
      return list[0]?.alias || ''
    })
    return list
  }, [])

  const fillCustomer = (p, id) => {
    const list = p.customers || []
    const c = list.find((x) => x.id === id) || list[0]
    if (!c) return
    setCustomerId(c.id)
    setForm({
      name: c.name || '',
      publicIp: c.publicIp || '',
      lanIp: c.lanIp || '',
      vpnIp: c.vpnIp || '',
      rdpPort: c.rdpPort || 3389,
      lanRdpPort: c.lanRdpPort || 3389,
      connectMode: c.connectMode || 'direct',
      gatewayHost: c.gatewayHost || c.publicIp || '',
      gatewayPort: c.gatewayPort || 443,
      webKind: c.webKind || 'auto',
      webUrl: c.webUrl || ''
    })
  }

  const loadPortal = useCallback(async () => {
    const res = await fetch('/api/portal')
    const data = await readJson(res)
    setPortal(data)
    setWebPort(data.webPort || 8001)
    fillCustomer(data, customerId)
  }, [customerId])

  const loadFiles = useCallback(async () => {
    const q = '?customer=' + encodeURIComponent(customerId || 'default')
    const res = await fetch('/rdp' + q)
    const data = await readJson(res)
    const all = data.files || []
    const filtered = selectedAlias ? all.filter((f) => f.alias === selectedAlias) : all
    setFiles(filtered.length ? filtered : all)
  }, [customerId, selectedAlias])

  const loadClients = async () => {
    const res = await fetch('/api/clients', { headers: authHeaders() })
    const data = await readJson(res)
    if (res.ok) setClients(data)
  }

  const loadTotp = async () => {
    const res = await fetch('/api/totp', { headers: authHeaders() })
    const data = await readJson(res)
    if (res.ok) {
      setTotp(data)
      if (data.enabled && sessionStorage.getItem('exfin_totp_ok') !== '1') setTotpGate(true)
    }
  }

  useEffect(() => {
    fetch('/health').then(readJson).then(setHealth).catch(() => setHealth({ ok: false }))
    loadApps().catch((e) => note('Uygulamalar yuklenemedi: ' + e, 'err'))
    loadPortal().catch((e) => note('Portal yuklenemedi: ' + e, 'err'))
    loadClients().catch(() => {})
    loadTotp().catch(() => {})
  }, [loadApps, loadPortal])

  const loadWeb = useCallback(async () => {
    const q = '?customer=' + encodeURIComponent(customerId || 'default')
    const res = await fetch('/api/web' + q)
    const data = await readJson(res)
    if (res.ok) setWebInfo(data)
  }, [customerId])

  useEffect(() => { loadFiles().catch(() => {}) }, [loadFiles])
  useEffect(() => { loadWeb().catch(() => {}) }, [loadWeb])

  const pickApp = (app) => {
    setSelectedAlias(app.alias)
    setPath(app.path || '')
    setAlias(app.alias || '')
    setAppName(app.name || '')
    setIconPath(app.iconPath || app.path || '')
  }

  const loadBrowse = async (p) => {
    const url = '/api/browse' + (p ? ('?path=' + encodeURIComponent(p)) : '')
    const res = await fetch(url, { headers: authHeaders() })
    const data = await readJson(res)
    if (!res.ok) {
      note(data.hint || data.error || 'Klasor acilamadi.', 'err')
      return
    }
    setBrowse(data)
  }

  const openBrowse = async (start, mode = 'exe') => {
    setBrowseMode(mode)
    setPreview(null)
    setBrowseOpen(mode !== 'files')
    const p = start || (path && path.lastIndexOf('\\') > 2 ? path.slice(0, path.lastIndexOf('\\')) : 'C:\\LOGO')
    await loadBrowse(p)
  }

  useEffect(() => {
    if (tab !== 'files') return
    setBrowseMode('files')
    setBrowseOpen(false)
    if (browse && browse.path) return
    loadBrowse('C:\\').catch(() => {})
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tab])

  const chooseFile = async (entry) => {
    if (entry.kind === 'dir') {
      setPreview(null)
      loadBrowse(entry.path)
      return
    }
    if (browseMode === 'icon') {
      setIconPath(entry.path)
      setBrowseOpen(false)
      note('Ikon secildi: ' + entry.path)
      return
    }
    if (browseMode === 'files') {
      if (canPreview(entry)) {
        const res = await fetch('/api/file?path=' + encodeURIComponent(entry.path), { headers: authHeaders() })
        const data = await readJson(res)
        if (res.ok) setPreview({ name: data.name || entry.name, path: data.path || entry.path, content: data.content || '' })
        else note(data.error || 'Onizleme yok', 'err')
        return
      }
      note('Metin onizlemesi yok: ' + entry.name)
      return
    }
    if (entry.extension === '.exe' || browseMode === 'exe') {
      setPath(entry.path)
      const base = entry.name.replace(/\.exe$/i, '')
      if (!alias) setAlias(base.replace(/[^A-Za-z0-9]/g, '') || 'App')
      if (!appName) setAppName(base)
      setIconPath((cur) => cur || entry.path)
      setBrowseOpen(false)
      note('Dosya secildi: ' + entry.path)
    }
  }

  const publish = async () => {
    setBusy(true)
    note('Yayinlaniyor...')
    try {
      const res = await fetch('/api/apps', {
        method: 'POST',
        headers: authHeaders(),
        body: JSON.stringify({ path, alias, name: appName, iconPath })
      })
      const data = await readJson(res)
      if (!res.ok) { note('Yayin reddedildi: ' + (data.error || res.status), 'err'); return }
      note('Yayinlandi: ' + data.name + ' (' + data.alias + ')', 'ok')
      await loadApps()
      setSelectedAlias(data.alias)
    } catch (e) { note('Hata: ' + e, 'err') }
    finally { setBusy(false) }
  }

  const saveIcon = async () => {
    if (!selectedAlias && !alias) return
    setBusy(true)
    try {
      const res = await fetch('/api/apps', {
        method: 'POST',
        headers: authHeaders(),
        body: JSON.stringify({ action: 'icon', alias: selectedAlias || alias, iconPath: iconPath || path })
      })
      const data = await readJson(res)
      if (!res.ok) { note('Ikon kaydedilemedi: ' + (data.error || res.status), 'err'); return }
      note('Ikon guncellendi.', 'ok')
      await loadApps()
      if (data.iconPath) setIconPath(data.iconPath)
      setIconNonce((n) => n + 1)
    } catch (e) { note('Hata: ' + e, 'err') }
    finally { setBusy(false) }
  }

  const saveCustomer = async () => {
    setBusy(true)
    note('Kaydediliyor...')
    try {
      const body = {
        webPort: parseInt(webPort, 10) || 8001,
        customer: {
          id: customerId,
          name: form.name.trim() || customerId,
          publicIp: form.publicIp.trim(),
          lanIp: form.lanIp.trim(),
          vpnIp: form.vpnIp.trim(),
          rdpPort: parseInt(form.rdpPort, 10),
          lanRdpPort: parseInt(form.lanRdpPort, 10),
          connectMode: form.connectMode || 'direct',
          gatewayHost: (form.gatewayHost || '').trim(),
          gatewayPort: parseInt(form.gatewayPort, 10) || 443,
          webKind: form.webKind || 'auto',
          webUrl: (form.webUrl || '').trim()
        }
      }
      const res = await fetch('/api/portal', { method: 'POST', headers: authHeaders(), body: JSON.stringify(body) })
      const data = await readJson(res)
      if (!res.ok) { note('Kayit reddedildi: ' + (data.error || res.status), 'err'); return }
      setPortal(data)
      note('Musteri kaydedildi.', 'ok')
      await loadFiles()
      await loadWeb()
    } catch (e) { note('Hata: ' + e, 'err') }
    finally { setBusy(false) }
  }

  const addCustomer = () => {
    const name = window.prompt('Yeni musteri adi')
    if (!name) return
    const id = name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '') || 'musteri'
    const merged = {
      ...portal,
      customers: [...(portal.customers || []), {
        id, name, publicIp: form.publicIp, lanIp: form.lanIp, vpnIp: form.vpnIp,
        rdpPort: 3389, lanRdpPort: form.lanRdpPort || 3389
      }]
    }
    setPortal(merged)
    fillCustomer(merged, id)
    note('Form dolduruldu. Kaydet ile kalici olur.')
  }

  const setClientAction = async (id, action) => {
    const res = await fetch('/api/clients', {
      method: 'POST', headers: authHeaders(),
      body: JSON.stringify({ id, action })
    })
    const data = await readJson(res)
    if (res.ok) setClients(data)
    else note(data.error || 'Izin guncellenemedi', 'err')
  }

  const toggleApproval = async () => {
    const res = await fetch('/api/clients', {
      method: 'POST', headers: authHeaders(),
      body: JSON.stringify({ requireApproval: !clients.requireApproval })
    })
    const data = await readJson(res)
    if (res.ok) setClients(data)
  }

  const startTotp = async () => {
    const res = await fetch('/api/totp', {
      method: 'POST', headers: authHeaders(),
      body: JSON.stringify({ action: 'enroll' })
    })
    const data = await readJson(res)
    if (res.ok) setTotpEnroll(data)
    else note(data.error || 'TOTP baslatilamadi', 'err')
  }

  const confirmTotp = async () => {
    const res = await fetch('/api/totp', {
      method: 'POST', headers: authHeaders(),
      body: JSON.stringify({ action: 'confirm', code: totpCode })
    })
    const data = await readJson(res)
    if (!res.ok) { note(data.error || 'Kod hatali', 'err'); return }
    setTotp(data)
    setTotpEnroll(null)
    setTotpCode('')
    sessionStorage.setItem('exfin_totp_ok', '1')
    setTotpOk(true)
    setTotpGate(false)
    note('Google Authenticator baglandi.', 'ok')
  }

  const verifyGate = async () => {
    const res = await fetch('/api/totp', {
      method: 'POST', headers: authHeaders(),
      body: JSON.stringify({ action: 'verify', code: totpCode })
    })
    const data = await readJson(res)
    if (!res.ok) { note(data.error || 'Kod hatali', 'err'); return }
    sessionStorage.setItem('exfin_totp_ok', '1')
    setTotpOk(true)
    setTotpGate(false)
    setTotpCode('')
  }

  const healthOk = health && (health.status === 'ok' || health.ok === true || health.service)

  const shownEntries = useMemo(() => {
    const raw = browse?.entries || []
    const filtered = raw.filter((e) => {
      if (browseMode === 'files') return true
      if (browseMode === 'icon') {
        const ext = (e.extension || '').toLowerCase()
        return e.kind === 'dir' || ICON_EXTS.indexOf(ext) >= 0
      }
      return e.kind === 'dir' || e.extension === '.exe' || e.extension === '.rdp'
    })
    const rank = (e) => {
      if (browseMode === 'files') {
        if (e.kind !== 'dir' && canPreview(e)) return 0
        if (e.kind !== 'dir') return 1
        return 2
      }
      return e.kind === 'dir' ? 0 : 1
    }
    return filtered.slice().sort((a, b) => {
      const d = rank(a) - rank(b)
      if (d !== 0) return d
      return String(a.name || '').localeCompare(String(b.name || ''), 'tr')
    })
  }, [browse, browseMode])

  const iconCacheKey = (iconPath || path || '') + '#' + iconNonce
  const renderBrowser = (embedded) => (
    <>
      <div className="crumbs">
        {(browse?.roots || []).map((r) => (
          <button key={r.path} type="button" onClick={() => { setPreview(null); loadBrowse(r.path) }}>{r.name}</button>
        ))}
        {browse?.parent && (
          <button type="button" className="ghost" onClick={() => { setPreview(null); loadBrowse(browse.parent) }}>Ust klasor</button>
        )}
        {!embedded && (
          <button type="button" className="ghost" onClick={() => setBrowseOpen(false)}>Kapat</button>
        )}
      </div>
      <p className="status">{browse?.path || 'Yukleniyor...'}</p>
      <div className="browser">
        {shownEntries.map((e) => (
          <button
            key={e.path}
            type="button"
            className={'entry' + (e.kind === 'dir' ? ' is-dir' : '') + (canPreview(e) ? ' is-text' : '')}
            onClick={() => chooseFile(e)}
          >
            <span className="kind">
              {e.kind === 'dir' ? 'Klasor' : (canPreview(e) ? 'Metin' : (e.extension || 'dosya'))}
            </span>
            <b>{e.name}</b>
            <small>{e.kind === 'file' ? formatSize(e.size) : (e.kind === 'dir' ? 'Klasor' : '')}</small>
          </button>
        ))}
      </div>
      {shownEntries.length === 0 && browse?.path && (
        <p className="browser-empty">Bu klasor bos. Metin dosyalari icin Ust klasor veya bir surucu secin.</p>
      )}
    </>
  )

  if (totpGate && totp.enabled && !totpOk) {
    return (
      <div className="app gate">
        <div className="card gate-card">
          <h1>EXFIN RemoteAPP</h1>
          <p>Google Authenticator kodunu girin.</p>
          <input value={totpCode} onChange={(e) => setTotpCode(e.target.value)} placeholder="123456" maxLength={8} />
          <div className="actions">
            <button type="button" onClick={verifyGate}>Giris</button>
          </div>
          <p className={'status ' + statusKind}>{status}</p>
        </div>
      </div>
    )
  }

  return (
    <div className="app">
      <header className="top">
        <div className="brand">
          <strong>EXFIN RemoteAPP</strong>
          <span>Uygulama, ikon, dosya ve istemci izni</span>
        </div>
        <nav className="tabs">
          {[['apps', 'Uygulamalar'], ['web', 'Web RDP'], ['files', 'Dosyalar'], ['icons', 'Ikonlar'], ['clients', 'Istemciler'], ['security', 'Guvenlik']].map(([id, label]) => (
            <button key={id} type="button" className={tab === id ? 'on' : ''} onClick={() => setTab(id)}>{label}</button>
          ))}
        </nav>
        <div className="health">
          <span className={'dot ' + (healthOk ? 'ok' : 'bad')} />
          {healthOk ? 'API calisiyor' : 'API bekleniyor'}
        </div>
      </header>

      <div className="layout">
        <aside className="col">
          <h2>Uygulamalar</h2>
          <div className="apps">
            {apps.length === 0 && <p className="empty">Henuz yayinli uygulama yok.</p>}
            {apps.map((app) => (
              <button
                key={app.alias}
                className={'app-card' + (selected && selected.alias === app.alias ? ' selected' : '')}
                onClick={() => pickApp(app)}
                type="button"
              >
                <span className="app-card-row">
                  <AppIcon
                    key={app.alias + '|' + (app.iconPath || app.path || '') + '|' + iconNonce}
                    alias={app.alias}
                    path={app.iconPath || app.path}
                  />
                  <span>
                    <b>{app.name || app.alias}</b>
                    <small>{app.path || app.alias}</small>
                  </span>
                </span>
              </button>
            ))}
          </div>
        </aside>

        <main className="col">
          {tab === 'apps' && (
            <>
              <div className="card">
                <h3>Uygulama dosyasi</h3>
                <label>Sunucu EXE yolu</label>
                <input value={path} onChange={(e) => setPath(e.target.value)} />
                <div className="row">
                  <div><label>Alias</label><input value={alias} onChange={(e) => setAlias(e.target.value)} /></div>
                  <div><label>Gorunen ad</label><input value={appName} onChange={(e) => setAppName(e.target.value)} /></div>
                </div>
                <div className="actions">
                  <button type="button" onClick={() => openBrowse(null, 'exe')} disabled={busy}>Open File</button>
                  <button type="button" className="secondary" onClick={publish} disabled={busy || !path}>Uygulamayi yayinla</button>
                </div>
              </div>
              <div className="card">
                <h3>Secili uygulama — .rdp indir</h3>
                <p className="status">{selected ? (selected.name + ' · ' + (selected.path || selected.alias)) : 'Bir uygulama secin'}</p>
                <ul className="files">
                  {files.map((f) => (
                    <li key={f.url}><a href={f.url}>{f.name} — {f.label} ({f.host}:{f.port})</a></li>
                  ))}
                </ul>
                <div className="actions">
                  <a className="btn" href={'/web?customer=' + encodeURIComponent(customerId)} target="_blank" rel="noreferrer">Web giris sayfasi</a>
                  <a className="btn" href={'/rdp/' + encodeURIComponent((selectedAlias || 'app').toLowerCase()) + '-gateway.rdp?customer=' + encodeURIComponent(customerId)}>Gateway .rdp</a>
                  <a className="btn" href={'/rdp/public.rdp?customer=' + encodeURIComponent(customerId)}>Public</a>
                  <a className="btn secondary" href={'/rdp/lan.rdp?customer=' + encodeURIComponent(customerId)}>LAN</a>
                  <a className="btn secondary" href={'/rdp/vpn.rdp?customer=' + encodeURIComponent(customerId)}>VPN</a>
                </div>
              </div>
            </>
          )}

          {tab === 'web' && (
            <div className="card">
              <h3>Web RDP — tarayicidan giris</h3>
              <p className="status">
                Kullanicilar <a href={'/web?customer=' + encodeURIComponent(customerId)} target="_blank" rel="noreferrer">/web</a> sayfasini acar.
                HTML5 icin RD Web Client veya Guacamole (8443) gerekir. Bu sunucuda Gateway servisi
                {webInfo && webInfo.gatewayRunning ? ' calisiyor' : ' yok'}.
              </p>
              {webInfo && (
                <ul className="files">
                  <li>Algilanan: {webInfo.resolvedKind}</li>
                  <li>Gateway: {webInfo.gatewayHost}:{webInfo.gatewayPort} {webInfo.gatewayRunning ? '(servis acik)' : '(servis kapali)'}</li>
                  <li>RD Web HTML5: {webInfo.rdWebHtml5 ? 'var' : 'yok'}</li>
                  <li>Guacamole 8443: {webInfo.guacamole ? 'acik' : 'kapali'}</li>
                </ul>
              )}
              {webInfo && webInfo.hint && <p className="status">{webInfo.hint}</p>}
              <div className="actions">
                <a className="btn" href={'/web?customer=' + encodeURIComponent(customerId)} target="_blank" rel="noreferrer">Kullanici web girisi</a>
                {webInfo && webInfo.launchPublic && (
                  <a className="btn secondary" href={webInfo.launchPublic} target="_blank" rel="noreferrer">Public web URL</a>
                )}
                {webInfo && webInfo.launchLan && window.location.hostname !== webInfo.publicIp && (
                  <a className="btn secondary" href={webInfo.launchLan} target="_blank" rel="noreferrer">LAN web URL</a>
                )}
              </div>
            </div>
          )}

          {tab === 'files' && (
            <div className="card">
              <h3>Sunucu dosyalari — tanitmadan gor</h3>
              <p className="status">EXE yayinlamadan klasorleri ve metin dosyalarini acabilirsiniz (txt, log, csv, json, xml, ini, rdp, ps1, md).</p>
              <div className="actions">
                <button type="button" onClick={() => openBrowse('C:\\', 'files')}>Open File</button>
              </div>
              {renderBrowser(true)}
              {preview && (
                <div className="preview">
                  <h4>{preview.name}</h4>
                  <p className="tiny">{preview.path}</p>
                  <pre>{preview.content}</pre>
                </div>
              )}
            </div>
          )}

          {tab === 'icons' && (
            <div className="card">
              <h3>Ikon paneli</h3>
              <div className="icon-preview">
                <AppIcon
                  key={(selectedAlias || alias) + '|' + iconCacheKey}
                  alias={selectedAlias || alias}
                  path={iconPath || path}
                  size={64}
                />
                <div className="icon-path-field">
                  <label>Ikon dosyasi (.ico / .exe / .png)</label>
                  <input value={iconPath} onChange={(e) => setIconPath(e.target.value)} placeholder="C:\..." />
                </div>
              </div>
              <div className="actions">
                <button type="button" onClick={() => openBrowse(null, 'icon')}>Ikon sec (Open File)</button>
                <button type="button" className="secondary" onClick={saveIcon} disabled={busy}>Ikonu kaydet</button>
              </div>
            </div>
          )}

          {tab === 'clients' && (
            <div className="card">
              <h3>Istemci kayitlari — giris izni</h3>
              <label className="check">
                <input type="checkbox" checked={!!clients.requireApproval} onChange={toggleApproval} />
                Onaysiz istemci .rdp indiremesin
              </label>
              <table className="grid">
                <thead>
                  <tr><th>Bilgisayar</th><th>Kullanici</th><th>Durum</th><th></th></tr>
                </thead>
                <tbody>
                  {(clients.clients || []).map((c) => (
                    <tr key={c.id}>
                      <td>{c.hostname}<div className="tiny">{c.machineId}</div></td>
                      <td>{c.username}</td>
                      <td>{c.status}</td>
                      <td>
                        <button type="button" onClick={() => setClientAction(c.id, 'approve')}>Izin ver</button>
                        <button type="button" className="secondary" onClick={() => setClientAction(c.id, 'deny')}>Reddet</button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
              {(clients.clients || []).length === 0 && <p className="empty">Henuz istemci kaydi yok. Client kurulumu sunucuya pending kayit gonderir.</p>}
            </div>
          )}

          {tab === 'security' && (
            <div className="card">
              <h3>Google Authenticator</h3>
              <p className="status">
                {totp.enabled ? 'Bagli. Panel girisinde 6 haneli kod istenir.' : 'Henuz baglanmadi.'}
              </p>
              <div className="actions">
                <button type="button" onClick={startTotp}>QR olustur</button>
              </div>
              {totpEnroll && (
                <div className="totp-box">
                  <img
                    alt="QR"
                    width={180}
                    height={180}
                    src={'https://api.qrserver.com/v1/create-qr-code/?size=180x180&data=' + encodeURIComponent(totpEnroll.otpauth)}
                  />
                  <p>Google Authenticator ile tarayin. Anahtar: <code>{totpEnroll.secret}</code></p>
                  <input value={totpCode} onChange={(e) => setTotpCode(e.target.value)} placeholder="Onay kodu" />
                  <button type="button" onClick={confirmTotp}>Kodu onayla</button>
                </div>
              )}
            </div>
          )}
        </main>

        <aside className="col">
          <div className="card">
            <h3>Musteri</h3>
            <label>Musteri</label>
            <select value={customerId} onChange={(e) => fillCustomer(portal, e.target.value)}>
              {(portal.customers || []).map((c) => (
                <option key={c.id} value={c.id}>{c.name} ({c.id})</option>
              ))}
            </select>
            <label>Musteri adi</label>
            <input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} />
            <div className="row">
              <div><label>Public IP</label><input value={form.publicIp} onChange={(e) => setForm({ ...form, publicIp: e.target.value })} /></div>
              <div><label>LAN IP</label><input value={form.lanIp} onChange={(e) => setForm({ ...form, lanIp: e.target.value })} /></div>
            </div>
            <label>VPN IP</label>
            <input value={form.vpnIp} onChange={(e) => setForm({ ...form, vpnIp: e.target.value })} />
            <div className="row">
              <div><label>WAN RDP portu</label><input type="number" value={form.rdpPort} onChange={(e) => setForm({ ...form, rdpPort: e.target.value })} /></div>
              <div><label>LAN/VPN RDP portu</label><input type="number" value={form.lanRdpPort} onChange={(e) => setForm({ ...form, lanRdpPort: e.target.value })} /></div>
            </div>
            <label>Baglanti modu</label>
            <select value={form.connectMode} onChange={(e) => setForm({ ...form, connectMode: e.target.value })}>
              <option value="direct">Direct (WAN RDP portu)</option>
              <option value="gateway">RD Gateway (TCP 443)</option>
              <option value="web">Web RDP (tarayici)</option>
            </select>
            <div className="row">
              <div><label>Gateway host</label><input value={form.gatewayHost} onChange={(e) => setForm({ ...form, gatewayHost: e.target.value })} placeholder="185.86.15.238" /></div>
              <div><label>Gateway port</label><input type="number" value={form.gatewayPort} onChange={(e) => setForm({ ...form, gatewayPort: e.target.value })} /></div>
            </div>
            <label>Web RDP turu</label>
            <select value={form.webKind} onChange={(e) => setForm({ ...form, webKind: e.target.value })}>
              <option value="auto">Otomatik</option>
              <option value="rdweb">RD Web</option>
              <option value="guacamole">Guacamole (8443)</option>
              <option value="custom">Ozel URL</option>
            </select>
            <label>Ozel web URL (opsiyonel)</label>
            <input value={form.webUrl} onChange={(e) => setForm({ ...form, webUrl: e.target.value })} placeholder="https://..." />
            <label>Web portu</label>
            <input type="number" value={webPort} onChange={(e) => setWebPort(e.target.value)} />
            <label>Yonetici token</label>
            <input type="password" value={token} onChange={(e) => { setToken(e.target.value); sessionStorage.setItem('rdpvb_token', e.target.value) }} />
            <div className="actions">
              <button type="button" onClick={saveCustomer} disabled={busy}>Kaydet</button>
              <button type="button" className="secondary" onClick={addCustomer}>Yeni musteri</button>
            </div>
            <p className={'status ' + statusKind}>{status}</p>
          </div>
        </aside>
      </div>

      {browseOpen && (
        <div className="modal-back" onClick={() => setBrowseOpen(false)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <h3>Open File — {browseMode === 'files' ? 'tum dosyalar' : browseMode === 'icon' ? 'ikon' : 'uygulama'}</h3>
            {renderBrowser(false)}
            {preview && browseMode === 'files' && (
              <div className="preview"><h4>{preview.name}</h4><pre>{preview.content}</pre></div>
            )}
          </div>
        </div>
      )}
    </div>
  )
}
