package com.center.center_mobile

import android.Manifest
import android.app.Activity
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * ملفات المستندات التي يصدّرها التطبيق (السندات والكشوف):
 *
 * - `save`: حفظٌ في مجلد التنزيلات العام — كان «تنزيل» يفتح ورقة المشاركة فقط،
 *   فلا يجد المستخدم الملف بعدها في تنزيلاته.
 * - `open`: فتح الملف المحفوظ في عارض النظام.
 * - `whatsapp`: إرسال الملف نفسه في محادثة الرقم مباشرة — كان واتساب يُرسل نص
 *   رسالة بدل السند.
 */
class DocumentsBridge(private val activity: Activity) : MethodChannel.MethodCallHandler {

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "save" -> result.success(
                    save(
                        call.argument<ByteArray>("bytes") ?: ByteArray(0),
                        call.argument<String>("name") ?: "document.pdf",
                        call.argument<String>("mime") ?: "application/pdf",
                    ),
                )
                "open" -> result.success(
                    open(call.argument<String>("uri") ?: "", call.argument<String>("mime") ?: "application/pdf"),
                )
                "whatsapp" -> result.success(
                    whatsapp(
                        call.argument<ByteArray>("bytes") ?: ByteArray(0),
                        call.argument<String>("name") ?: "document.pdf",
                        call.argument<String>("mime") ?: "application/pdf",
                        call.argument<String>("phone") ?: "",
                        call.argument<String>("caption") ?: "",
                    ),
                )
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("documents", e.message, null)
        }
    }

    /** يعيد رابط الملف المحفوظ، أو `needs_permission` على أندرويد 9 فما دون قبل الإذن. */
    private fun save(bytes: ByteArray, name: String, mime: String): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = activity.contentResolver
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, name)
                put(MediaStore.Downloads.MIME_TYPE, mime)
                put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("insert failed")
            resolver.openOutputStream(uri)?.use { it.write(bytes) } ?: throw IllegalStateException("open failed")
            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            return uri.toString()
        }

        // أندرويد 9 فما دون: المجلد العام يحتاج إذن التخزين — يُطلب ويعيد المستخدم الضغط
        if (activity.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) {
            activity.requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), STORAGE_REQUEST)
            return "needs_permission"
        }
        @Suppress("DEPRECATION")
        val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        dir.mkdirs()
        val file = uniqueFile(dir, name)
        file.writeBytes(bytes)
        return Uri.fromFile(file).toString()
    }

    private fun open(uriText: String, mime: String): Boolean {
        if (uriText.isEmpty()) return false
        var uri = Uri.parse(uriText)
        // ملفٌّ عادي (أندرويد 9 فما دون) يُفتح عبر المزوّد: file:// يُرفض خارج التطبيق
        if (uri.scheme == "file") uri = providerUri(File(uri.path ?: return false))
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, mime)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return try {
            activity.startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    /**
     * يعيد `sent` أو `not_installed`. [phone] أرقام دولية بلا + — بها تُفتح محادثة الرقم
     * والملف مرفقٌ جاهز (`jid`)، وبلاها يختار المستخدم المحادثة.
     */
    private fun whatsapp(bytes: ByteArray, name: String, mime: String, phone: String, caption: String): String {
        val pkg = WHATSAPP_PACKAGES.firstOrNull { installed(it) } ?: return "not_installed"
        val dir = File(activity.cacheDir, "documents").apply { mkdirs() }
        val file = File(dir, name)
        file.writeBytes(bytes)
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = mime
            setPackage(pkg)
            putExtra(Intent.EXTRA_STREAM, providerUri(file))
            if (caption.isNotEmpty()) putExtra(Intent.EXTRA_TEXT, caption)
            if (phone.isNotEmpty()) putExtra("jid", "$phone@s.whatsapp.net")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        activity.startActivity(intent)
        return "sent"
    }

    private fun providerUri(file: File): Uri =
        FileProvider.getUriForFile(activity, "${activity.packageName}.documents", file)

    private fun installed(pkg: String): Boolean = try {
        activity.packageManager.getPackageInfo(pkg, 0)
        true
    } catch (_: PackageManager.NameNotFoundException) {
        false
    }

    private fun uniqueFile(dir: File, name: String): File {
        var file = File(dir, name)
        if (!file.exists()) return file
        val dot = name.lastIndexOf('.')
        val base = if (dot > 0) name.substring(0, dot) else name
        val ext = if (dot > 0) name.substring(dot) else ""
        var n = 1
        while (file.exists()) file = File(dir, "$base ($n)$ext").also { n++ }
        return file
    }

    companion object {
        const val CHANNEL = "center/documents"
        private const val STORAGE_REQUEST = 4712
        private val WHATSAPP_PACKAGES = listOf("com.whatsapp", "com.whatsapp.w4b")
    }
}
