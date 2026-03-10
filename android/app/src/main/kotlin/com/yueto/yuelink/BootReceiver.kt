package com.yueto.yuelink

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * Handles device boot-completed broadcast.
 *
 * Launches MainActivity with a flag so the Flutter app knows it was started
 * via boot (auto-connect logic runs based on the saved autoConnect setting).
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return

        val launch = Intent(context, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            putExtra("auto_connect", true)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // On Android 10+ background activity launch is restricted;
            // start a foreground service proxy to show a notification first.
            context.startForegroundService(
                Intent(context, BootStartService::class.java)
            )
        } else {
            context.startActivity(launch)
        }
    }
}
