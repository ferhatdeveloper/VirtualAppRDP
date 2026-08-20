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
    val lanRdpPort: Int
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
