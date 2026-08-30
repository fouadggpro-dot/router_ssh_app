package com.routercontroller.agent

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat

/**
 * Full-screen-intent notification used only for pending approval
 * requests. It surfaces the request (and only the request — the
 * approval decision itself always happens in-app via ApprovalScreen,
 * never from a notification action button) even when the device is
 * locked, so a stale "pending" state doesn't sit unnoticed.
 */
object NotificationHelper {
    private const val CHANNEL_ID = "approval_requests"

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val mgr = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (mgr.getNotificationChannel(CHANNEL_ID) == null) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    "طلبات الموافقة",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "إشعارات لطلبات تنفيذ تحتاج موافقتك"
                }
                mgr.createNotificationChannel(channel)
            }
        }
    }

    fun showApprovalRequest(context: Context, commandId: String, summary: String) {
        ensureChannel(context)

        val fullScreenIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("pending_command_id", commandId)
        }
        val fullScreenPendingIntent = PendingIntent.getActivity(
            context, commandId.hashCode(), fullScreenIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle("طلب موافقة جديد")
            .setContentText(summary)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setFullScreenIntent(fullScreenPendingIntent, true)
            .setContentIntent(fullScreenPendingIntent)
            .setAutoCancel(true)
            .build()

        val mgr = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        mgr.notify(commandId.hashCode(), notification)
    }
}
