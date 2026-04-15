package com.yueto.yuelink

import android.app.KeyguardManager
import android.content.Context
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
 * Quick Settings tile — headless VPN toggle.
 *
 * Rendered states (read from [PREFS_NAME]):
 *   - KEY_IN_TRANSITION == "starting" → STATE_UNAVAILABLE "连接中..."
 *   - KEY_IN_TRANSITION == "stopping" → STATE_UNAVAILABLE "断开中..."
 *   - KEY_VPN_ACTIVE && no transition → STATE_ACTIVE + optional subtitle
 *     override (KEY_SUBTITLE, e.g. "🇭🇰 香港"), else "已连接"
 *   - otherwise → STATE_INACTIVE "未连接"
 *
 * Click path:
 *   Path A (engine pre-warmed by MainApplication — the common case):
 *     Invoke MethodChannel("toggle") on the cached engine. Dart's
 *     `_performTileToggle` flips the core; its status listener writes
 *     KEY_IN_TRANSITION so the tile shows "连接中..." within a frame.
 *   Path B (cache empty — only if pre-warm lost the race):
 *     Optimistically set KEY_IN_TRANSITION and KEY_PENDING_TOGGLE,
 *     update the tile UI synchronously so the user sees instant
 *     feedback, then launch MainActivity to bootstrap the engine.
 *     Dart's `consumePendingToggle` drains the queued toggle once
 *     it finishes init. On a locked device this goes through
 *     [unlockAndRun] so Android actually brings the activity up.
 */
@RequiresApi(Build.VERSION_CODES.N)
class ProxyTileService : TileService() {

    companion object {
        const val PREFS_NAME = "yuelink_tile_prefs"
        const val KEY_VPN_ACTIVE = "vpn_active"
        const val KEY_IN_TRANSITION = "in_transition"
        const val KEY_SUBTITLE = "subtitle"
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
            try {
                val channel = MethodChannel(
                    engine.dartExecutor.binaryMessenger,
                    TILE_CHANNEL,
                )
                channel.invokeMethod("toggle", null, object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        // Dart will flip the transition flag as the core
                        // moves to starting/stopping; we don't touch prefs
                        // here or we race with it.
                    }
                    override fun error(code: String, msg: String?, detail: Any?) {
                        Log.w(TAG, "toggle invoke error: $code $msg — queueing")
                        optimisticTransitionAndQueue()
                    }
                    override fun notImplemented() {
                        Log.w(TAG, "toggle notImplemented — queueing")
                        optimisticTransitionAndQueue()
                    }
                })
            } catch (e: Throwable) {
                Log.e(TAG, "toggle invoke threw — falling back to activity", e)
                optimisticTransitionAndQueue()
                bootstrapViaActivityMaybeUnlock()
            }
            return
        }

        // Path B: engine cache empty, bootstrap via activity.
        Log.w(TAG, "shared engine missing from cache — bootstrap via activity")
        optimisticTransitionAndQueue()
        bootstrapViaActivityMaybeUnlock()
    }

    /**
     * Show "连接中..." / "断开中..." on the tile immediately and queue the
     * toggle so Dart picks it up once the engine finishes booting. Derived
     * from the current vpn_active flag: if we think we're connected, we're
     * about to disconnect, and vice versa.
     */
    private fun optimisticTransitionAndQueue() {
        val wasActive = prefs.getBoolean(KEY_VPN_ACTIVE, false)
        prefs.edit()
            .putString(KEY_IN_TRANSITION, if (wasActive) "stopping" else "starting")
            .putBoolean(KEY_PENDING_TOGGLE, true)
            .apply()
        // Force the tile to re-render right away — otherwise we wait for
        // onStartListening which only fires when the Quick Settings panel
        // reopens, defeating the point of optimistic UI.
        updateTileState()
    }

    private fun bootstrapViaActivityMaybeUnlock() {
        val run = Runnable { bootstrapViaActivity() }
        val km = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
        if (km != null && km.isKeyguardLocked) {
            // unlockAndRun delays execution until the user authenticates.
            // Without this, startActivityAndCollapse from a locked device
            // silently fails and the toggle is dropped.
            unlockAndRun(run)
        } else {
            run.run()
        }
    }

    private fun bootstrapViaActivity() {
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
     * Read all tile-state prefs and paint the tile. Called on
     * onStartListening (system-driven) and synchronously after
     * optimisticTransitionAndQueue so the user sees feedback instantly.
     */
    private fun updateTileState() {
        val tile = qsTile ?: return
        val isActive = prefs.getBoolean(KEY_VPN_ACTIVE, false)
        val transition = prefs.getString(KEY_IN_TRANSITION, null)
        val subtitleOverride = prefs.getString(KEY_SUBTITLE, null)

        tile.icon = Icon.createWithResource(this, R.drawable.ic_tile_vpn)
        tile.label = "YueLink"

        when (transition) {
            "starting", "stopping" -> {
                tile.state = Tile.STATE_UNAVAILABLE
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    tile.subtitle = getString(
                        if (transition == "starting")
                            R.string.tile_connecting
                        else R.string.tile_disconnecting
                    )
                }
            }
            else -> {
                tile.state = if (isActive) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    tile.subtitle = if (isActive) {
                        subtitleOverride?.takeIf { it.isNotEmpty() }
                            ?: getString(R.string.tile_connected)
                    } else {
                        getString(R.string.tile_disconnected)
                    }
                }
            }
        }
        tile.updateTile()
    }
}
