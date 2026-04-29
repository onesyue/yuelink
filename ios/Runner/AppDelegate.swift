import Flutter
import UIKit
import NetworkExtension

@main
@objc class AppDelegate: FlutterAppDelegate {
    private let appGroup = "group.com.yueto.yuelink"
    private var vpnManager: NETunnelProviderManager?
    private var vpnStatusObserver: NSObjectProtocol?
    /// Persistent observer installed after a successful VPN connection.
    /// Fires vpnRevoked to Flutter when the tunnel drops unexpectedly.
    private var backgroundVpnObserver: NSObjectProtocol?
    /// Channel reference kept alive so we can send unsolicited messages (vpnRevoked).
    private var vpnChannel: FlutterMethodChannel?
    /// Timestamp when session.status reached `.connected`. Used by the
    /// background observer to detect "connected then immediately dropped" —
    /// the signature symptom of an iOS PacketTunnel that the system started
    /// but isn't actually trusted (TrollStore / unsigned IPA / missing
    /// provisioning profile chain).
    private var lastConnectedAt: Date?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)

        guard let controller = window?.rootViewController as? FlutterViewController else {
            return super.application(application, didFinishLaunchingWithOptions: launchOptions)
        }
        let channel = FlutterMethodChannel(
            name: "com.yueto.yuelink/vpn",
            binaryMessenger: controller.binaryMessenger
        )
        vpnChannel = channel

        channel.setMethodCallHandler { [weak self] call, result in
            switch call.method {
            case "startVpn":
                let configYaml = call.arguments as? String
                self?.startVpn(configYaml: configYaml, result: result)
            case "stopVpn":
                self?.stopVpn(result: result)
            case "requestPermission":
                // iOS shows the system VPN prompt automatically on first startVpn
                result(true)
            case "resetVpnProfile":
                self?.resetVpnProfile(result: result)
            case "clearAppGroupConfig":
                self?.clearAppGroupConfig(result: result)
            default:
                result(FlutterMethodNotImplemented)
            }
        }

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // MARK: - VPN control

    private func startVpn(configYaml: String?, result: @escaping FlutterResult) {
        // Write config to App Group so PacketTunnel extension can read it
        if let yaml = configYaml {
            writeConfigToAppGroup(yaml)
        }

        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            guard let self = self else { return }

            if let error = error {
                // loadAllFromPreferences can fail on first install, after re-sign
                // (TrollStore/AltStore), or when VPN profile was removed from
                // Settings. Fall through and create a fresh manager instead of
                // treating this as fatal — saveToPreferences will establish the
                // profile.
                NSLog("[VPN] loadAllFromPreferences error (non-fatal): %@", error.localizedDescription)
            }

            let manager = managers?.first ?? NETunnelProviderManager()
            self.vpnManager = manager

            let proto = NETunnelProviderProtocol()
            proto.providerBundleIdentifier = "com.yueto.yuelink.PacketTunnel"
            proto.serverAddress = "YueLink"
            proto.disconnectOnSleep = false

            manager.protocolConfiguration = proto
            manager.localizedDescription = "YueLink"
            manager.isEnabled = true

            manager.saveToPreferences { [weak self] error in
                guard let self = self else { return }
                if let error = error {
                    result(FlutterError(code: "VPN_SAVE_ERROR",
                                        message: error.localizedDescription, details: nil))
                    return
                }

                manager.loadFromPreferences { [weak self] error in
                    guard let self = self else { return }
                    if let error = error {
                        result(FlutterError(code: "VPN_RELOAD_ERROR",
                                            message: error.localizedDescription, details: nil))
                        return
                    }

                    guard let session = manager.connection as? NETunnelProviderSession else {
                        result(FlutterError(code: "VPN_CAST_ERROR",
                                            message: "Failed to get tunnel session", details: nil))
                        return
                    }

                    // Remove any stale observer from a previous attempt
                    if let old = self.vpnStatusObserver {
                        NotificationCenter.default.removeObserver(old)
                        self.vpnStatusObserver = nil
                    }

                    // Guard against result() being called more than once
                    var done = false

                    // Timeout: if the tunnel does not connect within 20 seconds,
                    // report an error. The PacketTunnel extension startup can be
                    // slow on first launch (Go core init + provisioning prompt).
                    let timeoutWork = DispatchWorkItem { [weak self] in
                        guard !done else { return }
                        done = true
                        if let obs = self?.vpnStatusObserver {
                            NotificationCenter.default.removeObserver(obs)
                            self?.vpnStatusObserver = nil
                        }
                        result(FlutterError(
                            code: "VPN_TIMEOUT_ERROR",
                            message: "VPN tunnel did not connect within 20 seconds",
                            details: nil
                        ))
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: timeoutWork)

                    // Watch for status changes; resolve the Flutter result once
                    // we reach a terminal state (.connected or .disconnected).
                    self.vpnStatusObserver = NotificationCenter.default.addObserver(
                        forName: .NEVPNStatusDidChange,
                        object: session,
                        queue: .main
                    ) { [weak self] _ in
                        guard !done else { return }
                        let status = session.status
                        switch status {
                        case .connected:
                            done = true
                            timeoutWork.cancel()
                            if let obs = self?.vpnStatusObserver {
                                NotificationCenter.default.removeObserver(obs)
                                self?.vpnStatusObserver = nil
                            }
                            self?.lastConnectedAt = Date()
                            self?.startBackgroundVpnObserver(session: session)
                            result(true)
                        case .disconnected, .invalid:
                            done = true
                            timeoutWork.cancel()
                            if let obs = self?.vpnStatusObserver {
                                NotificationCenter.default.removeObserver(obs)
                                self?.vpnStatusObserver = nil
                            }
                            result(FlutterError(
                                code: "VPN_CONNECT_ERROR",
                                message: "VPN tunnel disconnected unexpectedly (status=\(status.rawValue))",
                                details: nil
                            ))
                        default:
                            break // .connecting / .reasserting — keep waiting
                        }
                    }

                    // configurationStale is iOS's "you saved but I haven't
                    // synced yet" response. Documented workaround (used by
                    // sing-box-for-apple, Streisand, Karing): reload the
                    // preferences, then retry startTunnel once after a
                    // short beat. Without this, users see "first connect
                    // fails, second connect works" right after granting
                    // the Settings pane prompt — the iOS analogue of the
                    // Windows SCM "install OK but listener not bound" race.
                    func finishWithError(_ error: Error) {
                        done = true
                        timeoutWork.cancel()
                        if let obs = self.vpnStatusObserver {
                            NotificationCenter.default.removeObserver(obs)
                            self.vpnStatusObserver = nil
                        }
                        result(FlutterError(code: "VPN_START_ERROR",
                                            message: error.localizedDescription, details: nil))
                    }

                    do {
                        try session.startTunnel()
                    } catch let nsError as NSError where
                            nsError.domain == NEVPNErrorDomain &&
                            nsError.code == NEVPNError.Code.configurationStale.rawValue {
                        NSLog("[VPN] configurationStale on first startTunnel — reloading + retrying once")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            manager.loadFromPreferences { _ in
                                do {
                                    try session.startTunnel()
                                } catch {
                                    finishWithError(error)
                                }
                            }
                        }
                    } catch {
                        finishWithError(error)
                    }
                }
            }
        }
    }

    /// Install a persistent observer that fires `vpnRevoked` to Flutter when
    /// the tunnel drops unexpectedly (killed by system, permission revoked, etc.).
    /// Safe to call multiple times — removes the previous observer first.
    private func startBackgroundVpnObserver(session: NETunnelProviderSession) {
        if let old = backgroundVpnObserver {
            NotificationCenter.default.removeObserver(old)
            backgroundVpnObserver = nil
        }
        backgroundVpnObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: session,
            queue: .main
        ) { [weak self] _ in
            let status = session.status
            guard status == .disconnected || status == .invalid else { return }

            // Distinguish "tunnel held connected for a while then dropped"
            // (legitimate revoke / network change) from "tunnel reached
            // .connected then immediately collapsed" — the latter is the
            // signature of an iOS PacketTunnel extension that the system
            // started but isn't fully trusted. Most common cause: TrollStore
            // installed IPA without a valid provisioning profile chain, or a
            // re-signed IPA whose entitlements aren't honored.
            //
            // < 10s window is generous: even a slow-but-working tunnel
            // typically holds far longer; legitimate "system killed it"
            // events on healthy installs almost never happen within seconds.
            var args: [String: Any] = [:]
            if let connectedAt = self?.lastConnectedAt {
                let elapsedMs = Int(Date().timeIntervalSince(connectedAt) * 1000)
                args["elapsed_ms"] = elapsedMs
                if elapsedMs < 10_000 {
                    args["reason"] = "entitlement_suspect"
                }
            }

            NSLog("[VPN] Unexpected disconnect (status=%d, args=%@) — notifying Flutter",
                  status.rawValue, args.description)
            if let obs = self?.backgroundVpnObserver {
                NotificationCenter.default.removeObserver(obs)
                self?.backgroundVpnObserver = nil
            }
            self?.lastConnectedAt = nil
            self?.vpnChannel?.invokeMethod(
                "vpnRevoked",
                arguments: args.isEmpty ? nil : args
            )
        }
    }

    private func stopVpn(result: @escaping FlutterResult) {
        // Remove background observer BEFORE stopping — prevents a false vpnRevoked
        // notification for the intentional disconnect we are about to trigger.
        if let obs = backgroundVpnObserver {
            NotificationCenter.default.removeObserver(obs)
            backgroundVpnObserver = nil
        }
        // 真实状态闭环：处理 App 被杀后台后 vpnManager 丢失的情况
        if let manager = vpnManager {
            manager.connection.stopVPNTunnel()
            result(true)
        } else {
            NETunnelProviderManager.loadAllFromPreferences { managers, error in
                if let manager = managers?.first {
                    manager.connection.stopVPNTunnel()
                }
                result(true)
            }
        }
    }

    // MARK: - Repair tools

    /// Remove all existing VPN profiles and reset state.
    /// Next startVpn call will create a fresh profile and trigger the system
    /// VPN permission prompt again.
    private func resetVpnProfile(result: @escaping FlutterResult) {
        // Clean up observers
        if let obs = backgroundVpnObserver {
            NotificationCenter.default.removeObserver(obs)
            backgroundVpnObserver = nil
        }
        if let obs = vpnStatusObserver {
            NotificationCenter.default.removeObserver(obs)
            vpnStatusObserver = nil
        }

        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            guard let managers = managers, !managers.isEmpty else {
                self?.vpnManager = nil
                result(true) // No profile to remove — already clean
                return
            }
            let group = DispatchGroup()
            for manager in managers {
                group.enter()
                manager.connection.stopVPNTunnel()
                manager.removeFromPreferences { _ in group.leave() }
            }
            group.notify(queue: .main) {
                self?.vpnManager = nil
                NSLog("[VPN] Reset: removed %d VPN profile(s)", managers.count)
                result(true)
            }
        }
    }

    /// Delete all config/geo files from the App Group container.
    /// Forces a fresh config write on next startVpn.
    private func clearAppGroupConfig(result: @escaping FlutterResult) {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroup
        ) else {
            result(false)
            return
        }
        let mihomoDir = containerURL.appendingPathComponent("mihomo")
        let fm = FileManager.default
        var removed = 0
        if let files = try? fm.contentsOfDirectory(atPath: mihomoDir.path) {
            for file in files {
                try? fm.removeItem(at: mihomoDir.appendingPathComponent(file))
                removed += 1
            }
        }
        NSLog("[VPN] Cleared %d files from App Group", removed)
        result(true)
    }

    // MARK: - App Group config sharing

    /// Write config YAML to the shared App Group container so the
    /// PacketTunnel extension can read it on startup.
    private func writeConfigToAppGroup(_ yaml: String) {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroup
        ) else { return }

        let mihomoDir = containerURL.appendingPathComponent("mihomo")
        try? FileManager.default.createDirectory(
            atPath: mihomoDir.path, withIntermediateDirectories: true
        )
        try? yaml.write(
            to: mihomoDir.appendingPathComponent("config.yaml"),
            atomically: true,
            encoding: .utf8
        )

        // Copy geo data files from main app's Application Support to the
        // App Group container so the PacketTunnel extension can use them.
        // Without these, GEOIP/GEOSITE rules fail on first launch.
        copyGeoFilesToAppGroup(mihomoDir)
    }

    /// Copy GeoIP/GeoSite files from the main app sandbox to the App Group
    /// mihomo directory. Only copies if the source is newer or dest is missing.
    private func copyGeoFilesToAppGroup(_ destDir: URL) {
        let geoFiles = ["GeoIP.dat", "GeoSite.dat", "country.mmdb", "ASN.mmdb"]
        guard let appSupportDir = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { return }

        let fm = FileManager.default
        for name in geoFiles {
            let src = appSupportDir.appendingPathComponent(name)
            let dst = destDir.appendingPathComponent(name)

            guard fm.fileExists(atPath: src.path) else { continue }

            // Skip if destination already exists and is same size or newer
            if fm.fileExists(atPath: dst.path) {
                let srcAttrs = try? fm.attributesOfItem(atPath: src.path)
                let dstAttrs = try? fm.attributesOfItem(atPath: dst.path)
                let srcSize = srcAttrs?[.size] as? Int ?? 0
                let dstSize = dstAttrs?[.size] as? Int ?? 0
                if dstSize >= srcSize && dstSize > 1024 { continue }
            }

            try? fm.removeItem(at: dst)
            try? fm.copyItem(at: src, to: dst)
            NSLog("[GeoData] Copied %@ to App Group (%d bytes)",
                  name, (try? fm.attributesOfItem(atPath: dst.path))?[.size] as? Int ?? 0)
        }
    }
}
