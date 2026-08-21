package com.exfin.remoteapp.data

data class HealthInfo(
    val status: String,
    val version: String,
    val hostname: String,
    val port: Int,
    val rdpPort: Int
)

data class RemoteAppInfo(
    val id: String,
    val alias: String,
    val name: String,
    val path: String
)

data class CustomerInfo(
    val id: String,
    val name: String,
    val publicIp: String,
    val lanIp: String,
    val vpnIp: String,
    val rdpPort: Int,
    val lanRdpPort: Int,
    val connectMode: String = "direct",
    val gatewayHost: String = "",
    val gatewayPort: Int = 443
)

data class WebInfo(
    val resolvedKind: String,
    val gatewayHost: String,
    val gatewayPort: Int,
    val gatewayRunning: Boolean,
    val rdWebHtml5: Boolean,
    val launchLan: String,
    val launchPublic: String,
    val hint: String
)

data class PortalInfo(
    val webPort: Int,
    val listenRdpPort: Int,
    val customers: List<CustomerInfo>
)

data class RdpFileInfo(
    val alias: String,
    val name: String,
    val kind: String,
    val label: String,
    val host: String,
    val port: Int,
    val fileName: String,
    val url: String,
    val customerId: String
)

data class RdpIndex(
    val customerId: String,
    val files: List<RdpFileInfo>
)

class ProbeException(message: String) : Exception(message)
