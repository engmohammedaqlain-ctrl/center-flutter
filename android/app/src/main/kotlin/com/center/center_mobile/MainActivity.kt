package com.center.center_mobile

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
        private const val CHANNEL = "center/update_download"
        private const val NOTIFY_REQUEST = 4711
    }
}
