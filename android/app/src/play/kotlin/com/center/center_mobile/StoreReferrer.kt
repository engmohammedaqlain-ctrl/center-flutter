package com.center.center_mobile

import android.os.Handler
import android.os.Looper
import com.android.installreferrer.api.InstallReferrerClient
import com.android.installreferrer.api.InstallReferrerStateListener
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * نسخة المتجر: نص الإحالة الذي حمله رابط التنزيل (`referrer=school%3DCODE`)، فيُعرف
 * كود المدرسة من أول فتح (lib/data/school_brand.dart).
 * يعيد النص، أو "" إن لم يدعم المتجر ذلك، أو null إن تعذّر الاتصال الآن.
 */
object StoreReferrer {
    private const val CHANNEL = "center/install_referrer"

    fun register(activity: FlutterActivity, engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method != "get") return@setMethodCallHandler result.notImplemented()
            val main = Handler(Looper.getMainLooper())
            var answered = false
            fun answer(value: String?) = main.post {
                if (!answered) {
                    answered = true
                    result.success(value)
                }
            }
            val client = InstallReferrerClient.newBuilder(activity.applicationContext).build()
            try {
                client.startConnection(object : InstallReferrerStateListener {
                    override fun onInstallReferrerSetupFinished(code: Int) {
                        val value = when (code) {
                            InstallReferrerClient.InstallReferrerResponse.OK ->
                                try { client.installReferrer.installReferrer ?: "" } catch (_: Exception) { null }
                            InstallReferrerClient.InstallReferrerResponse.FEATURE_NOT_SUPPORTED -> ""
                            else -> null
                        }
                        client.endConnection()
                        answer(value)
                    }

                    override fun onInstallReferrerServiceDisconnected() {
                        answer(null)
                    }
                })
            } catch (_: Exception) {
                answer(null)
            }
        }
    }
}
