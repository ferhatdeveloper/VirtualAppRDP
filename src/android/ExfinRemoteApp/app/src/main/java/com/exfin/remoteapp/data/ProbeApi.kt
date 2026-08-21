package com.exfin.remoteapp.data

import android.util.Base64
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.net.URLEncoder
import java.util.concurrent.TimeUnit

class ProbeApi(
    private val host: String,
    private val port: Int,
    private val useHttps: Boolean,
    private val token: String?
) {
    private val client = OkHttpClient.Builder()
        .connectTimeout(12, TimeUnit.SECONDS)
        .readTimeout(20, TimeUnit.SECONDS)
        .writeTimeout(20, TimeUnit.SECONDS)
        .followRedirects(true)
        .build()

    val baseUrl: String
        get() {
            val scheme = if (useHttps) "https" else "http"
            return "$scheme://$host:$port"
        }

    fun health(): HealthInfo {
        val json = getJson("/health")
        return HealthInfo(
            status = json.optString("status"),
            version = json.optString("version"),
            hostname = json.optString("hostname"),
            port = json.optInt("port"),
            rdpPort = json.optInt("rdpPort")
        )
    }

    fun apps(): List<RemoteAppInfo> {
        val json = getJson("/api/apps")
        val arr = json.optJSONArray("apps") ?: JSONArray()
        val out = ArrayList<RemoteAppInfo>(arr.length())
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            val alias = o.optString("alias").ifBlank { o.optString("id") }
            if (alias.isBlank()) continue
            out.add(
                RemoteAppInfo(
                    id = o.optString("id").ifBlank { alias },
                    alias = alias,
                    name = o.optString("name").ifBlank { alias },
                    path = o.optString("path")
                )
            )
        }
        return out
    }

    fun portal(): PortalInfo {
        val json = getJson("/api/portal")
        val arr = json.optJSONArray("customers") ?: JSONArray()
        val customers = ArrayList<CustomerInfo>(arr.length())
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            val id = o.optString("id")
            if (id.isBlank()) continue
            customers.add(
                CustomerInfo(
                    id = id,
                    name = o.optString("name").ifBlank { id },
                    publicIp = o.optString("publicIp"),
                    lanIp = o.optString("lanIp"),
                    vpnIp = o.optString("vpnIp"),
                    rdpPort = o.optInt("rdpPort"),
                    lanRdpPort = o.optInt("lanRdpPort"),
                    connectMode = o.optString("connectMode").ifBlank { "direct" },
                    gatewayHost = o.optString("gatewayHost"),
                    gatewayPort = o.optInt("gatewayPort", 443)
                )
            )
        }
        return PortalInfo(
            webPort = json.optInt("webPort"),
            listenRdpPort = json.optInt("listenRdpPort"),
            customers = customers
        )
    }

    fun rdpIndex(customerId: String?): RdpIndex {
        val path = if (customerId.isNullOrBlank()) "/rdp" else "/rdp?customer=${enc(customerId)}"
        val json = getJson(path)
        val cust = json.optJSONObject("customer")
        val cid = cust?.optString("id").orEmpty().ifBlank { customerId.orEmpty() }
        val arr = json.optJSONArray("files") ?: JSONArray()
        val files = ArrayList<RdpFileInfo>(arr.length())
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            files.add(
                RdpFileInfo(
                    alias = o.optString("alias"),
                    name = o.optString("name"),
                    kind = o.optString("kind"),
                    label = o.optString("label"),
                    host = o.optString("host"),
                    port = o.optInt("port"),
                    fileName = o.optString("fileName"),
                    url = o.optString("url"),
                    customerId = o.optString("customerId").ifBlank { cid }
                )
            )
        }
        return RdpIndex(customerId = cid, files = files)
    }

    fun webStatus(customerId: String?): WebInfo {
        val path = if (customerId.isNullOrBlank()) "/api/web" else "/api/web?customer=${enc(customerId)}"
        val json = getJson(path)
        return WebInfo(
            resolvedKind = json.optString("resolvedKind"),
            gatewayHost = json.optString("gatewayHost"),
            gatewayPort = json.optInt("gatewayPort", 443),
            gatewayRunning = json.optBoolean("gatewayRunning"),
            rdWebHtml5 = json.optBoolean("rdWebHtml5"),
            launchLan = json.optString("launchLan"),
            launchPublic = json.optString("launchPublic"),
            hint = json.optString("hint")
        )
    }

    fun iconPng(alias: String): ByteArray? {
        if (alias.isBlank()) return null
        return try {
            val json = getJson("/api/icon?alias=${enc(alias)}")
            val b64 = json.optString("png")
            if (b64.isBlank()) null else Base64.decode(b64, Base64.DEFAULT)
        } catch (_: Exception) {
            null
        }
    }

    fun downloadRdp(relativeUrl: String, clientId: String?): String {
        var path = relativeUrl.trim()
        if (!path.startsWith("/")) path = "/$path"
        if (!clientId.isNullOrBlank()) {
            path += if (path.contains("?")) "&" else "?"
            path += "client=${enc(clientId)}"
        }
        path += if (path.contains("?")) "&" else "?"
        path += "platform=android"
        val req = authorized(Request.Builder().url(baseUrl + path).get())
        client.newCall(req.build()).execute().use { resp ->
            val body = resp.body?.string().orEmpty()
            if (resp.code == 403) {
                throw ProbeException("Bu cihaz henüz onaylanmadı. Yöneticinin panelde İstemciler sekmesinden izin vermesi gerekir.")
            }
            if (!resp.isSuccessful) {
                throw ProbeException(httpError(resp.code, body))
            }
            if (body.isBlank()) throw ProbeException("Sunucu boş .rdp döndürdü.")
            return body
        }
    }

    fun registerClient(
        machineId: String,
        hostname: String,
        username: String,
        apps: List<RemoteAppInfo>
    ) {
        val arr = JSONArray()
        for (app in apps) {
            arr.put(
                JSONObject()
                    .put("id", app.id)
                    .put("name", app.name)
                    .put("alias", app.alias)
            )
        }
        val payload = JSONObject()
            .put("machineId", machineId)
            .put("hostname", hostname)
            .put("username", username)
            .put("apps", arr)
            .toString()
        val req = authorized(
            Request.Builder()
                .url("$baseUrl/api/clients")
                .post(payload.toRequestBody(JSON))
        )
        client.newCall(req.build()).execute().use { resp ->
            val body = resp.body?.string().orEmpty()
            if (!resp.isSuccessful) {
                throw ProbeException(httpError(resp.code, body))
            }
        }
    }

    private fun getJson(path: String): JSONObject {
        val req = authorized(Request.Builder().url(baseUrl + path).get())
        client.newCall(req.build()).execute().use { resp ->
            val body = resp.body?.string().orEmpty()
            if (!resp.isSuccessful) {
                throw ProbeException(httpError(resp.code, body))
            }
            return try {
                JSONObject(body)
            } catch (ex: Exception) {
                throw ProbeException("Sunucu JSON döndürmedi: ${ex.message}")
            }
        }
    }

    private fun authorized(builder: Request.Builder): Request.Builder {
        builder.header("User-Agent", "EXFIN-RemoteAPP-Android/1.1.5")
        builder.header("Accept", "application/json, application/x-rdp, */*")
        val t = token?.trim().orEmpty()
        if (t.isNotEmpty()) builder.header("Authorization", "Bearer $t")
        return builder
    }

    private fun httpError(code: Int, body: String): String {
        val snippet = body.trim().replace("\n", " ").take(180)
        return if (snippet.isBlank()) "HTTP $code" else "HTTP $code: $snippet"
    }

    private fun enc(value: String): String =
        URLEncoder.encode(value, Charsets.UTF_8.name())

    companion object {
        private val JSON = "application/json; charset=utf-8".toMediaType()
    }
}
