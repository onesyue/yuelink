package com.yueto.yuelink

import io.flutter.app.FlutterApplication
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Process-level crash logging only.
 *
 * A shared FlutterEngine is still used, but it is created lazily by
 * MainActivity and cached there. Starting Dart from Application.onCreate()
 * made every Android process launch pay Flutter startup cost before the
 * Activity could draw, and it ran Dart before Activity-bound plugins were
 * attached. Low-end devices reported this as a cold-start ANR.
 *
 * ProxyTileService already has a safe fallback: if no cached engine exists,
 * it queues the toggle in SharedPreferences and launches MainActivity.
 */
class MainApplication : FlutterApplication() {

    companion object {
        const val SHARED_ENGINE_ID = "yuelink_shared_engine"
    }

    override fun onCreate() {
        super.onCreate()
        installCrashHandler()
    }

    /**
     * Install a process-wide uncaught-exception handler. Without this, any
     * Kotlin exception on a non-main thread (e.g. a callback in
     * YueLinkVpnService, a PackageManager query, a SharedPreferences commit
     * race) kills the app process with no trace beyond logcat — which most
     * users can't capture.
     *
     * We append the stack trace to `filesDir/crash.log` (the same file the
     * Dart-side ErrorLogger writes to, so `LogExportService` and the
     * Settings → Export Diagnostics flow pick it up automatically), then
     * chain to the system's default handler so Android still shows its
     * "YueLink has stopped" dialog and the process dies normally.
     */
    private fun installCrashHandler() {
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            try {
                val sw = StringWriter()
                throwable.printStackTrace(PrintWriter(sw))
                val timestamp = SimpleDateFormat(
                    "yyyy-MM-dd'T'HH:mm:ss.SSS", Locale.US
                ).format(Date())
                val entry = buildString {
                    append("[$timestamp]\n")
                    append("[Android/${thread.name}] ")
                    append(throwable.javaClass.name)
                    append(": ").append(throwable.message ?: "").append("\n")
                    append(sw.toString()).append("\n\n")
                }
                File(filesDir, "crash.log").appendText(entry)
            } catch (_: Throwable) {
                // If logging itself fails, let the original crash propagate
                // unadorned — don't mask the root cause.
            }
            // Preserve the system's crash dialog behaviour.
            previous?.uncaughtException(thread, throwable)
        }
    }
}
