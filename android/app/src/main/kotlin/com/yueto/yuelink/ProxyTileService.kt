package com.yueto.yuelink

import android.content.Intent
import android.content.SharedPreferences
import android.graphics.drawable.Icon
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import androidx.annotation.RequiresApi

/**
 * Quick Settings tile that toggles the VPN proxy on/off.
 *
 * Communication flow:
 * 1. Tile reads current VPN state from SharedPreferences (written by Flutter via MethodChannel)
 * 2. On click, launches MainActivity with TOGGLE action
 * 3. MainActivity forwards the toggle to Flutter's core lifecycle
 * 4. Flutter updates SharedPreferences when VPN state changes, tile refreshes
 */
@RequiresApi(Build.VERSION_CODES.N)
class ProxyTileService : TileService() {

    companion object {
        const val PREFS_NAME = "yuelink_tile_prefs"
        const val KEY_VPN_ACTIVE = "vpn_active"
        const val ACTION_TOGGLE = "com.yueto.yuelink.TOGGLE"
    }

    private val prefs: SharedPreferences
        get() = applicationContext.getSharedPreferences(PREFS_NAME, MODE_PRIVATE)

    override fun onStartListening() {
        super.onStartListening()
        updateTileState()
    }

    override fun onClick() {
        super.onClick()

        // Launch MainActivity with toggle action.
        // singleTop + FLAG_ACTIVITY_NEW_TASK ensures we reuse an existing instance
        // (onNewIntent) or create one if the app is not running.
        val intent = Intent(this, MainActivity::class.java).apply {
            action = ACTION_TOGGLE
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

        // On API 34+, startActivityAndCollapse requires a PendingIntent.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val pendingIntent = android.app.PendingIntent.getActivity(
                this, 0, intent,
                android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
            )
            startActivityAndCollapse(pendingIntent)
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }

    /**
     * Read VPN state from SharedPreferences and update the tile appearance.
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
