package com.center.center_mobile

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import android.widget.Toast
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream

/**
 * «مشاركة» من المعرض أو واتساب أو تطبيق البنك إلى التطبيق.
 *
 * نشاط شفاف لا يُرى: ينسخ الملفات المشارَكة إلى ذاكرة التطبيق المؤقتة فوراً (إذن
 * قراءة الرابط مؤقت وينتهي بإغلاق هذا النشاط)، ثم يفتح [MainActivity] في مهمّتها
 * هي بقائمة الملفات المنسوخة ويُغلق. لو استقبلت [MainActivity] المشاركة بنفسها
 * لفُتحت نسخة ثانية منها داخل مهمّة المعرض بمحرك Flutter ثانٍ.
 *
 * بلا أي إذن تخزين أو صور: روابط `content://` تصل بإذن قراءتها.
 */
class ShareActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val uris = sharedUris(intent)
        if (uris.isEmpty()) {
            finish()
            return
        }
        val fallbackMime = intent.type
        val app = applicationContext
        // ملفات كبيرة تأخذ ثواني: إشارة صغيرة بدل شاشة لا يتغير فيها شيء
        val main = Handler(Looper.getMainLooper())
        val notice = Runnable { Toast.makeText(app, "جارٍ تجهيز الملفات…", Toast.LENGTH_SHORT).show() }
        main.postDelayed(notice, 800)
        Thread {
            val files = try {
                SharedFiles.copy(app, uris, fallbackMime)
            } catch (e: Exception) {
                JSONArray()
            }
            main.post {
                main.removeCallbacks(notice)
                val open = Intent(app, MainActivity::class.java).apply {
                    action = MainActivity.ACTION_SHARED
                    putExtra(MainActivity.EXTRA_SHARED, files.toString())
                    // مهمّة التطبيق نفسها إن كانت مفتوحة، والنسخة القائمة تستقبلها في onNewIntent
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                }
                try {
                    if (isDestroyed) app.startActivity(open) else startActivity(open)
                } catch (e: Exception) {
                }
                finish()
                noAnimation()
            }
        }.start()
    }

    @Suppress("DEPRECATION")
    private fun noAnimation() = overridePendingTransition(0, 0)

    /** روابط المشاركة: EXTRA_STREAM (واحد أو قائمة) وClipData، بلا تكرار. */
    @Suppress("DEPRECATION")
    private fun sharedUris(intent: Intent?): List<Uri> {
        if (intent == null) return emptyList()
        val out = LinkedHashSet<Uri>()
        when (intent.action) {
            Intent.ACTION_SEND -> intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)?.let { out.add(it) }
            Intent.ACTION_SEND_MULTIPLE -> intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)?.let { out.addAll(it) }
            else -> return emptyList()
        }
        intent.clipData?.let { clip ->
            for (i in 0 until clip.itemCount) clip.getItemAt(i).uri?.let { out.add(it) }
        }
        return out.filter { it.scheme == "content" || it.scheme == "file" }.take(SharedFiles.MAX_FILES)
    }
}

/** نسخ ما شورك إلى `cache/shared/<وقت>/` ووصفه لـ Flutter. */
object SharedFiles {
    const val MAX_FILES = 20

    /** أكبر من حد الصورة الخام (40 ميجا) لا يُنسخ: Flutter يرفضه بسببه. */
    private const val MAX_BYTES = 40L * 1024 * 1024

    private val UPLOADABLE_IMAGES = setOf("image/jpeg", "image/png", "image/webp")

    fun copy(context: Context, uris: List<Uri>, fallbackMime: String?): JSONArray {
        val root = File(context.cacheDir, "shared")
        prune(root)
        val dir = File(root, System.currentTimeMillis().toString()).apply { mkdirs() }
        val out = JSONArray()
        uris.forEachIndexed { index, uri ->
            val o = JSONObject()
            var name = displayName(context, uri) ?: "ملف ${index + 1}"
            var mime = (context.contentResolver.getType(uri) ?: fallbackMime ?: "").lowercase()
            if (mime.endsWith("/*")) mime = ""
            try {
                val target = File(dir, "${index}_${safeName(name)}")
                val size = copyLimited(context, uri, target)
                if (size < 0) {
                    target.delete()
                    o.put("size", -1)
                } else if (mime.startsWith("image/") && mime !in UPLOADABLE_IMAGES) {
                    // HEIC من كاميرات سامسونج وغيرها: فلاتر لا يفكّها، فتُحوَّل هنا JPEG
                    val jpg = File(dir, "${index}_${safeName(stem(name))}.jpg")
                    if (toJpeg(target, jpg)) {
                        target.delete()
                        name = "${stem(name)}.jpg"
                        mime = "image/jpeg"
                        o.put("path", jpg.path)
                        o.put("size", jpg.length())
                    } else {
                        o.put("path", target.path)
                        o.put("size", size)
                    }
                } else {
                    o.put("path", target.path)
                    o.put("size", size)
                }
            } catch (e: Exception) {
                o.put("error", "unreadable")
                o.put("size", 0)
            }
            o.put("name", name)
            o.put("mime", mime)
            out.put(o)
        }
        return out
    }

    /** مشاركات أقدم من يومين لم تعد تلزم. */
    private fun prune(root: File) {
        val cutoff = System.currentTimeMillis() - 2L * 24 * 60 * 60 * 1000
        root.listFiles()?.forEach { if (it.lastModified() < cutoff) it.deleteRecursively() }
    }

    private fun displayName(context: Context, uri: Uri): String? {
        if (uri.scheme == "file") return uri.lastPathSegment
        return try {
            context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                if (c.moveToFirst()) c.getString(0)?.takeIf { it.isNotBlank() } else null
            }
        } catch (e: Exception) {
            null
        }
    }

    private fun safeName(name: String): String =
        name.replace(Regex("[\\\\/:*?\"<>|\\p{Cntrl}]"), "_").take(120).ifBlank { "file" }

    private fun stem(name: String): String {
        val dot = name.lastIndexOf('.')
        return if (dot > 0) name.substring(0, dot) else name
    }

    /** عدد البايتات المنسوخة، أو -1 إن تجاوز [MAX_BYTES]. */
    private fun copyLimited(context: Context, uri: Uri, target: File): Long {
        val input = context.contentResolver.openInputStream(uri) ?: throw IllegalStateException("no stream")
        var total = 0L
        input.use { inp ->
            FileOutputStream(target).use { outp ->
                val buffer = ByteArray(64 * 1024)
                while (true) {
                    val n = inp.read(buffer)
                    if (n < 0) break
                    total += n
                    if (total > MAX_BYTES) break
                    outp.write(buffer, 0, n)
                }
            }
        }
        return if (total > MAX_BYTES) -1L else total
    }

    /** صورة بصيغة لا تقبلها الحاوية → JPEG بأطول ضلع 1920 واتجاه الكاميرا. */
    private fun toJpeg(src: File, dst: File): Boolean {
        return try {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(src.path, bounds)
            if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return false
            var sample = 1
            while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= MAX_SIDE) sample *= 2
            var bitmap = BitmapFactory.decodeFile(src.path, BitmapFactory.Options().apply { inSampleSize = sample })
                ?: return false
            val longest = maxOf(bitmap.width, bitmap.height)
            val matrix = Matrix()
            if (longest > MAX_SIDE) {
                val scale = MAX_SIDE.toFloat() / longest
                matrix.postScale(scale, scale)
            }
            val degrees = rotation(src)
            if (degrees != 0) matrix.postRotate(degrees.toFloat())
            if (!matrix.isIdentity) {
                val turned = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
                if (turned !== bitmap) bitmap.recycle()
                bitmap = turned
            }
            FileOutputStream(dst).use { bitmap.compress(Bitmap.CompressFormat.JPEG, 90, it) }
            bitmap.recycle()
            true
        } catch (e: Throwable) {
            dst.delete()
            false
        }
    }

    private fun rotation(file: File): Int {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return 0
        return try {
            when (ExifInterface(file.path).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)) {
                ExifInterface.ORIENTATION_ROTATE_90 -> 90
                ExifInterface.ORIENTATION_ROTATE_180 -> 180
                ExifInterface.ORIENTATION_ROTATE_270 -> 270
                else -> 0
            }
        } catch (e: Exception) {
            0
        }
    }

    private const val MAX_SIDE = 1920
}
