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
        for fd: Int32 in 3...4096 {
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

        // Keep-alive interval: prevents NAT from dropping idle QUIC (hy2)
        // and TLS (anytls) sessions. 15s is safe for mobile carrier NATs.
        if !result.contains("keep-alive-interval:") {
            result += "\nkeep-alive-interval: 15\n"
        }

        // Ensure comprehensive DNS config for TUN fake-ip.
        // If subscription has no dns section, inject a full default.
        // If it does, patch it: ensure enable:true and inject nameserver-policy
        // for Apple/iCloud so DIRECT-routed Apple system services resolve via
        // domestic DoH (avoids "dial tcp 0.0.0.0:443" on blocked networks).
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
                + "    - \"+.apple.com\"\n"
                + "    - \"+.icloud.com\"\n"
                + "    - \"+.cdn-apple.com\"\n"
                + "    - \"+.mzstatic.com\"\n"
                + "    - \"+.push.apple.com\"\n"
                // Connectivity check domains — all platforms
                // Google / Android
                + "    - \"connectivitycheck.gstatic.com\"\n"
                + "    - \"www.gstatic.com\"\n"
                + "    - \"+.connectivitycheck.android.com\"\n"
                + "    - \"clients1.google.com\"\n"
                + "    - \"clients3.google.com\"\n"
                + "    - \"play.googleapis.com\"\n"
                // Apple captive portal
                + "    - \"captive.apple.com\"\n"
                + "    - \"gsp-ssl.ls.apple.com\"\n"
                + "    - \"gsp-ssl.ls-apple.com.akadns.net\"\n"
                // Microsoft
                + "    - \"www.msftconnecttest.com\"\n"
                + "    - \"www.msftncsi.com\"\n"
                + "    - \"dns.msftncsi.com\"\n"
                // Huawei
                + "    - \"connectivitycheck.platform.hicloud.com\"\n"
                + "    - \"+.wifi.huawei.com\"\n"
                // Samsung
                + "    - \"connectivitycheck.samsung.com\"\n"
                // Xiaomi
                + "    - \"connect.rom.miui.com\"\n"
                // Vivo / other
                + "    - \"wifi.vivo.com.cn\"\n"
                + "    - \"noisyfox.cn\"\n"
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
                + "  nameserver-policy:\n"
                + "    \"+.apple.com\": [\"https://doh.pub/dns-query\", \"https://dns.alidns.com/dns-query\"]\n"
                + "    \"+.icloud.com\": [\"https://doh.pub/dns-query\", \"https://dns.alidns.com/dns-query\"]\n"
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
        } else {
            result = ensureDnsPatched(result)
        }

        return result
    }

    /// Patch an existing dns section: ensure enable:true, inject
    /// nameserver-policy + direct-nameserver for Apple/iCloud if not present.
    /// Uses indent detection to match the subscription's YAML style (2-space
    /// or 4-space) — hardcoded indentation breaks go-yaml parsing.
    private func ensureDnsPatched(_ config: String) -> String {
        var result = config

        // Ensure enable: true
        guard let dnsRange = result.range(
            of: #"(?m)^dns:.*\n(?:[ \t]+.*\n)*"#, options: .regularExpression
        ) else { return result }

        let dnsBlock = String(result[dnsRange])
        if dnsBlock.contains("enable: false") {
            result = result.replacingCharacters(
                in: dnsRange,
                with: dnsBlock.replacingOccurrences(of: "enable: false", with: "enable: true")
            )
        } else if !dnsBlock.contains("enable: true") {
            if let dnsLineEnd = result.range(of: #"(?m)^dns:.*$"#, options: .regularExpression) {
                // Insert "enable: true" on the line after "dns:".
                // Guard against end-of-string to avoid index(after: endIndex) crash.
                if dnsLineEnd.upperBound < result.endIndex {
                    let insertPos = result.index(after: dnsLineEnd.upperBound)
                    result.insert(contentsOf: "  enable: true\n", at: insertPos)
                } else {
                    result.append("\n  enable: true\n")
                }
            }
        }

        // Re-capture dns block after enable:true changes
        guard let updatedRange = result.range(
            of: #"(?m)^dns:.*\n(?:[ \t]+.*\n)*"#, options: .regularExpression
        ) else { return result }
        let updatedBlock = String(result[updatedRange])

        // Detect indentation used by dns sub-keys (2-space or 4-space).
        // Without matching, go-yaml reports "did not find expected key".
        guard let indentMatch = updatedBlock.range(
            of: #"(?m)\n( +)\S"#, options: .regularExpression
        ) else { return result }

        // Extract the whitespace between \n and the first non-whitespace char
        let afterNewline = updatedBlock.index(after: indentMatch.lowerBound)
        let firstNonSpace = updatedBlock[indentMatch].drop(while: { $0 == "\n" || $0 == " " || $0 == "\t" }).startIndex
        let indent = String(updatedBlock[afterNewline..<firstNonSpace])

        // Detect entry indentation from existing list items (e.g. "    - ")
        var entryIndent = indent + "  " // default: indent + 2
        if let listMatch = updatedBlock.range(of: #"(?m)\n( +)- "#, options: .regularExpression) {
            let afterNl = updatedBlock.index(after: listMatch.lowerBound)
            let firstDash = updatedBlock[listMatch].drop(while: { $0 == "\n" || $0 == " " }).startIndex
            entryIndent = String(updatedBlock[afterNl..<firstDash])
        }

        // Inject prefer-h3 for DNS-over-HTTP/3 (QUIC) — faster DNS resolution,
        // avoids TCP DNS blocking on some networks.
        if !updatedBlock.contains("prefer-h3") {
            // Re-find dns block for insertion
            if let dnsLineRange = result.range(of: #"(?m)^dns:.*$"#, options: .regularExpression) {
                if dnsLineRange.upperBound < result.endIndex {
                    let insertPos = result.index(after: dnsLineRange.upperBound)
                    result.insert(contentsOf: "\(indent)prefer-h3: true\n", at: insertPos)
                }
            }
        }

        // Inject nameserver-policy for Apple/iCloud (used by main resolver).
        // On some networks, domestic UDP DNS returns 0.0.0.0 for Apple update
        // domains when subscription routes them DIRECT.
        // Re-capture dns block after possible prefer-h3 changes
        guard let updatedRange2 = result.range(
            of: #"(?m)^dns:.*\n(?:[ \t]+.*\n)*"#, options: .regularExpression
        ) else { return result }
        let updatedBlock2 = String(result[updatedRange2])
        if !updatedBlock2.contains("nameserver-policy:") {
            let policy = "\(indent)nameserver-policy:\n"
                + "\(entryIndent)\"+.apple.com\": [\"https://doh.pub/dns-query\", \"https://dns.alidns.com/dns-query\"]\n"
                + "\(entryIndent)\"+.icloud.com\": [\"https://doh.pub/dns-query\", \"https://dns.alidns.com/dns-query\"]\n"
            result.insert(contentsOf: policy, at: updatedRange2.upperBound)
        }

        // Inject direct-nameserver with DoH (used by direct resolver for
        // DIRECT outbound connections). This is critical — mihomo uses
        // direct-nameserver (not nameserver-policy) to resolve domains
        // when the rule says DIRECT. Without DoH, plain UDP DNS may be
        // poisoned and return 0.0.0.0 for Apple/other domains.
        if !updatedBlock2.contains("direct-nameserver:") {
            // Re-find dns block end after possible nameserver-policy injection
            if let finalRange = result.range(
                of: #"(?m)^dns:.*\n(?:[ \t]+.*\n)*"#, options: .regularExpression
            ) {
                let directNs = "\(indent)direct-nameserver:\n"
                    + "\(entryIndent)- https://doh.pub/dns-query\n"
                    + "\(entryIndent)- https://dns.alidns.com/dns-query\n"
                result.insert(contentsOf: directNs, at: finalRange.upperBound)
            }
        }

        // Fix 3: ensure connectivity-check domains are in fake-ip-filter.
        // Without these, Android/vendor connectivity checks resolve to fake IPs,
        // causing "no internet" / WiFi exclamation mark.
        let connectivityDomains = [
            // Google / Android
            "connectivitycheck.gstatic.com",
            "www.gstatic.com",
            "+.connectivitycheck.android.com",
            "clients1.google.com",
            "clients3.google.com",
            "play.googleapis.com",
            // Apple captive portal
            "captive.apple.com",
            "gsp-ssl.ls.apple.com",
            "gsp-ssl.ls-apple.com.akadns.net",
            // Microsoft
            "www.msftconnecttest.com",
            "www.msftncsi.com",
            "dns.msftncsi.com",
            // Huawei
            "connectivitycheck.platform.hicloud.com",
            "+.wifi.huawei.com",
            // Samsung
            "connectivitycheck.samsung.com",
            // Xiaomi
            "connect.rom.miui.com",
            // Vivo / other
            "wifi.vivo.com.cn",
            "noisyfox.cn",
        ]
        // Re-capture dns block for fake-ip-filter check
        if let fipRange = result.range(
            of: #"(?m)^dns:.*\n(?:[ \t]+.*\n)*"#, options: .regularExpression
        ) {
            let fipBlock = String(result[fipRange])
            if fipBlock.contains("fake-ip-filter:") {
                // Append missing domains to existing fake-ip-filter
                if let filterStart = fipBlock.range(of: #"fake-ip-filter:\s*\n"#, options: .regularExpression) {
                    // Find end of list items
                    let afterFilter = String(fipBlock[filterStart.upperBound...])
                    var insertOffset = fipRange.lowerBound
                    // Move to absolute position of filterStart.upperBound
                    let relativeOffset = fipBlock.distance(from: fipBlock.startIndex, to: filterStart.upperBound)
                    insertOffset = result.index(fipRange.lowerBound, offsetBy: relativeOffset)
                    // Find where list items end
                    if let listEnd = afterFilter.range(of: #"(?m)^(?![ \t]+- )"#, options: .regularExpression) {
                        let listEndOffset = afterFilter.distance(from: afterFilter.startIndex, to: listEnd.lowerBound)
                        insertOffset = result.index(insertOffset, offsetBy: listEndOffset)
                    }
                    var injection = ""
                    for domain in connectivityDomains {
                        if !fipBlock.contains(domain) {
                            injection += "\(entryIndent)- \"\(domain)\"\n"
                        }
                    }
                    if !injection.isEmpty {
                        result.insert(contentsOf: injection, at: insertOffset)
                    }
                }
            } else {
                // No fake-ip-filter at all — inject one with connectivity domains
                let items = connectivityDomains.map { "\(entryIndent)- \"\($0)\"" }.joined(separator: "\n")
                let filterBlock = "\(indent)fake-ip-filter:\n\(items)\n"
                result.insert(contentsOf: filterBlock, at: fipRange.upperBound)
            }
        }

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

        // Inject TUN fd for hot-reload too
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
