import Flutter
import UIKit
import NetworkExtension

@main
@objc class AppDelegate: FlutterAppDelegate {
    private let appGroup = "group.com.yueto.yuelink"
    private var vpnManager: NETunnelProviderManager?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)

        let controller = window?.rootViewController as! FlutterViewController
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
            if let error = error {
                result(FlutterError(code: "VPN_LOAD_ERROR",
                                    message: error.localizedDescription, details: nil))
                return
            }

            let manager = managers?.first ?? NETunnelProviderManager()
            self?.vpnManager = manager

            let proto = NETunnelProviderProtocol()
            proto.providerBundleIdentifier = "com.yueto.yuelink.PacketTunnel"
            proto.serverAddress = "YueLink"
            proto.disconnectOnSleep = false

            manager.protocolConfiguration = proto
            manager.localizedDescription = "YueLink"
            manager.isEnabled = true

            manager.saveToPreferences { error in
                if let error = error {
                    result(FlutterError(code: "VPN_SAVE_ERROR",
                                        message: error.localizedDescription, details: nil))
                    return
                }

                manager.loadFromPreferences { error in
                    if let error = error {
                        result(FlutterError(code: "VPN_RELOAD_ERROR",
                                            message: error.localizedDescription, details: nil))
                        return
                    }

                    do {
                        let session = manager.connection as! NETunnelProviderSession
                        try session.startTunnel()
                        result(true)
                    } catch {
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
                managers?.first?.connection.stopVPNTunnel()
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
