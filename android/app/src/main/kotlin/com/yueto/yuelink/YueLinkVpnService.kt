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

        /** Called when VPN is revoked by the system or another app. */
        var onVpnRevoked: (() -> Unit)? = null

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
    // Tracks all currently available physical networks (INTERNET + NOT_VPN).
    // Passed to setUnderlyingNetworks() so the VPN correctly reflects WiFi
    // (or cellular) as its underlying transport. Without this set, the VPN
    // defaults to the last network that fired onLinkPropertiesChanged, which
    // is often cellular even when WiFi is active — causing the WiFi "!" icon.
    private val availableNetworks = mutableSetOf<Network>()

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
        // START_NOT_STICKY: do not auto-restart after user stops VPN.
        // START_STICKY caused the service to resurrect after user explicitly
        // disconnected, making the toggle feel broken.
        return START_NOT_STICKY
    }

    private fun startTunnel(mixedPort: Int, mode: String, apps: List<String>) {
        // Reset stop guard so stopTunnel() works on subsequent stop calls.
        // Android can reuse the same Service instance across start/stop cycles.
        stopped = false
        // Force fresh tunnel establishment — stale fd from a previous session
        // that died without stopTunnel() would cause silent VPN failure.
        tunFd = -1

        // Must call startForeground ASAP (within 5s of startForegroundService)
        // to avoid ANR. Call it before establish() which may take time.
        startForeground(NOTIFICATION_ID, createNotification())

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
            // mtu: 1500 matches the physical cellular/Wi-Fi MTU. The
            // previous 9000 was inherited from mihomo's jumbo-frame
            // default (only makes sense for desktop utun), but Android
            // apps emit IP packets through the kernel socket layer
            // which is still bound to the physical MTU — the extra 7500
            // bytes of TUN MTU weren't helping and wasted buffer memory
            // in sing-tun's gvisor stack. Clash Meta for Android and
            // mihomo-party desktop both use 1500.
            .setMtu(1500)
            .setBlocking(false)

        // Tell Android this VPN is not metered — prevents traffic throttling
        // and allows background data for all apps through the VPN.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setMetered(false)
        }

        // Android VPN API requires EITHER addAllowedApplication OR addDisallowedApplication,
        // never both — calling both throws IllegalArgumentException.
        // Whitelist mode: only specified apps go through VPN (addAllowedApplication).
        // Blacklist / all mode: all apps except specified ones (addDisallowedApplication).
        when (mode) {
            "whitelist" -> {
                for (pkg in apps) {
                    try { builder.addAllowedApplication(pkg) } catch (_: Exception) {}
                }
                // In whitelist mode, our own app must also be allowed to protect sockets
                try { builder.addAllowedApplication(packageName) } catch (_: Exception) {}
            }
            else -> {
                // Always exclude ourselves to prevent routing loops
                builder.addDisallowedApplication(packageName)
                if (mode == "blacklist") {
                    for (pkg in apps) {
                        try { builder.addDisallowedApplication(pkg) } catch (_: Exception) {}
                    }
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

        // Start monitoring network changes for DNS updates and underlying-network
        // tracking. Must come AFTER establish() so setUnderlyingNetworks() works.
        startNetworkMonitor()
    }

    private var stopped = false

    fun stopTunnel() {
        // Guard against double-call from onStartCommand(STOP) + onDestroy/onRevoke
        if (stopped) return
        stopped = true

        tunSetupFailed = false
        stopNetworkMonitor()
        try {
            nativeStopProtect()
        } catch (_: Exception) {}
        // Do NOT close the TUN fd here — Go core's executor.Shutdown()
        // (called from StopCore FFI) already closes it via sing-tun.
        // Calling ParcelFileDescriptor.adoptFd(tunFd).close() on an
        // already-closed fd causes a native SIGABRT/SIGSEGV that crashes
        // the entire Flutter process. Just reset the reference.
        tunFd = -1
        onTunReady = null
        try {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } catch (_: Exception) {}
        stopSelf()
    }

    fun getTunFd(): Int = tunFd

    override fun onDestroy() {
        stopTunnel()
        super.onDestroy()
    }

    override fun onRevoke() {
        onVpnRevoked?.invoke()
        stopTunnel()
    }

    // ── Network change monitoring ───────────────────────────────────────────
    // Tracks all active physical networks (INTERNET + NOT_VPN) in a set.
    // Passes the full set to setUnderlyingNetworks() on every change so the
    // VPN's underlying transport correctly reflects WiFi when WiFi is up.
    //
    // Previous code only called setUnderlyingNetworks() in onLinkPropertiesChanged,
    // meaning the underlying was whichever network last had a DNS change (often
    // cellular), not the highest-priority network. This caused the WiFi "!" icon.
    //
    // Reference: ClashMetaForAndroid NetworkObserveModule, FlClash VpnService.

    private fun startNetworkMonitor() {
        val cm = getSystemService(ConnectivityManager::class.java) ?: return

        // Seed availableNetworks with currently validated physical networks so
        // setUnderlyingNetworks is correct immediately (don't wait for first callback).
        for (net in cm.allNetworks) {
            val caps = cm.getNetworkCapabilities(net) ?: continue
            if (caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)) {
                synchronized(availableNetworks) { availableNetworks.add(net) }
            }
        }
        applyUnderlyingNetworks()

        val request = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
            .build()

        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                synchronized(availableNetworks) { availableNetworks.add(network) }
                applyUnderlyingNetworks()
            }

            override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) {
                // Network gained/lost VALIDATED — keep set accurate.
                if (caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                    caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)) {
                    synchronized(availableNetworks) { availableNetworks.add(network) }
                } else {
                    synchronized(availableNetworks) { availableNetworks.remove(network) }
                }
                applyUnderlyingNetworks()
            }

            override fun onLinkPropertiesChanged(network: Network, lp: LinkProperties) {
                // Forward updated DNS to mihomo so it can reach nameservers on the
                // new interface after WiFi ↔ cellular switches.
                val dnsServers = lp.dnsServers
                    .mapNotNull { it.hostAddress }
                    .filter { it.isNotEmpty() }
                if (dnsServers.isNotEmpty()) {
                    val dnsList = dnsServers.joinToString(",")
                    android.util.Log.d("YueLinkVpn", "DNS changed on $network: $dnsList")
                    try { nativeNotifyDnsChanged(dnsList) } catch (_: UnsatisfiedLinkError) {}
                }
            }

            override fun onLost(network: Network) {
                synchronized(availableNetworks) { availableNetworks.remove(network) }
                applyUnderlyingNetworks()
            }
        }

        try {
            cm.registerNetworkCallback(request, callback)
            networkCallback = callback
        } catch (_: Exception) {}
    }

    /**
     * Push the current physical network set to VpnService.setUnderlyingNetworks().
     * Passing null lets the system decide; passing the explicit set makes
     * Android show the correct transport icon (WiFi instead of cellular "!" icon).
     */
    private fun applyUnderlyingNetworks() {
        try {
            val nets = synchronized(availableNetworks) { availableNetworks.toTypedArray() }
            setUnderlyingNetworks(if (nets.isEmpty()) null else nets)
            android.util.Log.d("YueLinkVpn", "underlyingNetworks: ${nets.size}")
        } catch (_: Exception) {}
    }

    private fun stopNetworkMonitor() {
        val cb = networkCallback ?: return
        networkCallback = null
        synchronized(availableNetworks) { availableNetworks.clear() }
        try {
            val cm = getSystemService(ConnectivityManager::class.java)
            cm?.unregisterNetworkCallback(cb)
        } catch (_: Exception) {}
    }

    // ── Notification ────────────────────────────────────────────────────────

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "YueLink",
            // IMPORTANCE_MIN: notification only visible when shade is pulled down,
            // no status bar icon from the app (system VPN key icon remains).
            NotificationManager.IMPORTANCE_MIN
        ).apply { description = "YueLink service status" }
        // `?.` — some OEM ROMs return null here even though docs say non-null,
        // and an NPE inside startForeground() would crash the service.
        getSystemService(NotificationManager::class.java)?.createNotificationChannel(channel)
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
            // Do not set ongoing — let user swipe away if desired
            .build()
    }
}
