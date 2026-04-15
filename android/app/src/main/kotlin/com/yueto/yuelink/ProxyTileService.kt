package com.yueto.yuelink

import android.content.Intent
import android.content.SharedPreferences
import android.graphics.drawable.Icon
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.util.Log
import androidx.annotation.RequiresApi
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

/**
 * Quick Settings tile that toggles the VPN headlessly.
 *
 * Path A (the common case — engine pre-warmed by MainApplication):
 *   onClick → MethodChannel("toggle") on the shared FlutterEngine →
 *   Dart's TileService.onToggleRequested → CoreActions.start/stop →
 *   tile state refreshes via SharedPreferences write from Dart.
 *   The app window is never shown.
 *
 * Path B (fallback — engine cache empty, e.g. the very first tile click
 * in this process and pre-warm somehow lost the race):
 *   Set pending_toggle=true in prefs → start MainActivity to bootstrap
 *   the engine → Dart's _consumePendingToggle picks up the queued
 *   request after _setupTileService registers the channel handler.
 */
@RequiresApi(Build.VERSION_CODES.N)
class ProxyTileService : TileService() {

    companion object {
        const val PREFS_NAME = "yuelink_tile_prefs"
        const val KEY_VPN_ACTIVE = "vpn_active"
        const val KEY_PENDING_TOGGLE = "pending_toggle"
        const val ACTION_TOGGLE = "com.yueto.yuelink.TOGGLE"
        const val TILE_CHANNEL = "com.yueto.yuelink/tile"
        private const val TAG = "YueLinkTile"
    }

    private val prefs: SharedPreferences
        get() = applicationContext.getSharedPreferences(PREFS_NAME, MODE_PRIVATE)

    override fun onStartListening() {
        super.onStartListening()
        updateTileState()
    }

    override fun onClick() {
        super.onClick()

        val engine = FlutterEngineCache.getInstance()
            .get(MainApplication.SHARED_ENGINE_ID)
        if (engine != null) {
            // Path A: headless toggle via the shared engine.
            try {
                val channel = MethodChannel(
                    engine.dartExecutor.binaryMessenger,
                    TILE_CHANNEL,
                )
                channel.invokeMethod("toggle", null, object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        // Nothing to do — Dart will write SharedPreferences
                        // when the core status actually changes, and the
                        // tile UI will refresh via onStartListening.
                    }
                    override fun error(code: String, msg: String?, detail: Any?) {
                        // Dart handler not registered yet — engine is still
                        // booting. Queue the toggle so Dart picks it up
                        // when it finishes initializing.
                        Log.w(TAG, "toggle invoke error: $code $msg — queueing")
                        prefs.edit().putBoolean(KEY_PENDING_TOGGLE, true).apply()
                    }
                    override fun notImplemented() {
                        Log.w(TAG, "toggle notImplemented — queueing")
                        prefs.edit().putBoolean(KEY_PENDING_TOGGLE, true).apply()
                    }
                })
            } catch (e: Throwable) {
                Log.e(TAG, "toggle invoke threw — falling back to activity", e)
                bootstrapViaActivity()
            }
            return
        }

        // Path B: cache empty, bootstrap via activity.
        Log.w(TAG, "shared engine missing from cache — bootstrap via activity")
        bootstrapViaActivity()
    }

    private fun bootstrapViaActivity() {
        prefs.edit().putBoolean(KEY_PENDING_TOGGLE, true).apply()
        val intent = Intent(this, MainActivity::class.java).apply {
            action = ACTION_TOGGLE
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val pendingIntent = android.app.PendingIntent.getActivity(
                this, 0, intent,
                android.app.PendingIntent.FLAG_UPDATE_CURRENT
                    or android.app.PendingIntent.FLAG_IMMUTABLE,
            )
            startActivityAndCollapse(pendingIntent)
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }

    /**
     * Read VPN state from SharedPreferences and update the tile appearance.
     * Dart writes the flag whenever core status changes via
     * `TileService.updateState` on the Flutter side.
     */
    private fun updateTileState() {
        val tile = qsTile ?: return
        val isActive = prefs.getBoolean(KEY_VPN_ACTIVE, false)

        tile.state = if (isActive) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.icon = Icon.createWithResource(this, R.drawable.ic_tile_vpn)
        tile.label = "YueLink"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.subtitle = getString(
                if (isActive) R.string.tile_connected else R.string.tile_disconnected
            )
        }
        tile.updateTile()
    }
}
