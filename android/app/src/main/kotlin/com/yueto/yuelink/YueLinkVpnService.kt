package com.yueto.yuelink

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.VpnService
import android.os.Binder
import android.os.Build
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
        @JvmStatic external fun nativeStartProtect(vpnService: VpnService)
        @JvmStatic external fun nativeStopProtect()
        @JvmStatic external fun nativeNotifyDnsChanged(dnsList: String)

        init {
            System.loadLibrary("clash")
        }
    }

    inner class LocalBinder : Binder() {
        fun getService() = this@YueLinkVpnService
    }

    private val binder = LocalBinder()

    // Raw TUN fd — we use detachFd() to take ownership so GC can't close it.
    // CMFA does the same: establish()?.detachFd().
    // Using .fd without detach causes silent fd invalidation when GC collects
    // the ParcelFileDescriptor, killing all TUN traffic.
    private var tunFd: Int = -1

    // Set to true immediately when establish() returns null, so waitForTunFd
    // can detect failure in the next poll (100ms) instead of 8s timeout.
    var tunSetupFailed: Boolean = false

    var onTunReady: ((Int) -> Unit)? = null

    private var splitMode: String = "all"
    private var networkCallback: ConnectivityManager.NetworkCallback? = null

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

        if (tunFd >= 0) {
            onTunReady?.invoke(tunFd)
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
            // No IPv6 route — mihomo TUN only has inet4-address.
            // Use TUN gateway as DNS so queries reliably enter TUN for dns-hijack.
            .addDnsServer("172.19.0.2")
            .setMtu(9000)
            .setBlocking(false)
            .addDisallowedApplication(packageName)

        // Tell Android this VPN is not metered — prevents traffic throttling
        // and allows background data for all apps through the VPN.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setMetered(false)
        }

        when (mode) {
            "whitelist" -> {
                for (pkg in apps) {
                    try { builder.addAllowedApplication(pkg) } catch (_: Exception) {}
                }
            }
            "blacklist" -> {
                for (pkg in apps) {
                    try { builder.addDisallowedApplication(pkg) } catch (_: Exception) {}
                }
            }
        }

        val pfd = builder.establish()
        if (pfd == null) {
            android.util.Log.e("YueLinkVpn", "establish() returned null — permission denied or another VPN active")
            tunSetupFailed = true
            onTunReady?.invoke(-1)
            return
        }

        // detachFd() transfers fd ownership to us. The ParcelFileDescriptor
        // no longer closes the fd on GC — we manage its lifecycle.
        // Without this, GC can close the fd at any time, silently killing TUN.
        tunFd = pfd.detachFd()

        onTunReady?.invoke(tunFd)

        // Start monitoring network changes for DNS updates
        startNetworkMonitor()
    }

    private fun stopTunnel() {
        tunSetupFailed = false
        stopNetworkMonitor()
        try {
            nativeStopProtect()
        } catch (_: UnsatisfiedLinkError) {}
        // Close the raw fd we own (adopted back into PFD for safe close)
        if (tunFd >= 0) {
            try {
                ParcelFileDescriptor.adoptFd(tunFd).close()
            } catch (_: Exception) {}
            tunFd = -1
        }
        onTunReady = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    fun getTunFd(): Int = tunFd

    override fun onDestroy() {
        stopTunnel()
        super.onDestroy()
    }

    override fun onRevoke() {
        stopTunnel()
    }

    // ── Network change monitoring ───────────────────────────────────────────
    // When the physical network changes (WiFi ↔ cellular), update mihomo's
    // system DNS and flush the resolver cache. Without this, DNS resolution
    // fails after network switches because cached servers are unreachable.
    // CMFA has an equivalent NetworkObserveModule.

    private fun startNetworkMonitor() {
        val cm = getSystemService(ConnectivityManager::class.java) ?: return

        val request = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
            .build()

        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onLinkPropertiesChanged(network: Network, lp: LinkProperties) {
                val dnsServers = lp.dnsServers
                    .mapNotNull { it.hostAddress }
                    .filter { it.isNotEmpty() }
                if (dnsServers.isNotEmpty()) {
                    val dnsList = dnsServers.joinToString(",")
                    android.util.Log.d("YueLinkVpn", "DNS changed: $dnsList")
                    try {
                        nativeNotifyDnsChanged(dnsList)
                    } catch (_: UnsatisfiedLinkError) {}
                }

                // Tell the system which physical network underlies the VPN.
                // This fixes connectivity detection ("no internet" warnings).
                try {
                    setUnderlyingNetworks(arrayOf(network))
                } catch (_: Exception) {}
            }

            override fun onLost(network: Network) {
                try {
                    setUnderlyingNetworks(null)
                } catch (_: Exception) {}
            }
        }

        try {
            cm.registerNetworkCallback(request, callback)
            networkCallback = callback
        } catch (_: Exception) {}
    }

    private fun stopNetworkMonitor() {
        val cb = networkCallback ?: return
        networkCallback = null
        try {
            val cm = getSystemService(ConnectivityManager::class.java)
            cm?.unregisterNetworkCallback(cb)
        } catch (_: Exception) {}
    }

    // ── Notification ────────────────────────────────────────────────────────

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
