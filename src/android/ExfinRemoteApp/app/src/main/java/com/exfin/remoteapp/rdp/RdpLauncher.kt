package com.exfin.remoteapp.rdp

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import java.io.File

object RdpLauncher {
    private val rdPackages = listOf(
        "com.microsoft.rdc.androidx",
        "com.microsoft.rdc.android"
    )

    fun isRdClientInstalled(context: Context): Boolean {
        val pm = context.packageManager
        return rdPackages.any { pkg ->
            try {
                pm.getPackageInfo(pkg, 0)
                true
            } catch (_: Exception) {
                false
            }
        }
    }

    fun playStoreIntent(): Intent {
        val market = Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=com.microsoft.rdc.androidx"))
        market.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return market
    }

    fun openPlayStore(context: Context) {
        try {
            context.startActivity(playStoreIntent())
        } catch (_: ActivityNotFoundException) {
            val web = Intent(
                Intent.ACTION_VIEW,
                Uri.parse("https://play.google.com/store/apps/details?id=com.microsoft.rdc.androidx")
            )
            web.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(web)
        }
    }

    fun saveAndOpen(context: Context, fileName: String, content: String) {
        val remoteApp = content.contains("remoteapplicationmode:i:1", ignoreCase = true)
        if (!remoteApp) {
            throw IllegalStateException("Sunucu tam masaüstü .rdp gönderdi. RemoteApp bekleniyor.")
        }
        val safe = fileName.replace(Regex("[^A-Za-z0-9._-]"), "_").ifBlank { "app.rdp" }
        val dir = File(context.cacheDir, "rdp").apply { mkdirs() }
        val file = File(dir, safe)
        val normalized = content.replace("\r\n", "\n").replace("\r", "\n").replace("\n", "\r\n")
        file.writeText(normalized)
        val uri = FileProvider.getUriForFile(context, context.packageName + ".fileprovider", file)

        val view = Intent(Intent.ACTION_VIEW).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            setDataAndType(uri, "application/rdp")
        }
        val installed = rdPackages.firstOrNull { pkg ->
            try {
                context.packageManager.getPackageInfo(pkg, 0)
                true
            } catch (_: Exception) {
                false
            }
        }
        if (installed != null) {
            view.setPackage(installed)
            context.grantUriPermission(installed, uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }

        try {
            context.startActivity(view)
        } catch (_: ActivityNotFoundException) {
            view.setPackage(null)
            view.setDataAndType(uri, "application/x-rdp")
            try {
                val chooser = Intent.createChooser(view, "RemoteApp .rdp aç")
                chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(chooser)
            } catch (_: Exception) {
                openPlayStore(context)
            }
        }
    }

    fun openPortal(context: Context, url: String) {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }
}
