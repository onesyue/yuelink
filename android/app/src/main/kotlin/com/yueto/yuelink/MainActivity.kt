package com.yueto.yuelink

import android.app.Activity
import android.app.PictureInPictureParams
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.net.VpnService
import android.os.Build
import android.os.IBinder
import android.service.quicksettings.TileService
import androidx.core.content.FileProvider
import java.io.File
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    // Use texture render mode to avoid the black-frame flash / ghost shadow
    // that appears when returning from background with the default surface mode.
    // Surface mode destroys and recreates the EGL surface on pause/resume;
    // texture mode keeps the Flutter texture alive, giving a smooth transition.
    override fun getRenderMode(): RenderMode = RenderMode.texture

    /**
     * Reuse the shared FlutterEngine pre-warmed by MainApplication so the
     * UI and the Quick Settings tile share a single engine (one CoreManager,
     * no Go-core race). Returns null and falls back to the default engine
     * creation only if the cache is empty for some reason.
     */
    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        return FlutterEngineCache.getInstance().get(MainApplication.SHARED_ENGINE_ID)
            ?: super.provideFlutterEngine(context)
    }

    /**
     * Tell FlutterActivity which cached engine ID to attach to. Without
     * this, FlutterActivity ignores provideFlutterEngine in some builds
     * because it tracks engines by ID.
     */
    override fun getCachedEngineId(): String? = MainApplication.SHARED_ENGINE_ID

    /**
     * The shared engine is owned by the Application — must NOT be destroyed
     * when the activity finishes, otherwise the tile loses its target and
     * subsequent toggles fall back to launching the activity again.
     */
    override fun shouldDestroyEngineWithHost(): Boolean = false

    companion object {
        private const val VPN_CHANNEL  = "com.yueto.yuelink/vpn"
        private const val APPS_CHANNEL = "com.yueto.yuelink/apps"
        private const val PIP_CHANNEL  = "com.yueto.yuelink/pip"
        private const val TILE_CHANNEL = "com.yueto.yuelink/tile"
        private const val VPN_REQUEST_CODE = 1001
        private const val NOTIFICATION_REQUEST_CODE = 1002
    }

    private var vpnPermissionResult: MethodChannel.Result? = null
    private var vpnStartResult: MethodChannel.Result? = null
    private var pendingMixedPort: Int = 7890
    private var pendingSplitMode: String = "all"
    private var pendingSplitApps: List<String> = emptyList()

    /** True when the Quick Settings tile triggered a toggle before Flutter engine was ready. */
    private var pendingTileToggle = false
    private var tileChannel: MethodChannel? = null

    private var vpnService: YueLinkVpnService? = null
    private var serviceBound = false

    private val serviceConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
            vpnService = (service as YueLinkVpnService.LocalBinder).getService()
            serviceBound = true
        }
        override fun onServiceDisconnected(name: ComponentName?) {
            vpnService = null
            serviceBound = false
        }
    }

    override fun onStart() {
        super.onStart()
        // POST_NOTIFICATIONS is no longer requested eagerly on startup.
        // The foreground VPN service works without the permission — the
        // notification is simply suppressed by the system. This avoids
        // confusing permission dialogs on first launch and makes the app
        // functional even when the user denies notification access.
    }

    /**
     * Handle intents when activity is already running (singleTop).
     * Used by ProxyTileService to send TOGGLE action.
     */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleTileToggleIntent(intent)
    }

    /** True when the tile long-press arrived before the Flutter channel was ready. */
    private var pendingOpenPreferences = false

    /**
     * Forward tile-driven intents to Flutter. Two actions:
     *   - ACTION_TOGGLE (from the tile service's activity-bootstrap fallback
     *     path) → sent as "toggle"
     *   - ACTION_QS_TILE_PREFERENCES (system-driven when the user long-presses
     *     the tile in the Quick Settings panel) → sent as "openPreferences"
     *
     * If the tile channel isn't set up yet (Flutter engine hasn't finished
     * initializing), the request is queued and delivered from
     * configureFlutterEngine.
     */
    private fun handleTileToggleIntent(intent: Intent?) {
        val action = intent?.action ?: return
        when (action) {
            ProxyTileService.ACTION_TOGGLE -> {
                val channel = tileChannel
                if (channel != null) {
                    channel.invokeMethod("toggle", null)
                } else {
                    pendingTileToggle = true
                }
            }
            "android.service.quicksettings.action.QS_TILE_PREFERENCES" -> {
                val channel = tileChannel
                if (channel != null) {
                    channel.invokeMethod("openPreferences", null)
                } else {
                    pendingOpenPreferences = true
                }
            }
            else -> return
        }
        intent.action = null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── VPN channel ───────────────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VPN_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestPermission" -> requestVpnPermission(result)
                    "startVpn" -> {
                        val mixedPort = call.argument<Int>("mixedPort") ?: 7890
                        val splitMode = call.argument<String>("splitMode") ?: "all"
                        val splitApps = call.argument<List<String>>("splitApps") ?: emptyList()
                        startVpnService(mixedPort, splitMode, splitApps, result)
                    }
                    "stopVpn"  -> stopVpnService(result)
                    "getTunFd" -> result.success(vpnService?.getTunFd() ?: -1)
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path != null) {
                            installApk(path, result)
                        } else {
                            result.error("INVALID_PATH", "APK path is null", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // Notify Dart when VPN is revoked by system/another app
        YueLinkVpnService.onVpnRevoked = {
            try {
                MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VPN_CHANNEL)
                    .invokeMethod("vpnRevoked", null)
            } catch (e: Exception) {
                android.util.Log.w("YueLinkVpn", "Failed to notify Dart of VPN revoke: ${e.message}")
            }
        }

        // ── PiP channel ─────────────────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PIP_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enterPip" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            val w = call.argument<Int>("width") ?: 16
                            val h = call.argument<Int>("height") ?: 9
                            val params = PictureInPictureParams.Builder()
                                .setAspectRatio(android.util.Rational(w, h))
                                .build()
                            enterPictureInPictureMode(params)
                            result.success(true)
                        } else {
                            result.error("UNSUPPORTED", "PiP requires Android 8.0+", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // ── Installed apps channel ────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, APPS_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInstalledApps" -> {
                        val showSystem = call.argument<Boolean>("showSystem") ?: false
                        // Run on background thread to avoid blocking the main thread.
                        // PackageManager queries can take 500ms-2s on devices with many apps.
                        Thread {
                            try {
                                val apps = getInstalledApps(showSystem)
                                mainExecutor.execute { result.success(apps) }
                            } catch (e: Exception) {
                                android.util.Log.e("YueLinkApps", "getInstalledApps thread failed", e)
                                mainExecutor.execute { result.success(emptyList<Map<String, String>>()) }
                            }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            }

        // ── Tile channel (Quick Settings ↔ Flutter) ─────────────────────────────
        val tc = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, TILE_CHANNEL)
        tc.setMethodCallHandler { call, result ->
            when (call.method) {
                "updateTileState" -> {
                    val isActive = call.argument<Boolean>("active") ?: false
                    val transition = call.argument<String?>("transition")
                    val subtitle = call.argument<String?>("subtitle")
                    updateTilePrefs(isActive, transition, subtitle)
                    result.success(true)
                }
                "consumePendingToggle" -> {
                    // Atomic getAndClear of the pending_toggle flag set by
                    // ProxyTileService when it failed to invoke into a
                    // not-yet-ready engine.
                    val prefs = getSharedPreferences(
                        ProxyTileService.PREFS_NAME, MODE_PRIVATE
                    )
                    val had = prefs.getBoolean(
                        ProxyTileService.KEY_PENDING_TOGGLE, false
                    )
                    if (had) {
                        prefs.edit()
                            .putBoolean(ProxyTileService.KEY_PENDING_TOGGLE, false)
                            .apply()
                    }
                    result.success(had)
                }
                else -> result.notImplemented()
            }
        }
        tileChannel = tc

        // Deliver pending tile toggle if ProxyTileService launched us
        if (pendingTileToggle) {
            pendingTileToggle = false
            tc.invokeMethod("toggle", null)
        }
        if (pendingOpenPreferences) {
            pendingOpenPreferences = false
            tc.invokeMethod("openPreferences", null)
        }

        // Also check the initial launch intent (cold start from tile)
        handleTileToggleIntent(intent)
    }

    // ── Tile helpers ─────────────────────────────────────────────────────────

    /**
     * Write VPN active state + optional transition ("starting"/"stopping") +
     * optional subtitle override into SharedPreferences and request tile UI
     * refresh. Called from Flutter via the tile MethodChannel whenever the
     * core status changes or the exit node is resolved.
     */
    private fun updateTilePrefs(
        active: Boolean,
        transition: String? = null,
        subtitle: String? = null,
    ) {
        val edit = getSharedPreferences(ProxyTileService.PREFS_NAME, MODE_PRIVATE).edit()
        edit.putBoolean(ProxyTileService.KEY_VPN_ACTIVE, active)
        if (transition.isNullOrEmpty()) {
            edit.remove(ProxyTileService.KEY_IN_TRANSITION)
        } else {
            edit.putString(ProxyTileService.KEY_IN_TRANSITION, transition)
        }
        if (subtitle.isNullOrEmpty()) {
            edit.remove(ProxyTileService.KEY_SUBTITLE)
        } else {
            edit.putString(ProxyTileService.KEY_SUBTITLE, subtitle)
        }
        edit.apply()

        // Request the system to refresh the tile — triggers onStartListening()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            TileService.requestListeningState(
                this,
                ComponentName(this, ProxyTileService::class.java)
            )
        }
    }

    // ── Installed apps ────────────────────────────────────────────────────────

    private fun getInstalledApps(showSystem: Boolean): List<Map<String, String>> {
        val pm = packageManager
        try {
            // Android 13+ (API 33): getInstalledApplications(ApplicationInfoFlags)
            // Older: getInstalledApplications(int flags)
            @Suppress("DEPRECATION")
            val allApps = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                pm.getInstalledApplications(
                    PackageManager.ApplicationInfoFlags.of(0)
                )
            } else {
                pm.getInstalledApplications(0)
            }
            android.util.Log.i("YueLinkApps", "getInstalledApplications returned ${allApps.size} apps")
            return allApps
                .filter { app ->
                    val isSystem = (app.flags and ApplicationInfo.FLAG_SYSTEM) != 0
                    if (!showSystem && isSystem) return@filter false
                    // Exclude ourselves
                    app.packageName != packageName
                }
                .mapNotNull { app ->
                    try {
                        mapOf(
                            "packageName" to app.packageName,
                            "appName"     to (pm.getApplicationLabel(app).toString()),
                        )
                    } catch (e: Exception) {
                        // Some ROMs throw on getApplicationLabel for certain packages
                        mapOf(
                            "packageName" to app.packageName,
                            "appName"     to app.packageName,
                        )
                    }
                }
                .sortedBy { it["appName"]?.lowercase() }
        } catch (e: Exception) {
            android.util.Log.e("YueLinkApps", "getInstalledApps failed", e)
            return emptyList()
        }
    }

    // ── APK installer ─────────────────────────────────────────────────────────

    private fun installApk(path: String, result: MethodChannel.Result) {
        try {
            val file = File(path)
            if (!file.exists()) {
                result.error("FILE_NOT_FOUND", "APK file not found: $path", null)
                return
            }
            val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            result.error("INSTALL_FAILED", e.message, null)
        }
    }

    // ── VPN helpers ───────────────────────────────────────────────────────────

    private fun requestVpnPermission(result: MethodChannel.Result) {
        val intent = VpnService.prepare(this)
        if (intent != null) {
            vpnPermissionResult = result
            @Suppress("DEPRECATION")
            startActivityForResult(intent, VPN_REQUEST_CODE)
        } else {
            result.success(true)
        }
    }

    private fun startVpnService(
        mixedPort: Int,
        splitMode: String,
        splitApps: List<String>,
        result: MethodChannel.Result,
    ) {
        // Permission was already obtained by the requestPermission() step.
        // Do NOT call VpnService.prepare() here again — on Samsung Galaxy devices
        // a second prepare() call shows a duplicate permission dialog even after
        // the user just granted, causing confusion and an 8s timeout.
        doStartVpnService(mixedPort, splitMode, splitApps, result)
    }

    private fun doStartVpnService(
        mixedPort: Int,
        splitMode: String,
        splitApps: List<String>,
        result: MethodChannel.Result,
    ) {
        val serviceIntent = Intent(this, YueLinkVpnService::class.java).apply {
            action = YueLinkVpnService.ACTION_START
            putExtra(YueLinkVpnService.EXTRA_MIXED_PORT, mixedPort)
            putExtra(YueLinkVpnService.EXTRA_SPLIT_MODE, splitMode)
            putStringArrayListExtra(YueLinkVpnService.EXTRA_SPLIT_APPS, ArrayList(splitApps))
        }
        startForegroundService(serviceIntent)

        if (!serviceBound) {
            val bindIntent = Intent(this, YueLinkVpnService::class.java)
            bindService(bindIntent, serviceConnection, Context.BIND_AUTO_CREATE)
        }

        // Poll for TUN fd with retry instead of fixed 500ms delay.
        // The VPN service may take varying time to bind and establish().
        waitForTunFd(result)
    }

    /**
     * Poll for the TUN file descriptor with exponential backoff.
     * Retries every 100ms for up to 5 seconds, then gives up.
     * Also sets an onTunReady callback as fallback for late delivery.
     */
    private fun waitForTunFd(
        result: MethodChannel.Result,
        maxRetries: Int = 50,
    ) {
        val handler = android.os.Handler(mainLooper)
        var retries = 0
        var responded = false

        val checker = object : Runnable {
            override fun run() {
                if (responded || isFinishing || isDestroyed) return

                val bound = vpnService
                if (bound != null) {
                    // Fast-fail: establish() returned null immediately
                    if (bound.tunSetupFailed) {
                        responded = true
                        bound.onTunReady = null
                        android.util.Log.e("YueLinkVpn", "waitForTunFd: tunSetupFailed — reporting -1 immediately")
                        try { result.success(-1) } catch (_: Exception) {}
                        return
                    }
                    val fd = bound.getTunFd()
                    if (fd != -1) {
                        responded = true
                        bound.onTunReady = null
                        try { result.success(fd) } catch (_: Exception) {}
                        return
                    }
                }

                retries++
                if (retries >= maxRetries) {
                    // Final attempt: set callback for late delivery
                    bound?.onTunReady = { fd ->
                        if (!responded) {
                            responded = true
                            try { result.success(fd) } catch (_: Exception) {}
                        }
                    }
                    // Absolute timeout: give up after 3 more seconds
                    handler.postDelayed({
                        if (!responded) {
                            responded = true
                            bound?.onTunReady = null
                            try { result.success(-1) } catch (_: Exception) {}
                        }
                    }, 3000)
                    return
                }
                handler.postDelayed(this, 100)
            }
        }
        // Start checking immediately (no initial delay)
        handler.post(checker)
    }

    private fun stopVpnService(result: MethodChannel.Result) {
        // Prefer direct call on bound service — avoids startService() which
        // can throw ForegroundServiceStartNotAllowedException on Android 12+
        // when app is transitioning to background.
        val bound = vpnService
        if (bound != null) {
            bound.stopTunnel()
        } else {
            // Fallback: deliver stop via intent if not bound
            try {
                val serviceIntent = Intent(this, YueLinkVpnService::class.java).apply {
                    action = YueLinkVpnService.ACTION_STOP
                }
                startService(serviceIntent)
            } catch (e: Exception) {
                android.util.Log.w("YueLinkVpn", "startService(STOP) failed: ${e.message}")
            }
        }
        if (serviceBound) {
            try {
                unbindService(serviceConnection)
            } catch (e: Exception) {
                android.util.Log.w("YueLinkVpn", "unbindService failed: ${e.message}")
            }
            serviceBound = false
            vpnService = null
        }
        result.success(true)
    }

    @Suppress("DEPRECATION")
    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != VPN_REQUEST_CODE) return

        val granted = resultCode == Activity.RESULT_OK
        try {
            if (vpnPermissionResult != null) {
                vpnPermissionResult?.success(granted)
                vpnPermissionResult = null
            } else if (vpnStartResult != null) {
                val pendingResult = vpnStartResult!!
                vpnStartResult = null
                if (granted) {
                    doStartVpnService(pendingMixedPort, pendingSplitMode, pendingSplitApps, pendingResult)
                } else {
                    pendingResult.success(-1)
                }
            }
        } catch (_: Exception) {
            vpnPermissionResult = null
            vpnStartResult = null
        }
    }

    override fun onDestroy() {
        if (serviceBound) {
            unbindService(serviceConnection)
            serviceBound = false
        }
        super.onDestroy()
    }
}
