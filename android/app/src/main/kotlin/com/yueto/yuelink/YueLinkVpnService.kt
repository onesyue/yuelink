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
import android.net.ProxyInfo
import android.net.NetworkRequest
import android.net.VpnService
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.os.ParcelFileDescriptor
import android.provider.Settings

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
        private const val DEFAULT_TUN_MTU = 9000

        // Public IPv4 coverage excluding loopback, LAN/private, link-local,
        // multicast and common local-control ranges. This mirrors the route
        // shape used by Clash Meta on Android instead of installing a blunt
        // 0.0.0.0/0 route that drags NAS, printer, hotspot and router traffic
        // through the VPN unnecessarily.
        private val PUBLIC_IPV4_ROUTES = arrayOf(
            "1.0.0.0" to 8,
            "2.0.0.0" to 7,
            "4.0.0.0" to 6,
            "8.0.0.0" to 7,
            "11.0.0.0" to 8,
            "12.0.0.0" to 6,
            "16.0.0.0" to 4,
            "32.0.0.0" to 3,
            "64.0.0.0" to 3,
            "96.0.0.0" to 4,
            "112.0.0.0" to 5,
            "120.0.0.0" to 6,
            "124.0.0.0" to 7,
            "126.0.0.0" to 8,
            "128.0.0.0" to 3,
            "160.0.0.0" to 5,
            "168.0.0.0" to 8,
            "169.0.0.0" to 9,
            "169.128.0.0" to 10,
            "169.192.0.0" to 11,
            "169.224.0.0" to 12,
            "169.240.0.0" to 13,
            "169.248.0.0" to 14,
            "169.252.0.0" to 15,
            "169.255.0.0" to 16,
            "170.0.0.0" to 7,
            "172.0.0.0" to 12,
            "172.32.0.0" to 11,
            "172.64.0.0" to 10,
            "172.128.0.0" to 9,
            "173.0.0.0" to 8,
            "174.0.0.0" to 7,
            "176.0.0.0" to 4,
            "192.0.0.0" to 9,
            "192.128.0.0" to 11,
            "192.160.0.0" to 13,
            "192.169.0.0" to 16,
            "192.170.0.0" to 15,
            "192.172.0.0" to 14,
            "192.176.0.0" to 12,
            "192.192.0.0" to 10,
            "193.0.0.0" to 8,
            "194.0.0.0" to 7,
            "196.0.0.0" to 6,
            "200.0.0.0" to 5,
            "208.0.0.0" to 4,
        )

        private val VPN_HTTP_PROXY_EXCLUSIONS = listOf(
            "localhost",
            "*.local",
            "*.lan",
            "127.*",
            "10.*",
            "169.254.*",
            "172.16.*",
            "172.17.*",
            "172.18.*",
            "172.19.*",
            "172.20.*",
            "172.21.*",
            "172.22.*",
            "172.23.*",
            "172.24.*",
            "172.25.*",
            "172.26.*",
            "172.27.*",
            "172.28.*",
            "172.29.*",
            "172.30.*",
            "172.31.*",
            "192.168.*",
        )

        /** Called when VPN is revoked by the system or another app. */
        var onVpnRevoked: (() -> Unit)? = null

        /**
         * Called when the primary underlying transport flips (e.g. Wi-Fi →
         * cellular on elevator entry). Args: (oldTransport, newTransport),
         * values ∈ {"none","wifi","cellular","ethernet","other"}.
         */
        var onTransportChanged: ((String, String) -> Unit)? = null

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
    // Last-seen primary transport: "wifi" / "cellular" / "ethernet" / "none".
    // When this flips (e.g. Wi-Fi dropped → cellular picked up), Dart is
    // notified so it can flush fake-ip + close stale connections.
    private var lastTransport: String = "none"
    private var lastPrimaryNetwork: Network? = null

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
            // No IPv6 route — mihomo TUN only has inet4-address.
            // Use TUN gateway as DNS so queries reliably enter TUN for dns-hijack.
            .addDnsServer("172.19.0.2")
            .setMtu(DEFAULT_TUN_MTU)
            .setBlocking(false)

        addPublicIpv4Routes(builder)
        configureVpnHttpProxy(builder, mixedPort)
        logPrivateDnsState()

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

    private fun addPublicIpv4Routes(builder: Builder) {
        for ((address, prefix) in PUBLIC_IPV4_ROUTES) {
            builder.addRoute(address, prefix)
        }
        // Host route for the synthetic DNS peer used by addDnsServer().
        builder.addRoute("172.19.0.2", 32)
    }

    private fun configureVpnHttpProxy(builder: Builder, mixedPort: Int) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
        try {
            builder.setHttpProxy(
                ProxyInfo.buildDirectProxy(
                    "127.0.0.1",
                    mixedPort,
                    VPN_HTTP_PROXY_EXCLUSIONS,
                ),
            )
        } catch (e: Exception) {
            android.util.Log.w("YueLinkVpn", "setHttpProxy failed: ${e.message}")
        }
    }

    private fun logPrivateDnsState() {
        try {
            val mode = Settings.Global.getString(contentResolver, "private_dns_mode")
            val spec = Settings.Global.getString(contentResolver, "private_dns_specifier")
            if (mode == "hostname" || mode == "opportunistic") {
                android.util.Log.i(
                    "YueLinkVpn",
                    "Android Private DNS is $mode${if (spec.isNullOrBlank()) "" else " ($spec)"}; " +
                        "DNS hijack depends on the platform allowing VPN DNS capture",
                )
            }
        } catch (_: Exception) {}
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
                notifyDnsFromLinkProperties(network, lp)
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
     *
     * Also computes the new primary transport — if it changed since last
     * check, fires [onTransportChanged] so Dart can flush fake-ip cache and
     * close stale TCP connections. Without this, Wi-Fi↔cellular transitions
     * leave the connection pool pointing at the old interface for up to
     * the TCP keep-alive timeout (~30 s), which the user perceives as
     * "everything froze" right after walking into the elevator.
     */
    private fun applyUnderlyingNetworks() {
        try {
            val cm = getSystemService(ConnectivityManager::class.java) ?: return
            val rawNets = synchronized(availableNetworks) { availableNetworks.toTypedArray() }
            val nets = orderUnderlyingNetworks(cm, rawNets)
            val primary = primaryNetwork(cm, nets)
            setUnderlyingNetworks(if (nets.isEmpty()) null else nets)
            android.util.Log.d("YueLinkVpn",
                "underlyingNetworks: ${nets.size}, active=${cm.activeNetwork}")

            val newTransport = computePrimaryTransport(cm, nets, primary)
            val primaryChanged = primary != lastPrimaryNetwork
            if (newTransport != lastTransport || primaryChanged) {
                val prev = lastTransport
                lastTransport = newTransport
                lastPrimaryNetwork = primary
                android.util.Log.d("YueLinkVpn",
                    "transport changed: $prev → $newTransport primary=$primary")
                notifyDnsForPrimaryNetwork(cm, nets, primary)
                try {
                    onTransportChanged?.invoke(prev, newTransport)
                } catch (e: Exception) {
                    android.util.Log.w("YueLinkVpn",
                        "onTransportChanged threw: ${e.message}")
                }
            }
        } catch (_: Exception) {}
    }

    private fun orderUnderlyingNetworks(
        cm: ConnectivityManager,
        nets: Array<Network>
    ): Array<Network> {
        if (nets.size <= 1) return nets
        val active = cm.activeNetwork ?: return nets
        if (!nets.any { it == active }) return nets
        val ordered = mutableListOf<Network>()
        ordered.add(active)
        for (n in nets) {
            if (n != active) ordered.add(n)
        }
        return ordered.toTypedArray()
    }

    private fun primaryNetwork(
        cm: ConnectivityManager,
        nets: Array<Network>
    ): Network? {
        if (nets.isEmpty()) return null
        val active = cm.activeNetwork
        if (active != null && nets.any { it == active }) return active
        return nets.first()
    }

    /** Reduce a set of underlying networks to one primary transport label. */
    private fun computePrimaryTransport(
        cm: ConnectivityManager,
        nets: Array<Network>,
        primary: Network?
    ): String {
        if (nets.isEmpty()) return "none"
        // Prefer Android's current default physical network. It changes only
        // after network scoring/validation has settled, which avoids switching
        // YueLink onto Wi-Fi while the system still routes through cellular.
        if (primary != null) {
            transportLabel(cm, primary)?.let { return it }
        }

        // Fallback when activeNetwork is unavailable or not in the physical
        // set yet: wifi > ethernet > cellular > other.
        var hasWifi = false
        var hasEthernet = false
        var hasCellular = false
        for (n in nets) {
            when (transportLabel(cm, n)) {
                "wifi" -> hasWifi = true
                "ethernet" -> hasEthernet = true
                "cellular" -> hasCellular = true
            }
        }
        return when {
            hasWifi -> "wifi"
            hasEthernet -> "ethernet"
            hasCellular -> "cellular"
            else -> "other"
        }
    }

    private fun transportLabel(cm: ConnectivityManager, network: Network): String? {
        val caps = cm.getNetworkCapabilities(network) ?: return null
        return when {
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
            else -> "other"
        }
    }

    private fun notifyDnsForPrimaryNetwork(
        cm: ConnectivityManager,
        nets: Array<Network>,
        primary: Network?
    ) {
        if (nets.isEmpty()) return
        val network = primary ?: nets.first()
        val lp = cm.getLinkProperties(network) ?: return
        notifyDnsFromLinkProperties(network, lp)
    }

    private fun notifyDnsFromLinkProperties(network: Network, lp: LinkProperties) {
        val dnsServers = lp.dnsServers
            .mapNotNull { it.hostAddress }
            .filter { it.isNotEmpty() }
        if (dnsServers.isEmpty()) return
        val dnsList = dnsServers.joinToString(",")
        android.util.Log.d("YueLinkVpn", "DNS changed on $network: $dnsList")
        try { nativeNotifyDnsChanged(dnsList) } catch (_: UnsatisfiedLinkError) {}
    }

    private fun stopNetworkMonitor() {
        val cb = networkCallback ?: return
        networkCallback = null
        synchronized(availableNetworks) { availableNetworks.clear() }
        lastPrimaryNetwork = null
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
