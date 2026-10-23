package com.center.center_mobile

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.net.Uri
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * رابط المدرسة (`https://noonschool.app/d/<الكود>`) يفتح التطبيق عليها، واختصارها على
 * الشاشة الرئيسية (lib/data/school_link.dart).
 *
 * الرابط يصل من App Links في نسخة المتجر (src/play/AndroidManifest.xml)، ومن الاختصار
 * المثبّت في كل النسخ. النص كاملاً يُسلَّم لـ Flutter وهو يقرأ الكود منه.
 */
class SchoolLinks(private val activity: Activity, engine: FlutterEngine) {

    private val channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)

    /** رابط الإقلاع: Flutter لم يبدأ بعد حين يصل، فيأخذه بـ `initial`. */
    private var pending: String? = null

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "initial" -> {
                    result.success(pending)
                    pending = null
                }
                "canPin" -> result.success(ShortcutManagerCompat.isRequestPinShortcutSupported(activity))
                "pin" -> result.success(
                    try {
                        pin(
                            call.argument<String>("code") ?: "",
                            call.argument<String>("name") ?: "",
                            call.argument<ByteArray>("logo"),
                        )
                    } catch (_: Exception) {
                        false
                    },
                )
                else -> result.notImplemented()
            }
        }
    }

    /** [initial] من `onCreate`: Flutter لم يسجّل مستمعه بعد، فيُحفظ حتى يسأل. */
    fun receive(intent: Intent?, initial: Boolean) {
        if (intent?.action != Intent.ACTION_VIEW) return
        val url = intent.dataString ?: return
        if (initial) pending = url else channel.invokeMethod("open", url)
    }

    private fun pin(code: String, name: String, logo: ByteArray?): Boolean {
        if (name.isBlank() || !ShortcutManagerCompat.isRequestPinShortcutSupported(activity)) return false
        val bitmap = logo?.let { BitmapFactory.decodeByteArray(it, 0, it.size) }
        // شعار SVG أو تالف: أيقونة التطبيق نفسها بدل مربع فارغ
        val icon = if (bitmap != null) {
            IconCompat.createWithAdaptiveBitmap(framed(bitmap))
        } else {
            IconCompat.createWithResource(activity, R.mipmap.ic_launcher)
        }
        val intent = (
            if (code.isEmpty()) {
                Intent(Intent.ACTION_MAIN)
            } else {
                Intent(Intent.ACTION_VIEW, Uri.parse("https://noonschool.app/d/" + Uri.encode(code)))
            }
            ).setClass(activity, MainActivity::class.java)
        val info = ShortcutInfoCompat.Builder(activity, "school-" + code.ifEmpty { "home" })
            .setShortLabel(name)
            .setLongLabel(name)
            .setIcon(icon)
            .setIntent(intent)
            .build()
        return ShortcutManagerCompat.requestPinShortcut(activity, info, null)
    }

    /**
     * أيقونة متكيّفة: خلفية بيضاء والشعار في وسطها داخل المنطقة الآمنة (ثلثا المساحة)،
     * فلا يقصّه قناع الشاشة الرئيسية أياً كان شكله.
     */
    private fun framed(src: Bitmap): Bitmap {
        val size = 432
        val out = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        canvas.drawColor(Color.WHITE)
        val box = size * 0.58f
        val scale = minOf(box / src.width, box / src.height)
        val w = src.width * scale
        val h = src.height * scale
        val left = (size - w) / 2f
        val top = (size - h) / 2f
        canvas.drawBitmap(src, null, RectF(left, top, left + w, top + h), Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG))
        return out
    }

    companion object {
        const val CHANNEL = "center/school_link"
    }
}
