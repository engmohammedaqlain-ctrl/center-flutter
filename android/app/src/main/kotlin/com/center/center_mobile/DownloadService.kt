package com.center.center_mobile

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * خدمةٌ في المقدمة تُبقي تنزيل التحديث يعمل والتطبيق خارج الشاشة.
 *
 * أندرويد يجمّد عملية التطبيق بعد ثوانٍ من خروجه من المقدمة، فينقطع التنزيل
 * ويبقى معلّقاً حتى يُفتح ثانيةً. خدمةٌ في المقدمة بإشعارٍ ظاهر تُعفي العملية
 * من التجميد، والإشعار نفسه هو ما يرى منه المستخدم النسبة وهو في تطبيقٍ آخر.
 */
class DownloadService : Service() {

    override fun onCreate() {
        super.onCreate()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // IMPORTANCE_LOW: شريط تقدّمٍ يُقرأ عند فتح الستارة، بلا صوتٍ ولا اقتحام
            val channel = NotificationChannel(CHANNEL, "تحديث التطبيق", NotificationManager.IMPORTANCE_LOW)
            channel.setShowBadge(false)
            manager(this).createNotificationChannel(channel)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val text = intent?.getStringExtra(EXTRA_TEXT) ?: DEFAULT_TEXT
        val percent = intent?.getIntExtra(EXTRA_PERCENT, -1) ?: -1
        val notification = build(this, text, percent, ongoing = true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(ID, notification)
        }
        running = true
        // التنزيل يُستأنف بيد المستخدم لا بإحياءٍ من النظام بعد قتل العملية
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        running = false
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        private const val CHANNEL = "app_update_download"
        private const val ID = 4711

        /** إشعار «جاهز للتثبيت» يبقى بعد توقف الخدمة، فله رقمه. */
        private const val DONE_ID = 4712
        private const val EXTRA_TEXT = "text"
        private const val EXTRA_PERCENT = "percent"
        private const val DEFAULT_TEXT = "جارِ تنزيل التحديث"

        private var running = false

        /** أول نداء يشغّل الخدمة، وما بعده يحدّث الإشعار وحده: إعادة تشغيلها لكل
         *  واحدٍ بالمئة عملٌ بلا فائدة. */
        fun show(context: Context, text: String, percent: Int) {
            if (running) {
                manager(context).notify(ID, build(context, text, percent, ongoing = true))
                return
            }
            val intent = Intent(context, DownloadService::class.java)
                .putExtra(EXTRA_TEXT, text)
                .putExtra(EXTRA_PERCENT, percent)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        /** انتهى العمل: تتوقف الخدمة ويبقى إشعارٌ يُلمس فيُفتح التطبيق. */
        fun finish(context: Context, text: String) {
            hide(context)
            manager(context).notify(DONE_ID, build(context, text, -1, ongoing = false))
        }

        fun hide(context: Context) {
            context.stopService(Intent(context, DownloadService::class.java))
            running = false
            manager(context).cancel(DONE_ID)
        }

        private fun manager(context: Context) =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        private fun build(context: Context, text: String, percent: Int, ongoing: Boolean): Notification {
            val open = Intent(context, MainActivity::class.java)
                .setFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            val pending = PendingIntent.getActivity(
                context,
                0,
                open,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(context, CHANNEL)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(context)
            }
            builder
                .setContentTitle("تحديث التطبيق")
                .setContentText(text)
                .setSmallIcon(android.R.drawable.stat_sys_download)
                .setOngoing(ongoing)
                // بلا هذا يهتزّ الجهاز ويُضيء مع كل واحدٍ بالمئة
                .setOnlyAlertOnce(true)
                .setContentIntent(pending)
            if (ongoing) {
                builder.setProgress(100, percent.coerceIn(0, 100), percent < 0)
            } else {
                builder.setSmallIcon(android.R.drawable.stat_sys_download_done).setAutoCancel(true)
            }
            return builder.build()
        }
    }
}
