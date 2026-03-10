import NetworkExtension

// libclash.a is statically linked — declare the C functions directly.
// These symbols come from core/hub.go (exported via CGo).
// InitCore returns a C string: "" on success, error message on failure.
// Caller must free the returned string via FreeCString.
@_silgen_name("InitCore")
func InitCore(_ homeDir: UnsafePointer<CChar>!) -> UnsafeMutablePointer<CChar>!

@_silgen_name("StartCore")
func StartCore(_ configYaml: UnsafePointer<CChar>!) -> Int32

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
        // Network settings match what VpnService sets on Android:
        // fake-ip range 198.18.0.1/16 with default route
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "254.1.1.1")

        let ipv4 = NEIPv4Settings(addresses: ["198.18.0.1"], subnetMasks: ["255.255.0.0"])
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
        guard let configYaml = String(data: messageData, encoding: .utf8) else {
            completionHandler?(nil)
            return
        }

        // Write new config to app group and reload
        writeConfig(configYaml)

        let result = configYaml.withCString { ptr in
            StartCore(ptr)
        }
        let response = Data([result == 0 ? 1 : 0])
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
        guard let configYaml = try? String(contentsOfFile: configPath, encoding: .utf8),
              !configYaml.isEmpty else {
            completionHandler(TunnelError.noConfig)
            return
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
        let startResult = configYaml.withCString { ptr in
            StartCore(ptr)
        }
        guard startResult == 0 else {
            completionHandler(TunnelError.startFailed)
            return
        }

        completionHandler(nil)
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
