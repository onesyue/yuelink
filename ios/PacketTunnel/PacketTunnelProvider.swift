import NetworkExtension

// libclash.a is statically linked — declare the C functions directly.
// These symbols come from core/hub.go (exported via CGo).
// InitCore returns a C string: "" on success, error message on failure.
// Caller must free the returned string via FreeCString.
@_silgen_name("InitCore")
func InitCore(_ homeDir: UnsafePointer<CChar>!) -> UnsafeMutablePointer<CChar>!

@_silgen_name("StartCore")
func StartCore(_ configYaml: UnsafePointer<CChar>!) -> UnsafeMutablePointer<CChar>!

@_silgen_name("StopCore")
func StopCore()

@_silgen_name("IsRunning")
func IsRunning() -> Int32

@_silgen_name("FreeCString")
func FreeCString(_ s: UnsafeMutablePointer<CChar>!)

class PacketTunnelProvider: NEPacketTunnelProvider {

    private let appGroup = "group.com.yueto.yuelink"
    /// Cached TUN file descriptor — avoids re-scanning 4094 fds on every config update.
    private var cachedTunFd: Int32 = -1

    override func startTunnel(
        options: [String: NSObject]?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        // TUN address: 172.19.0.1/30 (matches mihomo tun.inet4-address below
        // in injectTunConfig). The /30 prefix gives us 4 addresses
        // (172.19.0.0 network, .1 us, .2 peer, .3 broadcast) which is the
        // smallest valid IPv4 subnet — all the dns-hijack traffic goes
        // through this TUN regardless of subnet size.
        // DNS: real servers, but mihomo's dns-hijack intercepts all queries
        // on port 53 through the TUN for fake-ip resolution.
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "254.1.1.1")

        // 255.255.255.252 == /30. Previously this was 255.255.252.0 (/22),
        // a typo that gave the TUN a 1024-host subnet and disagreed with
        // the mihomo inet4-address line below — causing inconsistent
        // routing decisions in iOS networkd vs mihomo.
        let ipv4 = NEIPv4Settings(addresses: ["172.19.0.1"], subnetMasks: ["255.255.255.252"])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4

        settings.dnsSettings = NEDNSSettings(servers: ["223.5.5.5", "8.8.8.8"])
        settings.mtu = 9000

        setTunnelNetworkSettings(settings) { [weak self] error in
            if let error = error {
                completionHandler(error)
                return
            }

            guard let self = self else {
                completionHandler(TunnelError.startFailed)
                return
            }

            self.startMihomoCore(completionHandler: completionHandler)
        }
    }

    /// Find the TUN file descriptor created by NEPacketTunnelProvider.
    /// Scans open fds for a utun device (public API, no private KVC).
    /// Takes the LAST (highest-numbered) utun found — our tunnel is the most
    /// recently created one, so it has the highest fd among any open utuns.
    /// Results are cached — invalidate with `cachedTunFd = -1` on error.
    private func findTunFd() -> Int32 {
        if cachedTunFd > 0 { return cachedTunFd }
        var buf = [CChar](repeating: 0, count: Int(IFNAMSIZ))
        var found: Int32 = -1
        for fd: Int32 in 3...4096 {
            var len = socklen_t(buf.count)
            // SYSPROTO_CONTROL = 2, UTUN_OPT_IFNAME = 2
            if getsockopt(fd, 2, 2, &buf, &len) == 0 {
                let name = String(cString: buf)
                if name.hasPrefix("utun") {
                    found = fd  // keep updating — we want the highest fd
                }
            }
        }
        if found > 0 { cachedTunFd = found }
        return found
    }

    /// Inject TUN configuration into the mihomo config YAML.
    /// Removes any existing tun section and appends an iOS-safe one.
    /// Also ensures comprehensive DNS config and disables find-process-mode.
    private func injectTunConfig(_ config: String, fd: Int32) -> String {
        var result = config

        // Remove existing tun section
        if let range = result.range(of: #"(?m)^tun:.*\n(?:[ \t]+.*\n)*"#, options: .regularExpression) {
            result.removeSubrange(range)
        }

        // Force find-process-mode: off on iOS (no permission, avoids overhead)
        if let range = result.range(of: #"(?m)^find-process-mode:.*$"#, options: .regularExpression) {
            result.replaceSubrange(range, with: "find-process-mode: off")
        } else {
            result += "\nfind-process-mode: off\n"
        }

        // Append iOS-safe TUN config (matches NEPacketTunnelNetworkSettings)
        result += "\ntun:\n"
            + "  enable: true\n"
            + "  stack: gvisor\n"
            + "  file-descriptor: \(fd)\n"
            + "  inet4-address:\n"
            + "    - 172.19.0.1/30\n"
            + "  mtu: 9000\n"
            + "  auto-route: false\n"
            + "  auto-detect-interface: false\n"
            + "  dns-hijack:\n"
            + "    - any:53\n"

        // Keep-alive interval: prevents NAT from dropping idle QUIC (hy2)
        // and TLS (anytls) sessions. 15s is safe for mobile carrier NATs.
        // Dart _ensurePerformance may have already injected this — guard with contains().
        if !result.contains("keep-alive-interval:") {
            result += "\nkeep-alive-interval: 15\n"
        }

        // ── DNS handling ──
        // DNS config is fully handled by Dart's ConfigTemplate._ensureDns() BEFORE
        // the config reaches this extension process. The config written to App Group
        // by AppDelegate has already been through ConfigTemplate.process() which:
        //   - Injects full dns section when missing
        //   - Ensures enable:true, prefer-h3, nameserver-policy for Apple/iCloud
        //   - Adds connectivity-check domains to fake-ip-filter
        //   - Adds direct-nameserver, proxy-server-nameserver
        //
        // DO NOT add DNS injection here — it would duplicate Dart's work and create
        // a maintenance burden (two copies of the same logic in different languages).
        // See: lib/core/kernel/config_template.dart _ensureDns()

        return result
    }

    override func stopTunnel(
        with reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        StopCore()
        // Wait briefly for Go runtime to finish shutdown (close sockets,
        // flush fake-ip store) before the system kills the extension process.
        DispatchQueue.global().async {
            for _ in 0..<20 {
                if IsRunning() == 0 { break }
                Thread.sleep(forTimeInterval: 0.05)
            }
            completionHandler()
        }
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        // IPC: main app sends updated config → hot-reload
        // Message format: raw UTF-8 config YAML bytes
        guard var configYaml = String(data: messageData, encoding: .utf8) else {
            completionHandler?(nil)
            return
        }

        // Inject TUN fd for hot-reload too (invalidate cache for safety)
        cachedTunFd = -1
        let tunFd = findTunFd()
        if tunFd > 0 {
            configYaml = injectTunConfig(configYaml, fd: tunFd)
        }

        // Write new config to app group and reload
        writeConfig(configYaml)

        // Stop existing core before restarting to avoid resource leaks
        if IsRunning() == 1 {
            StopCore()
        }
        let startOk = startCoreWithConfig(configYaml)
        let response = Data([startOk ? 1 : 0])
        completionHandler?(response)
    }

    // MARK: - Private

    private func startMihomoCore(completionHandler: @escaping (Error?) -> Void) {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroup
        ) else {
            completionHandler(TunnelError.noAppGroup)
            return
        }

        let homeDir = containerURL.appendingPathComponent("mihomo").path
        let configPath = containerURL.appendingPathComponent("mihomo/config.yaml").path

        // Ensure home directory exists
        do {
            try FileManager.default.createDirectory(
                atPath: homeDir,
                withIntermediateDirectories: true
            )
        } catch {
            NSLog("[PacketTunnel] ERROR: Failed to create home directory: %@", error.localizedDescription)
        }

        // Read config written by the main app
        guard var configYaml = try? String(contentsOfFile: configPath, encoding: .utf8),
              !configYaml.isEmpty else {
            NSLog("[PacketTunnel] ERROR: Config file missing or empty at %@", configPath)
            completionHandler(TunnelError.noConfig)
            return
        }

        // Inject TUN fd so mihomo reads packets from the system VPN tunnel.
        // Without this fd, no traffic is processed — fail early rather than
        // silently running a broken tunnel that appears connected but drops all packets.
        // Invalidate cache — tunnel was just (re)created, old fd may be stale.
        cachedTunFd = -1
        let tunFd = findTunFd()
        guard tunFd > 0 else {
            NSLog("[PacketTunnel] ERROR: Could not find TUN fd — refusing to start broken tunnel")
            completionHandler(TunnelError.noTunFd)
            return
        }
        NSLog("[PacketTunnel] Found TUN fd: %d", tunFd)
        configYaml = injectTunConfig(configYaml, fd: tunFd)

        // Initialize Go core with home directory
        let initResultPtr = homeDir.withCString { ptr in
            InitCore(ptr)
        }
        if let resultPtr = initResultPtr {
            let errorMsg = String(cString: resultPtr)
            FreeCString(resultPtr)
            if !errorMsg.isEmpty {
                NSLog("[PacketTunnel] InitCore failed: %@", errorMsg)
                completionHandler(TunnelError.initFailed)
                return
            }
        }

        // Start Go core with config
        guard startCoreWithConfig(configYaml) else {
            completionHandler(TunnelError.startFailed)
            return
        }

        completionHandler(nil)
    }

    /// Call StartCore and check the returned error string.
    /// Returns true on success, false on failure.
    private func startCoreWithConfig(_ configYaml: String) -> Bool {
        let resultPtr = configYaml.withCString { ptr in
            StartCore(ptr)
        }
        if let ptr = resultPtr {
            let errorMsg = String(cString: ptr)
            FreeCString(ptr)
            if !errorMsg.isEmpty {
                NSLog("[PacketTunnel] StartCore failed: %@", errorMsg)
                return false
            }
        }
        return true
    }

    private func writeConfig(_ yaml: String) {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroup
        ) else { return }

        let dir = containerURL.appendingPathComponent("mihomo")
        try? FileManager.default.createDirectory(
            atPath: dir.path, withIntermediateDirectories: true
        )
        try? yaml.write(
            to: dir.appendingPathComponent("config.yaml"),
            atomically: true,
            encoding: .utf8
        )
    }
}

enum TunnelError: LocalizedError {
    case noAppGroup
    case noConfig
    case noTunFd
    case initFailed
    case startFailed

    var errorDescription: String? {
        switch self {
        case .noAppGroup:  return "Cannot access App Group container"
        case .noConfig:    return "No config found in App Group — start from main app first"
        case .noTunFd:     return "Could not find TUN file descriptor — VPN tunnel not ready"
        case .initFailed:  return "mihomo InitCore failed"
        case .startFailed: return "mihomo StartCore failed"
        }
    }
}
