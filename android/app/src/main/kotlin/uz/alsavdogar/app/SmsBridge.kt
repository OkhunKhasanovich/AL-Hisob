package uz.alsavdogar.app

import android.Manifest
import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.telephony.SmsManager
import android.telephony.SubscriptionInfo
import android.telephony.SubscriptionManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID
import java.util.concurrent.atomic.AtomicInteger

/**
 * Мост Flutter ↔ Android для SMS: разрешения, список SIM, отправка.
 *
 * Все методы отвечают через [MethodChannel.Result] ровно один раз.
 */
class SmsBridge(private val activity: Activity) {

    companion object {
        const val CHANNEL = "uz.alsavdogar.app/sms"
        private const val PERMISSIONS_REQUEST_CODE = 4101
        private const val SEND_TIMEOUT_MS = 60_000L
        private val requestCodes = AtomicInteger(1000)
        private val REQUIRED_PERMISSIONS = arrayOf(
            Manifest.permission.SEND_SMS,
            Manifest.permission.READ_PHONE_STATE,
        )
    }

    private val context: Context get() = activity.applicationContext
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pendingPermissionResult: MethodChannel.Result? = null

    fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "permissions" -> result.success(permissionState())
            "requestPermissions" -> requestPermissions(result)
            "listSims" -> listSims(result)
            "sendSms" -> sendSms(call, result)
            "openAppSettings" -> {
                openAppSettings()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    // ---------- разрешения ----------

    private fun granted(permission: String): Boolean =
        ContextCompat.checkSelfPermission(activity, permission) == PackageManager.PERMISSION_GRANTED

    private fun permissionState(): Map<String, Any> {
        val blocked = REQUIRED_PERMISSIONS.any {
            !granted(it) && !ActivityCompat.shouldShowRequestPermissionRationale(activity, it)
        }
        return mapOf(
            "canSend" to granted(Manifest.permission.SEND_SMS),
            "canListSims" to granted(Manifest.permission.READ_PHONE_STATE),
            // Осмысленно только сразу после запроса: «отказано и больше не спрашивать».
            "blockedForever" to blocked,
        )
    }

    private fun requestPermissions(result: MethodChannel.Result) {
        val missing = REQUIRED_PERMISSIONS.filter { !granted(it) }
        if (missing.isEmpty()) {
            result.success(permissionState())
            return
        }
        if (pendingPermissionResult != null) {
            result.error("busy", "A permission request is already in progress", null)
            return
        }
        pendingPermissionResult = result
        ActivityCompat.requestPermissions(activity, missing.toTypedArray(), PERMISSIONS_REQUEST_CODE)
    }

    fun onPermissionsResult(requestCode: Int) {
        if (requestCode != PERMISSIONS_REQUEST_CODE) return
        val pending = pendingPermissionResult ?: return
        pendingPermissionResult = null
        pending.success(permissionState())
    }

    private fun openAppSettings() {
        val intent = Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.parse("package:" + context.packageName),
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        activity.startActivity(intent)
    }

    // ---------- SIM-карты ----------

    private fun listSims(result: MethodChannel.Result) {
        if (!granted(Manifest.permission.READ_PHONE_STATE)) {
            result.success(emptyList<Map<String, Any>>())
            return
        }
        val manager = context.getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE)
            as? SubscriptionManager
        val subscriptions: List<SubscriptionInfo> = try {
            manager?.activeSubscriptionInfoList ?: emptyList()
        } catch (e: SecurityException) {
            emptyList()
        }
        val defaultId = SubscriptionManager.getDefaultSmsSubscriptionId()
        val sims = subscriptions.map { info ->
            mapOf(
                "subscriptionId" to info.subscriptionId,
                "slot" to info.simSlotIndex,
                "name" to (info.displayName?.toString() ?: ""),
                "carrier" to (info.carrierName?.toString() ?: ""),
                "isDefaultForSms" to (info.subscriptionId == defaultId),
            )
        }
        result.success(sims)
    }

    // ---------- отправка ----------

    @Suppress("DEPRECATION")
    private fun smsManagerFor(subscriptionId: Int?): SmsManager {
        val useModernApi = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S
        if (subscriptionId == null) {
            return if (useModernApi) {
                context.getSystemService(SmsManager::class.java)
            } else {
                SmsManager.getDefault()
            }
        }
        return if (useModernApi) {
            context.getSystemService(SmsManager::class.java).createForSubscriptionId(subscriptionId)
        } else {
            SmsManager.getSmsManagerForSubscriptionId(subscriptionId)
        }
    }

    private fun sendSms(call: MethodCall, result: MethodChannel.Result) {
        val phone = call.argument<String>("phone")
        val body = call.argument<String>("body")
        val subscriptionId = call.argument<Int>("subscriptionId")

        if (phone.isNullOrBlank() || body.isNullOrBlank()) {
            result.error("bad_args", "phone and body are required", null)
            return
        }
        if (!granted(Manifest.permission.SEND_SMS)) {
            result.success(mapOf("status" to "no_permission"))
            return
        }

        val manager: SmsManager
        val parts: ArrayList<String>
        try {
            manager = smsManagerFor(subscriptionId)
            parts = manager.divideMessage(body)
        } catch (e: Exception) {
            result.success(mapOf("status" to "failed", "message" to (e.message ?: "sms manager error")))
            return
        }

        val action = "${context.packageName}.SMS_SENT.${UUID.randomUUID()}"
        var remaining = parts.size
        var firstFailureCode: Int? = null
        var finished = false

        lateinit var receiver: BroadcastReceiver
        val finish: (Map<String, Any?>) -> Unit = { response ->
            if (!finished) {
                finished = true
                try {
                    context.unregisterReceiver(receiver)
                } catch (_: IllegalArgumentException) {
                    // уже снят
                }
                result.success(response)
            }
        }
        val timeout = Runnable {
            finish(mapOf("status" to "failed", "message" to "timeout"))
        }

        receiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context, intent: Intent) {
                if (resultCode != Activity.RESULT_OK && firstFailureCode == null) {
                    firstFailureCode = resultCode
                }
                remaining -= 1
                if (remaining <= 0) {
                    mainHandler.removeCallbacks(timeout)
                    val code = firstFailureCode
                    if (code == null) {
                        finish(mapOf("status" to "sent"))
                    } else {
                        finish(mapOf("status" to "failed", "code" to code, "message" to failureText(code)))
                    }
                }
            }
        }

        ContextCompat.registerReceiver(
            context,
            receiver,
            IntentFilter(action),
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
        mainHandler.postDelayed(timeout, SEND_TIMEOUT_MS)

        try {
            val sentIntents = ArrayList<PendingIntent>(parts.size)
            for (i in parts.indices) {
                val intent = Intent(action).setPackage(context.packageName)
                sentIntents.add(
                    PendingIntent.getBroadcast(
                        context,
                        requestCodes.incrementAndGet(),
                        intent,
                        PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE,
                    ),
                )
            }
            if (parts.size == 1) {
                manager.sendTextMessage(phone, null, parts[0], sentIntents[0], null)
            } else {
                manager.sendMultipartTextMessage(phone, null, parts, sentIntents, null)
            }
        } catch (e: Exception) {
            mainHandler.removeCallbacks(timeout)
            finish(mapOf("status" to "failed", "message" to (e.message ?: "send error")))
        }
    }

    private fun failureText(code: Int): String = when (code) {
        SmsManager.RESULT_ERROR_GENERIC_FAILURE -> "generic_failure"
        SmsManager.RESULT_ERROR_RADIO_OFF -> "radio_off"
        SmsManager.RESULT_ERROR_NULL_PDU -> "null_pdu"
        SmsManager.RESULT_ERROR_NO_SERVICE -> "no_service"
        else -> "error_$code"
    }
}
