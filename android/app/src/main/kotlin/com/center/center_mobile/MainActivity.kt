package com.center.center_mobile

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray

class MainActivity : FlutterActivity() {

    /** ملفات مشارَكة نسخها [ShareActivity] تنتظر أن يأخذها Flutter (`take`). */
    private val shared = mutableListOf<Map<String, Any?>>()
    private var shareChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createSchoolChannel()
        // فتحٌ من «الأخيرة» يعيد آخر Intent: المشاركة نفسها لا تُستقبل مرتين
        val fromHistory = (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0
        if (savedInstanceState == null && !fromHistory) receiveShared(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        receiveShared(intent)
    }

    private fun receiveShared(intent: Intent?) {
        if (intent?.action != ACTION_SHARED) return
        val json = intent.getStringExtra(EXTRA_SHARED) ?: return
        intent.removeExtra(EXTRA_SHARED)
        val files = try {
            val arr = JSONArray(json)
            (0 until arr.length()).map { i ->
                val o = arr.getJSONObject(i)
                mapOf<String, Any?>(
                    "path" to o.optString("path", ""),
                    "name" to o.optString("name", ""),
                    "mime" to o.optString("mime", ""),
                    "size" to o.optLong("size", 0),
                    "error" to o.optString("error", ""),
                )
            }
        } catch (e: Exception) {
            emptyList()
        }
        if (files.isEmpty()) return
        // مشاركة جديدة تحل محل ما لم يُؤخذ بعد
        shared.clear()
        shared.addAll(files)
        shareChannel?.invokeMethod("ready", null)
    }

    /**
     * قناة إشعارات ولي الأمر (الغياب والأقساط) التي يذكرها الخادم في كل رسالة
     * (`channel_id` في push-notify). أهمية عالية: تظهر منبثقة بصوت.
     * إنشاؤها مرة ثانية لا يغيّر ما عدّله المستخدم فيها.
     */
    private fun createSchoolChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(SCHOOL_CHANNEL, "المدرسة", NotificationManager.IMPORTANCE_HIGH)
        getSystemService(NotificationManager::class.java)?.createNotificationChannel(channel)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DocumentsBridge.CHANNEL)
            .setMethodCallHandler(DocumentsBridge(this))
        StoreReferrer.register(this, flutterEngine)
        shareChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHARE_CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "take" -> {
                        val out = ArrayList(shared)
                        shared.clear()
                        result.success(out)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "show" -> {
                        askToNotify()
                        DownloadService.show(
                            this,
                            call.argument<String>("text") ?: "",
                            call.argument<Int>("percent") ?: -1,
                            call.argument<String>("title") ?: "تحديث التطبيق",
                        )
                        result.success(null)
                    }
                    "finish" -> {
                        DownloadService.finish(
                            this,
                            call.argument<String>("text") ?: "",
                            call.argument<String>("title") ?: "تحديث التطبيق",
                        )
                        result.success(null)
                    }
                    "hide" -> {
                        DownloadService.hide(this)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * إذن الإشعارات على أندرويد ١٣ فما فوق — يُطلب عند أول تنزيل لا عند الإقلاع:
     * نافذةٌ تسأل عن إشعارات بلا سببٍ ظاهر تُرفض، فيُفقد الإذن قبل الحاجة إليه.
     * ورفضه لا يُوقف التنزيل: الخدمة تعمل والتطبيق على الشاشة يعرض تقدّمه.
     */
    private fun askToNotify() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) return
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFY_REQUEST)
    }

    companion object {
        const val ACTION_SHARED = "com.center.center_mobile.SHARED"
        const val EXTRA_SHARED = "shared_files"
        private const val SHARE_CHANNEL = "center/share"
        private const val CHANNEL = "center/update_download"
        private const val SCHOOL_CHANNEL = "school"
        private const val NOTIFY_REQUEST = 4711
    }
}
