package com.routercontroller.agent

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.core.content.FileProvider
import java.io.File
import java.net.URL

/**
 * Downloads an APK to app-private storage and hands it to the system
 * installer UI. This is only ever invoked from MainActivity's
 * "installApk" method call, which is only ever sent by
 * LanClientService.approveCommand() — i.e. after the user tapped
 * "Approve" on ApprovalScreen. The OS PackageInstaller then shows its
 * own confirmation dialog on top of that; there is no silent-install
 * path here.
 */
object ApkUpdateHelper {

    fun downloadAndRequestInstall(context: Context, url: String, version: String): Map<String, Any> {
        return try {
            val dir = File(context.getExternalFilesDir(null), "updates")
            if (!dir.exists()) dir.mkdirs()
            val file = File(dir, "router_controller_$version.apk")

            URL(url).openStream().use { input ->
                file.outputStream().use { output -> input.copyTo(output) }
            }

            val uri: Uri = FileProvider.getUriForFile(
                context, "${context.packageName}.fileprovider", file
            )

            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            context.startActivity(intent)

            mapOf("success" to true, "exitCode" to 0, "output" to "installer_launched", "error" to "")
        } catch (e: Exception) {
            mapOf("success" to false, "exitCode" to -1, "output" to "", "error" to (e.message ?: "download failed"))
        }
    }
}
