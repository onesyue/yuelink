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

@_silgen_name("FreeCString")
func FreeCString(_ s: UnsafeMutablePointer<CChar>!)

class PacketTunnelProvider: NEPacketTunnelProvider {

    private let appGroup = "group.com.yueto.yuelink"

    override func startTunnel(
        options: [String: NSObject]?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        // TUN address: 172.19.0.1/30 (matches mihomo tun.inet4-address).
        // DNS: real servers, but mihomo's dns-hijack intercepts all queries
        // on port 53 through the TUN for fake-ip resolution.
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "254.1.1.1")

        let ipv4 = NEIPv4Settings(addresses: ["172.19.0.1"], subnetMasks: ["255.255.252.0"])
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
                completionHandler(nil)
                return
            }

            self.startMihomoCore(completionHandler: completionHandler)
        }
    }

    /// Find the TUN file descriptor created by NEPacketTunnelProvider.
    /// Scans open fds for a utun device (public API, no private KVC).
    private func findTunFd() -> Int32 {
        var buf = [CChar](repeating: 0, count: Int(IFNAMSIZ))
        for fd: Int32 in 0...1024 {
            var len = socklen_t(buf.count)
            // SYSPROTO_CONTROL = 2, UTUN_OPT_IFNAME = 2
            if getsockopt(fd, 2, 2, &buf, &len) == 0 {
                let name = String(cString: buf)
                if name.hasPrefix("utun") {
                    return fd
                }
            }
        }
        return -1
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

        // Ensure comprehensive DNS config for TUN fake-ip
        if result.range(of: #"(?m)^dns:"#, options: .regularExpression) == nil {
            result += "\ndns:\n"
                + "  enable: true\n"
                + "  prefer-h3: true\n"
                + "  enhanced-mode: fake-ip\n"
                + "  fake-ip-range: 198.18.0.1/16\n"
                + "  fake-ip-filter:\n"
                + "    - \"+.lan\"\n"
                + "    - \"+.local\"\n"
                + "    - \"+.direct\"\n"
                + "    - \"+.msftconnecttest.com\"\n"
                + "    - \"+.msftncsi.com\"\n"
                + "    - \"localhost.ptlogin2.qq.com\"\n"
                + "    - \"+.srv.nintendo.net\"\n"
                + "    - \"+.stun.playstation.net\"\n"
                + "    - \"+.xboxlive.com\"\n"
                + "    - \"+.ntp.org\"\n"
                + "    - \"+.pool.ntp.org\"\n"
                + "    - \"+.time.edu.cn\"\n"
                + "    - \"+.push.apple.com\"\n"
                + "  default-nameserver:\n"
                + "    - 223.5.5.5\n"
                + "    - 119.29.29.29\n"
                + "    - 8.8.8.8\n"
                + "  nameserver:\n"
                + "    - https://doh.pub/dns-query\n"
                + "    - https://dns.alidns.com/dns-query\n"
                + "  direct-nameserver:\n"
                + "    - https://doh.pub/dns-query\n"
                + "    - https://dns.alidns.com/dns-query\n"
                + "  proxy-server-nameserver:\n"
                + "    - https://doh.pub/dns-query\n"
                + "    - https://dns.alidns.com/dns-query\n"
                + "  fallback:\n"
                + "    - \"tls://8.8.4.4:853\"\n"
                + "    - \"tls://1.0.0.1:853\"\n"
                + "    - \"https://1.0.0.1/dns-query\"\n"
                + "    - \"https://8.8.4.4/dns-query\"\n"
                + "  fallback-filter:\n"
                + "    geoip: true\n"
                + "    geoip-code: CN\n"
                + "    geosite:\n"
                + "      - gfw\n"
                + "    domain:\n"
                + "      - \"+.google.com\"\n"
                + "      - \"+.facebook.com\"\n"
                + "      - \"+.youtube.com\"\n"
                + "      - \"+.github.com\"\n"
                + "      - \"+.googleapis.com\"\n"
        }

        return result
    }

    override func stopTunnel(
        with reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        StopCore()
        completionHandler()
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        // IPC: main app sends updated config → hot-reload
        // Message format: raw UTF-8 config YAML bytes
        guard var configYaml = String(data: messageData, encoding: .utf8) else {
            completionHandler?(nil)
            return
        }

        // Inject TUN fd for hot-reload too
        let tunFd = findTunFd()
        if tunFd > 0 {
            configYaml = injectTunConfig(configYaml, fd: tunFd)
        }

        // Write new config to app group and reload
        writeConfig(configYaml)

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
        try? FileManager.default.createDirectory(
            atPath: homeDir,
            withIntermediateDirectories: true
        )

        // Read config written by the main app
        guard var configYaml = try? String(contentsOfFile: configPath, encoding: .utf8),
              !configYaml.isEmpty else {
            completionHandler(TunnelError.noConfig)
            return
        }

        // Inject TUN fd so mihomo reads packets from the system VPN tunnel.
        // Without this, mihomo only listens on mixed-port but no traffic
        // reaches it because NEPacketTunnelProvider routes at the IP level.
        let tunFd = findTunFd()
        if tunFd > 0 {
            NSLog("[PacketTunnel] Found TUN fd: %d", tunFd)
            configYaml = injectTunConfig(configYaml, fd: tunFd)
        } else {
            NSLog("[PacketTunnel] WARNING: Could not find TUN fd")
        }

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
    case initFailed
    case startFailed

    var errorDescription: String? {
        switch self {
        case .noAppGroup:  return "Cannot access App Group container"
        case .noConfig:    return "No config found in App Group — start from main app first"
        case .initFailed:  return "mihomo InitCore failed"
        case .startFailed: return "mihomo StartCore failed"
        }
    }
}
