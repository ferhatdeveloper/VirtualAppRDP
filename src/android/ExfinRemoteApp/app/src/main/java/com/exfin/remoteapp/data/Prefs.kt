package com.exfin.remoteapp.data

import android.content.Context

class Prefs(context: Context) {
    private val sp = context.getSharedPreferences("exfin_remoteapp", Context.MODE_PRIVATE)

    var host: String
        get() = sp.getString("host", "").orEmpty()
        set(value) { sp.edit().putString("host", value.trim()).apply() }

    var port: Int
        get() = sp.getInt("port", 8444)
        set(value) { sp.edit().putInt("port", value).apply() }

    var useHttps: Boolean
        get() = sp.getBoolean("https", false)
        set(value) { sp.edit().putBoolean("https", value).apply() }

    var username: String
        get() = sp.getString("username", "").orEmpty()
        set(value) { sp.edit().putString("username", value.trim()).apply() }

    var token: String
        get() = sp.getString("token", "").orEmpty()
        set(value) { sp.edit().putString("token", value.trim()).apply() }

    var customerId: String
        get() = sp.getString("customerId", "").orEmpty()
        set(value) { sp.edit().putString("customerId", value.trim()).apply() }

    var kind: String
        get() = sp.getString("kind", "lan").orEmpty().ifBlank { "lan" }
        set(value) { sp.edit().putString("kind", value).apply() }
}
