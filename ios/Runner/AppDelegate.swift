import Flutter
import UIKit
import NetworkExtension

@main
@objc class AppDelegate: FlutterAppDelegate {
    private let appGroup = "group.com.yueto.yuelink"
    private var vpnManager: NETunnelProviderManager?
    private var vpnStatusObserver: NSObjectProtocol?

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
                result(FlutterError(code: "VPN_LOAD_ERROR",
                                    message: error.localizedDescription, details: nil))
                return
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

                    do {
                        try session.startTunnel()
                    } catch {
                        done = true
                        timeoutWork.cancel()
                        if let obs = self.vpnStatusObserver {
                            NotificationCenter.default.removeObserver(obs)
                            self.vpnStatusObserver = nil
                        }
                        result(FlutterError(code: "VPN_START_ERROR",
                                            message: error.localizedDescription, details: nil))
                    }
                }
            }
        }
    }

    private func stopVpn(result: @escaping FlutterResult) {
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
    }
}
