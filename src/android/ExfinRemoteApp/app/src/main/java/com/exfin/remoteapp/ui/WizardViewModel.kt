package com.exfin.remoteapp.ui

import android.app.Application
import android.graphics.BitmapFactory
import android.os.Build
import android.provider.Settings
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.exfin.remoteapp.data.CustomerInfo
import com.exfin.remoteapp.data.HealthInfo
import com.exfin.remoteapp.data.Prefs
import com.exfin.remoteapp.data.ProbeApi
import com.exfin.remoteapp.data.ProbeException
import com.exfin.remoteapp.data.RdpFileInfo
import com.exfin.remoteapp.data.RemoteAppInfo
import com.exfin.remoteapp.data.WebInfo
import com.exfin.remoteapp.rdp.RdpLauncher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

data class WizardUiState(
    val step: Int = 1,
    val host: String = "",
    val port: String = "8444",
    val useHttps: Boolean = false,
    val username: String = "",
    val token: String = "",
    val customerId: String = "",
    val kind: String = "lan",
    val selectedAlias: String = "",
    val probing: Boolean = false,
    val connecting: Boolean = false,
    val registering: Boolean = false,
    val probeError: String? = null,
    val connectMessage: String? = null,
    val health: HealthInfo? = null,
    val apps: List<RemoteAppInfo> = emptyList(),
    val customers: List<CustomerInfo> = emptyList(),
    val rdpFiles: List<RdpFileInfo> = emptyList(),
    val icons: Map<String, ImageBitmap> = emptyMap(),
    val rdClientInstalled: Boolean = false
)

class WizardViewModel(application: Application) : AndroidViewModel(application) {
    private val prefs = Prefs(application)
    private val _state = MutableStateFlow(
        WizardUiState(
            host = prefs.host,
            port = prefs.port.toString(),
            useHttps = prefs.useHttps,
            username = prefs.username,
            token = prefs.token,
            customerId = prefs.customerId,
            kind = prefs.kind,
            rdClientInstalled = RdpLauncher.isRdClientInstalled(application)
        )
    )
    val state: StateFlow<WizardUiState> = _state

    val machineId: String by lazy {
        Settings.Secure.getString(application.contentResolver, Settings.Secure.ANDROID_ID)
            ?: "android-unknown"
    }

    val deviceName: String
        get() = (Build.MANUFACTURER + " " + Build.MODEL).trim()

    fun update(block: (WizardUiState) -> WizardUiState) {
        _state.update(block)
    }

    fun persistServer() {
        val s = _state.value
        prefs.host = s.host
        prefs.port = s.port.toIntOrNull()?.coerceIn(1, 65535) ?: 8444
        prefs.useHttps = s.useHttps
        prefs.username = s.username
        prefs.token = s.token
        prefs.customerId = s.customerId
        prefs.kind = s.kind
    }

    private fun api(): ProbeApi {
        val s = _state.value
        val port = s.port.toIntOrNull()?.coerceIn(1, 65535) ?: 8444
        if (s.host.isBlank()) throw ProbeException("Sunucu adresi gerekli.")
        return ProbeApi(s.host.trim(), port, s.useHttps, s.token.ifBlank { null })
    }

    fun goNext() {
        _state.update { it.copy(step = (it.step + 1).coerceAtMost(4), probeError = null, connectMessage = null) }
    }

    fun goBack() {
        _state.update { it.copy(step = (it.step - 1).coerceAtLeast(1), probeError = null, connectMessage = null) }
    }

    fun probe() {
        persistServer()
        viewModelScope.launch {
            _state.update { it.copy(probing = true, probeError = null, connectMessage = null) }
            try {
                val result = withContext(Dispatchers.IO) {
                    val api = api()
                    val health = api.health()
                    val apps = api.apps()
                    val portal = runCatching { api.portal() }.getOrNull()
                    val customerId = _state.value.customerId.ifBlank {
                        portal?.customers?.firstOrNull()?.id.orEmpty()
                    }
                    val index = api.rdpIndex(customerId.ifBlank { null })
                    val icons = HashMap<String, ImageBitmap>()
                    for (app in apps) {
                        val bytes = api.iconPng(app.alias) ?: continue
                        val bmp = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: continue
                        icons[app.alias] = bmp.asImageBitmap()
                    }
                    ProbeBundle(health, apps, portal?.customers.orEmpty(), index.files, customerId.ifBlank { index.customerId }, icons)
                }
                _state.update {
                    val alias = it.selectedAlias.ifBlank { result.apps.firstOrNull()?.alias.orEmpty() }
                    val kinds = result.files.filter { f -> f.alias.equals(alias, true) }.map { f -> f.kind.lowercase() }
                    val kind = pickKind(kinds, it.kind)
                    it.copy(
                        probing = false,
                        health = result.health,
                        apps = result.apps,
                        customers = result.customers,
                        rdpFiles = result.files,
                        customerId = result.customerId.ifBlank { it.customerId },
                        selectedAlias = alias,
                        kind = kind,
                        icons = result.icons,
                        rdClientInstalled = RdpLauncher.isRdClientInstalled(getApplication())
                    )
                }
                persistServer()
            } catch (ex: Exception) {
                _state.update {
                    it.copy(
                        probing = false,
                        probeError = ex.message ?: "Sunucu taraması başarısız."
                    )
                }
            }
        }
    }

    fun registerAndConnect() {
        persistServer()
        val appCtx = getApplication<Application>()
        viewModelScope.launch {
            _state.update { it.copy(connecting = true, connectMessage = null, probeError = null) }
            try {
                val s = _state.value
                val app = s.apps.firstOrNull { it.alias.equals(s.selectedAlias, true) }
                    ?: throw ProbeException("Bir uygulama seçin.")
                val file = s.rdpFiles.firstOrNull {
                    it.alias.equals(s.selectedAlias, true) && it.kind.equals(s.kind, true)
                } ?: throw ProbeException("Bu uygulama için ${s.kind.uppercase()} kaydı yok.")
                val user = s.username.ifBlank { "android" }
                val clientKey = (machineId + "|" + user).lowercase()
                val isWeb = file.kind.equals("web", true) || file.url.contains("/web")
                withContext(Dispatchers.IO) {
                    val api = api()
                    runCatching {
                        api.registerClient(machineId, deviceName, user, listOf(app))
                    }
                    if (isWeb) {
                        val web = runCatching { api.webStatus(s.customerId.ifBlank { null }) }.getOrNull()
                        val url = pickWebUrl(s.host, s.customers.firstOrNull { it.id == s.customerId }, web, api.baseUrl, file.url)
                        withContext(Dispatchers.Main) {
                            RdpLauncher.openPortal(appCtx, url)
                        }
                    } else {
                        val content = api.downloadRdp(file.url, clientKey)
                        withContext(Dispatchers.Main) {
                            RdpLauncher.saveAndOpen(appCtx, file.fileName.ifBlank { "${app.alias}.rdp" }, content)
                        }
                    }
                }
                _state.update {
                    it.copy(
                        connecting = false,
                        connectMessage = if (isWeb) {
                            "Web HTML5 tarayıcıda açıldı."
                        } else {
                            "RemoteApp açılıyor: ${app.name} (tam masaüstü değil)."
                        }
                    )
                }
            } catch (ex: Exception) {
                _state.update {
                    it.copy(connecting = false, connectMessage = ex.message ?: "Bağlantı başarısız.")
                }
            }
        }
    }

    fun openPortal() {
        persistServer()
        val s = _state.value
        val scheme = if (s.useHttps) "https" else "http"
        val port = s.port.toIntOrNull() ?: 8444
        RdpLauncher.openPortal(getApplication(), "$scheme://${s.host.trim()}:$port/web")
    }

    fun openGatewayCert() {
        persistServer()
        val s = _state.value
        val scheme = if (s.useHttps) "https" else "http"
        val port = s.port.toIntOrNull() ?: 8444
        RdpLauncher.openPortal(getApplication(), "$scheme://${s.host.trim()}:$port/gateway.cer")
    }

    private fun pickKind(kinds: List<String>, saved: String): String {
        val lower = kinds.map { it.lowercase() }
        if (saved.lowercase() in lower) return saved.lowercase()
        for (k in listOf("gateway", "lan", "vpn", "public", "web")) {
            if (k in lower) return k
        }
        return lower.firstOrNull() ?: saved.ifBlank { "gateway" }
    }

    private fun pickWebUrl(
        probeHost: String,
        customer: CustomerInfo?,
        web: WebInfo?,
        baseUrl: String,
        relative: String
    ): String {
        val host = probeHost.trim()
        val lan = web?.launchLan.orEmpty()
        val pub = web?.launchPublic.orEmpty()
        val lanIp = customer?.lanIp.orEmpty()
        if (lan.isNotBlank() && (host == lanIp || host.startsWith("192.168.") || host.startsWith("10.") || host == "127.0.0.1")) {
            return lan
        }
        if (pub.isNotBlank()) return pub
        if (lan.isNotBlank()) return lan
        val path = if (relative.startsWith("/")) relative else "/$relative"
        return baseUrl + path
    }

    private data class ProbeBundle(
        val health: HealthInfo,
        val apps: List<RemoteAppInfo>,
        val customers: List<CustomerInfo>,
        val files: List<RdpFileInfo>,
        val customerId: String,
        val icons: Map<String, ImageBitmap>
    )
}
