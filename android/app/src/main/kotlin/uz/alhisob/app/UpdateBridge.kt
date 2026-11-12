package uz.alhisob.app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Мост Flutter ↔ Android для автообновления: архитектура телефона и запуск
 * системной установки скачанного APK.
 */
class UpdateBridge(private val activity: Activity) {

    companion object {
        const val CHANNEL = "uz.alhisob.app/update"
    }

    fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "supportedAbis" -> result.success(Build.SUPPORTED_ABIS.toList())
            "install" -> install(call.argument<String>("path"), result)
            "openInstallSettings" -> {
                openInstallSettings()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /** С Android 8 установка из приложения требует отдельного разрешения пользователя. */
    private fun canInstall(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            activity.packageManager.canRequestPackageInstalls()

    private fun install(path: String?, result: MethodChannel.Result) {
        if (path.isNullOrBlank()) {
            result.error("bad_args", "path is required", null)
            return
        }
        if (!canInstall()) {
            result.success("needs_permission")
            return
        }
        try {
            val file = File(path)
            if (!file.exists()) {
                result.success("error")
                return
            }
            val uri = FileProvider.getUriForFile(
                activity,
                "${activity.packageName}.fileprovider",
                file,
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            activity.startActivity(intent)
            result.success("started")
        } catch (e: Exception) {
            result.success("error")
        }
    }

    private fun openInstallSettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val intent = Intent(
            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
            Uri.parse("package:" + activity.packageName),
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        activity.startActivity(intent)
    }
}
