package com.exfin.remoteapp.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Cloud
import androidx.compose.material.icons.filled.Computer
import androidx.compose.material.icons.filled.Language
import androidx.compose.material.icons.filled.PhoneAndroid
import androidx.compose.material.icons.filled.Security
import androidx.compose.material.icons.filled.VpnKey
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.exfin.remoteapp.rdp.RdpLauncher

@Composable
fun WizardScreen(vm: WizardViewModel = viewModel()) {
    val state by vm.state.collectAsStateWithLifecycle()
    val colors = MaterialTheme.colorScheme

    Scaffold(
        containerColor = colors.background,
        topBar = {
            Column(
                Modifier
                    .fillMaxWidth()
                    .background(colors.surface)
                    .padding(horizontal = 20.dp, vertical = 16.dp)
            ) {
                Text("EXFIN RemoteAPP", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                Text("Android istemci · RemoteApp", color = colors.onSurfaceVariant, style = MaterialTheme.typography.bodyMedium)
                Spacer(Modifier.height(12.dp))
                StepDots(state.step)
            }
        }
    ) { pad ->
        Column(
            Modifier
                .fillMaxSize()
                .padding(pad)
                .imePadding()
                .padding(20.dp)
        ) {
            Column(
                Modifier
                    .weight(1f)
                    .verticalScroll(rememberScrollState())
            ) {
                when (state.step) {
                    1 -> StepServer(state, vm)
                    2 -> StepProbe(state, vm)
                    3 -> StepApps(state, vm)
                    else -> StepConnect(state, vm)
                }
            }
            Spacer(Modifier.height(12.dp))
            NavButtons(state, vm)
        }
    }
}

@Composable
private fun StepDots(step: Int) {
    val labels = listOf("Sunucu", "Tarama", "Uygulama", "Bağlan")
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
        labels.forEachIndexed { i, label ->
            val active = i + 1 == step
            val done = i + 1 < step
            Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                Box(
                    Modifier
                        .fillMaxWidth()
                        .height(4.dp)
                        .clip(RoundedCornerShape(4.dp))
                        .background(
                            when {
                                active || done -> MaterialTheme.colorScheme.primary
                                else -> MaterialTheme.colorScheme.outline
                            }
                        )
                )
                Spacer(Modifier.height(6.dp))
                Text(
                    label,
                    style = MaterialTheme.typography.labelSmall,
                    color = if (active) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

@Composable
private fun StepServer(state: WizardUiState, vm: WizardViewModel) {
    Text("Adım 1 · Sunucu", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
    Spacer(Modifier.height(8.dp))
    Text(
        "Probe API adresini girin. Varsayılan HTTP 8444’tür. Caddy HTTPS 8445 yalnızca geçerli sertifika varsa çalışır.",
        color = MaterialTheme.colorScheme.onSurfaceVariant
    )
    Spacer(Modifier.height(16.dp))
    OutlinedTextField(
        value = state.host,
        onValueChange = { vm.update { s -> s.copy(host = it) } },
        label = { Text("Sunucu IP / DNS") },
        placeholder = { Text("192.168.5.100") },
        singleLine = true,
        modifier = Modifier.fillMaxWidth()
    )
    Spacer(Modifier.height(10.dp))
    OutlinedTextField(
        value = state.port,
        onValueChange = { vm.update { s -> s.copy(port = it.filter { ch -> ch.isDigit() }.take(5)) } },
        label = { Text("Probe port") },
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
        singleLine = true,
        modifier = Modifier.fillMaxWidth()
    )
    Spacer(Modifier.height(10.dp))
    OutlinedTextField(
        value = state.username,
        onValueChange = { vm.update { s -> s.copy(username = it) } },
        label = { Text("Windows kullanıcı adı") },
        placeholder = { Text("exfin1") },
        singleLine = true,
        modifier = Modifier.fillMaxWidth()
    )
    Spacer(Modifier.height(10.dp))
    OutlinedTextField(
        value = state.token,
        onValueChange = { vm.update { s -> s.copy(token = it) } },
        label = { Text("Bearer token (isteğe bağlı)") },
        visualTransformation = PasswordVisualTransformation(),
        singleLine = true,
        modifier = Modifier.fillMaxWidth()
    )
    Spacer(Modifier.height(8.dp))
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
        Text("HTTPS kullan", modifier = Modifier.weight(1f))
        Switch(checked = state.useHttps, onCheckedChange = { vm.update { s -> s.copy(useHttps = it) } })
    }
}

@Composable
private fun StepProbe(state: WizardUiState, vm: WizardViewModel) {
    Text("Adım 2 · Sunucu taraması", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
    Spacer(Modifier.height(8.dp))
    Text("Probe API’den sağlık, yayınlı uygulamalar ve .rdp hedefleri alınır.", color = MaterialTheme.colorScheme.onSurfaceVariant)
    Spacer(Modifier.height(16.dp))
    Button(
        onClick = { vm.probe() },
        enabled = !state.probing && state.host.isNotBlank(),
        modifier = Modifier.fillMaxWidth()
    ) {
        if (state.probing) {
            CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp, color = MaterialTheme.colorScheme.onPrimary)
            Spacer(Modifier.width(8.dp))
        }
        Text(if (state.probing) "Taranıyor…" else "Sunucuyu tara")
    }
    state.probeError?.let {
        Spacer(Modifier.height(12.dp))
        StatusLine(it, error = true)
    }
    state.health?.let { h ->
        Spacer(Modifier.height(16.dp))
        InfoCard("Sunucu", h.hostname.ifBlank { state.host })
        InfoCard("Sürüm", h.version.ifBlank { "—" })
        InfoCard("Durum", h.status.ifBlank { "ok" })
        InfoCard("RDP dinleme", if (h.rdpPort > 0) h.rdpPort.toString() else "—")
        InfoCard("Uygulama sayısı", state.apps.size.toString())
    }
    if (state.customers.isNotEmpty()) {
        Spacer(Modifier.height(12.dp))
        Text("Müşteri", fontWeight = FontWeight.SemiBold)
        Spacer(Modifier.height(6.dp))
        Row(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.horizontalScroll(rememberScrollState())
        ) {
            state.customers.forEach { c ->
                FilterChip(
                    selected = state.customerId == c.id,
                    onClick = { vm.update { s -> s.copy(customerId = c.id) } },
                    label = { Text(c.name.ifBlank { c.id }) }
                )
            }
        }
    }
}

@Composable
private fun StepApps(state: WizardUiState, vm: WizardViewModel) {
    Text("Adım 3 · RemoteApp seçimi", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
    Spacer(Modifier.height(8.dp))
    Text("Yayınlı RemoteApp’lerden birini seçin. Telefonda tam masaüstü değil, seçilen uygulama açılır.", color = MaterialTheme.colorScheme.onSurfaceVariant)
    Spacer(Modifier.height(12.dp))
    if (state.apps.isEmpty()) {
        StatusLine("Henüz uygulama yok. Önce sunucuyu tarayın.", error = false)
    }
    state.apps.forEach { app ->
        val selected = app.alias.equals(state.selectedAlias, true)
        Row(
            Modifier
                .fillMaxWidth()
                .padding(vertical = 4.dp)
                .clip(RoundedCornerShape(12.dp))
                .border(
                    1.dp,
                    if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline,
                    RoundedCornerShape(12.dp)
                )
                .background(if (selected) Color(0xFF1E3A5F) else MaterialTheme.colorScheme.surface)
                .clickable { vm.update { s -> s.copy(selectedAlias = app.alias) } }
                .padding(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            val icon = state.icons[app.alias]
            if (icon != null) {
                Image(icon, contentDescription = null, modifier = Modifier.size(36.dp))
            } else {
                Icon(Icons.Default.Computer, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
            }
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(app.name, fontWeight = FontWeight.SemiBold)
                Text(app.alias, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodySmall)
            }
            if (selected) Icon(Icons.Default.CheckCircle, contentDescription = null, tint = MaterialTheme.colorScheme.secondary)
        }
    }
    Spacer(Modifier.height(16.dp))
    Text("Bağlantı yolu", fontWeight = FontWeight.SemiBold)
    Spacer(Modifier.height(6.dp))
    val kinds = state.rdpFiles
        .filter { it.alias.equals(state.selectedAlias, true) }
        .map { it.kind.lowercase() to it }
    if (kinds.isEmpty()) {
        StatusLine("Bu uygulama için .rdp hedefi yok. Sunucuyu yeniden tarayın.", error = false)
    } else {
        Row(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.horizontalScroll(rememberScrollState())
        ) {
            kinds.distinctBy { it.first }.forEach { (kind, file) ->
                FilterChip(
                    selected = state.kind.equals(kind, true),
                    onClick = { vm.update { s -> s.copy(kind = kind) } },
                    label = { Text(file.label.ifBlank { kind.uppercase() }) },
                    leadingIcon = {
                        Icon(
                            when (kind) {
                                "vpn" -> Icons.Default.VpnKey
                                "public" -> Icons.Default.Cloud
                                "gateway" -> Icons.Default.Security
                                "web" -> Icons.Default.Language
                                else -> Icons.Default.PhoneAndroid
                            },
                            contentDescription = null
                        )
                    }
                )
            }
        }
        val chosen = kinds.firstOrNull { it.first.equals(state.kind, true) }?.second
        if (chosen != null) {
            Spacer(Modifier.height(10.dp))
            InfoCard("Hedef", "${chosen.host}:${chosen.port}")
        }
    }
}

@Composable
private fun StepConnect(state: WizardUiState, vm: WizardViewModel) {
    val context = LocalContext.current
    val isWeb = state.kind.equals("web", true)
    val isGateway = state.kind.equals("gateway", true)
    Text("Adım 4 · Bağlan", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
    Spacer(Modifier.height(8.dp))
    Text(
        if (isWeb) {
            "HTML5 RD Web tarayıcıda açılır. Windows parolası web girişinde sorulur."
        } else {
            "Cihaz kaydedilir, RemoteApp .rdp indirilir ve Microsoft Remote Desktop / Windows App ile yalnızca seçilen uygulama açılır (tam masaüstü değil). Dışarıdan RD Gateway (TCP 443) kullanın. Windows parolası RDP istemcisinde sorulur."
        },
        color = MaterialTheme.colorScheme.onSurfaceVariant
    )
    Spacer(Modifier.height(16.dp))
    InfoCard("Cihaz", vm.deviceName)
    InfoCard("Uygulama", state.apps.firstOrNull { it.alias.equals(state.selectedAlias, true) }?.name ?: "—")
    InfoCard("Yol", state.rdpFiles.firstOrNull { it.alias.equals(state.selectedAlias, true) && it.kind.equals(state.kind, true) }?.label ?: state.kind.uppercase())
    Spacer(Modifier.height(8.dp))
    if (!isWeb && !state.rdClientInstalled) {
        StatusLine("Microsoft Remote Desktop yüklü değil. Play Store’dan ücretsiz kurun.", error = true)
        Spacer(Modifier.height(8.dp))
        OutlinedButton(onClick = { RdpLauncher.openPlayStore(context) }, modifier = Modifier.fillMaxWidth()) {
            Text("Remote Desktop’ı yükle")
        }
        Spacer(Modifier.height(8.dp))
    }
    Button(
        onClick = { vm.registerAndConnect() },
        enabled = !state.connecting && state.selectedAlias.isNotBlank(),
        modifier = Modifier.fillMaxWidth()
    ) {
        if (state.connecting) {
            CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp, color = MaterialTheme.colorScheme.onPrimary)
            Spacer(Modifier.width(8.dp))
        }
        Text(
            when {
                state.connecting -> "Bağlanılıyor…"
                isWeb -> "Web ile aç"
                else -> "Kaydet ve bağlan"
            }
        )
    }
    Spacer(Modifier.height(8.dp))
    OutlinedButton(onClick = { vm.openPortal() }, enabled = state.host.isNotBlank(), modifier = Modifier.fillMaxWidth()) {
        Text("Web giriş sayfasını aç")
    }
    if (isGateway) {
        Spacer(Modifier.height(8.dp))
        OutlinedButton(onClick = { vm.openGatewayCert() }, enabled = state.host.isNotBlank(), modifier = Modifier.fillMaxWidth()) {
            Text("Gateway sertifikasını indir")
        }
    }
    state.connectMessage?.let {
        Spacer(Modifier.height(12.dp))
        StatusLine(it, error = it.contains("onay") || it.startsWith("HTTP") || it.contains("başarısız") || it.contains("gerekir"))
    }
}

@Composable
private fun NavButtons(state: WizardUiState, vm: WizardViewModel) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        if (state.step > 1) {
            OutlinedButton(onClick = { vm.goBack() }, modifier = Modifier.weight(1f)) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
                Spacer(Modifier.width(6.dp))
                Text("Geri")
            }
        }
        if (state.step < 4) {
            Button(
                onClick = {
                    if (state.step == 1) vm.persistServer()
                    if (state.step == 1 && state.health == null && !state.probing) vm.probe()
                    vm.goNext()
                },
                enabled = state.host.isNotBlank(),
                modifier = Modifier.weight(1f)
            ) { Text("İleri") }
        }
    }
}

@Composable
private fun InfoCard(label: String, value: String) {
    Row(
        Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp)
            .clip(RoundedCornerShape(10.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant)
            .padding(12.dp)
    ) {
        Text(label, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.width(140.dp))
        Text(value, fontWeight = FontWeight.Medium)
    }
}

@Composable
private fun StatusLine(text: String, error: Boolean) {
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(10.dp))
            .background(if (error) Color(0x33F87171) else Color(0x3334D399))
            .padding(12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            if (error) Icons.Default.Warning else Icons.Default.CheckCircle,
            contentDescription = null,
            tint = if (error) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.secondary
        )
        Spacer(Modifier.width(8.dp))
        Text(text)
    }
}
