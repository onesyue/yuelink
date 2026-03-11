package com.yueto.yuelink

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import android.os.Binder
import android.os.IBinder
import android.os.ParcelFileDescriptor

class YueLinkVpnService : VpnService() {
    companion object {
        const val ACTION_START = "com.yueto.yuelink.action.START"
        const val ACTION_STOP  = "com.yueto.yuelink.action.STOP"

        const val EXTRA_MIXED_PORT = "mixed_port"
        /** "all" | "whitelist" | "blacklist" */
        const val EXTRA_SPLIT_MODE = "split_mode"
        /** ArrayList<String> of package names */
        const val EXTRA_SPLIT_APPS = "split_apps"

        private const val NOTIFICATION_ID = 1
        private const val CHANNEL_ID = "yuelink_vpn"

        // JNI bridge to Go core's protect_android.c
        // Called to register/unregister VpnService for socket protection.
        // The Go core's DefaultSocketHook calls VpnService.protect(fd) for
        // every outbound socket to bypass VPN routing.
        @JvmStatic external fun nativeStartProtect(vpnService: VpnService)
        @JvmStatic external fun nativeStopProtect()

        init {
            System.loadLibrary("clash")
        }
    }

    inner class LocalBinder : Binder() {
        fun getService() = this@YueLinkVpnService
    }

    private val binder = LocalBinder()
    private var tunFd: ParcelFileDescriptor? = null

    var onTunReady: ((Int) -> Unit)? = null

    // Split-tunnel config stored at start time for notification text
    private var splitMode: String = "all"

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onBind(intent: Intent?): IBinder = binder

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val mixedPort = intent.getIntExtra(EXTRA_MIXED_PORT, 7890)
                val mode  = intent.getStringExtra(EXTRA_SPLIT_MODE) ?: "all"
                val apps  = intent.getStringArrayListExtra(EXTRA_SPLIT_APPS) ?: arrayListOf()
                startTunnel(mixedPort, mode, apps)
            }
            ACTION_STOP -> stopTunnel()
        }
        return START_STICKY
    }

    private fun startTunnel(mixedPort: Int, mode: String, apps: List<String>) {
        // Must call startForeground ASAP (within 5s of startForegroundService)
        // to avoid ANR. Call it before establish() which may take time.
        startForeground(NOTIFICATION_ID, createNotification())

        if (tunFd != null) {
            onTunReady?.invoke(tunFd!!.fd)
            return
        }

        // Register this VpnService for socket protection BEFORE TUN starts.
        // The Go core's DefaultSocketHook calls protect(fd) on every outbound
        // socket to prevent routing loops through the VPN tunnel.
        try {
            nativeStartProtect(this)
        } catch (e: UnsatisfiedLinkError) {
            android.util.Log.w("YueLinkVpn", "nativeStartProtect unavailable: ${e.message}")
        }

        splitMode = mode

        val builder = Builder()
            .setSession("YueLink")
            .addAddress("172.19.0.1", 30)
            .addRoute("0.0.0.0", 0)
            // Do NOT add IPv6 route — mihomo TUN only has inet4-address.
            // Routing IPv6 to TUN without inet6-address creates a black hole:
            // Android prefers IPv6, packets go to TUN, mihomo can't process them,
            // connections hang. IPv6 traffic bypasses VPN and goes direct instead.
            // Use TUN gateway (172.19.0.2 = .1/30 network's other usable IP) as DNS.
            // This ensures DNS queries always enter the TUN and get caught by
            // mihomo's dns-hijack. External DNS IPs (223.5.5.5) may have edge
            // cases where packets don't match the hijack pattern.
            .addDnsServer("172.19.0.2")
            .setMtu(9000)
            .setBlocking(false)
            // The mihomo process itself must always bypass the VPN to avoid routing loops.
            // This excludes the entire app UID (Go core shares the same process/UID).
            .addDisallowedApplication(packageName)

        when (mode) {
            "whitelist" -> {
                // Only listed apps go through VPN (allowedApplications)
                for (pkg in apps) {
                    try { builder.addAllowedApplication(pkg) } catch (_: Exception) {}
                }
            }
            "blacklist" -> {
                // Listed apps bypass VPN (disallowedApplications)
                for (pkg in apps) {
                    try { builder.addDisallowedApplication(pkg) } catch (_: Exception) {}
                }
            }
            // "all" — no extra filtering, everything goes through (default)
        }

        tunFd = builder.establish()

        val fd = tunFd?.fd
        if (fd != null) {
            onTunReady?.invoke(fd)
        }
    }

    private fun stopTunnel() {
        try {
            nativeStopProtect()
        } catch (_: UnsatisfiedLinkError) {}
        tunFd?.close()
        tunFd = null
        onTunReady = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    fun getTunFd(): Int = tunFd?.fd ?: -1

    override fun onDestroy() {
        stopTunnel()
        super.onDestroy()
    }

    override fun onRevoke() {
        stopTunnel()
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "YueLink VPN",
            NotificationManager.IMPORTANCE_LOW
        ).apply { description = "YueLink VPN service status" }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private fun createNotification(): Notification {
        val pendingIntent = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE
        )
        val modeText = when (splitMode) {
            "whitelist" -> getString(R.string.vpn_whitelist)
            "blacklist" -> getString(R.string.vpn_blacklist)
            else        -> getString(R.string.vpn_connected)
        }
        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("YueLink")
            .setContentText(modeText)
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }
}
