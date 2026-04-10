import Cocoa
import FlutterMacOS
import Security

@main
class AppDelegate: FlutterAppDelegate {
    override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Return false so the app stays alive in the tray when the window is hidden.
        // window_manager's setPreventClose(true) intercepts close events, but if the
        // NSWindow is ever destroyed by the system, returning true would kill the process.
        return false
    }

    override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    override func applicationDidFinishLaunching(_ notification: Notification) {
        guard let controller = mainFlutterWindow?.contentViewController as? FlutterViewController else { return }
        let channel = FlutterMethodChannel(name: "com.yueto.yuelink/vpn", binaryMessenger: controller.engine.binaryMessenger)

        // Keychain channel — stores secrets in macOS login keychain.
        // Does NOT require keychain-access-groups entitlement (single-app use).
        let keychainChannel = FlutterMethodChannel(
            name: "com.yueto.yuelink/keychain",
            binaryMessenger: controller.engine.binaryMessenger
        )
        keychainChannel.setMethodCallHandler { call, result in
            guard let args = call.arguments as? [String: String],
                  let key = args["key"] else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing 'key'", details: nil))
                return
            }
            switch call.method {
            case "read":
                result(self.keychainRead(key: key))
            case "write":
                guard let value = args["value"] else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Missing 'value'", details: nil))
                    return
                }
                let ok = self.keychainWrite(key: key, value: value)
                result(ok ? nil : FlutterError(code: "WRITE_FAILED", message: "Keychain write failed", details: nil))
            case "delete":
                self.keychainDelete(key: key)
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }

        channel.setMethodCallHandler { call, result in
            switch call.method {
            case "startVpn":
                // macOS: use system proxy mode as default
                result(true)
            case "stopVpn":
                self.clearSystemProxy()
                result(true)
            case "setSystemProxy":
                if let args = call.arguments as? [String: Any],
                   let host = args["host"] as? String,
                   let httpPort = args["httpPort"] as? Int,
                   let socksPort = args["socksPort"] as? Int {
                    self.setSystemProxy(host: host, httpPort: httpPort, socksPort: socksPort)
                    result(true)
                } else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Missing proxy arguments", details: nil))
                }
            case "clearSystemProxy":
                self.clearSystemProxy()
                result(true)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    private func setSystemProxy(host: String, httpPort: Int, socksPort: Int) {
        let services = getNetworkServices()
        for service in services {
            // Set HTTP proxy
            shell("networksetup -setwebproxy \"\(service)\" \(host) \(httpPort)")
            shell("networksetup -setsecurewebproxy \"\(service)\" \(host) \(httpPort)")
            shell("networksetup -setwebproxystate \"\(service)\" on")
            shell("networksetup -setsecurewebproxystate \"\(service)\" on")
            // Set SOCKS proxy
            shell("networksetup -setsocksfirewallproxy \"\(service)\" \(host) \(socksPort)")
            shell("networksetup -setsocksfirewallproxystate \"\(service)\" on")
        }
    }

    private func clearSystemProxy() {
        let services = getNetworkServices()
        for service in services {
            shell("networksetup -setwebproxystate \"\(service)\" off")
            shell("networksetup -setsecurewebproxystate \"\(service)\" off")
            shell("networksetup -setsocksfirewallproxystate \"\(service)\" off")
        }
    }

    private func getNetworkServices() -> [String] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        task.arguments = ["-listallnetworkservices"]
        let pipe = Pipe()
        task.standardOutput = pipe
        try? task.run()
        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return output
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty && !$0.contains("*") } // Skip disabled and header
            .dropFirst() // Skip "An asterisk..." header line
            .map { $0 }
    }

    // ── Keychain helpers ──────────────────────────────────────────────────

    private static let keychainService = "com.yueto.yuelink"

    private func keychainRead(key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: AppDelegate.keychainService,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status != errSecSuccess && status != errSecItemNotFound {
            NSLog("[Keychain] read '%@' failed: OSStatus %d", key, status)
        }
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func keychainWrite(key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        // Delete first to avoid errSecDuplicateItem
        keychainDelete(key: key)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: AppDelegate.keychainService,
            kSecAttrAccount: key,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlocked,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            NSLog("[Keychain] write '%@' failed: OSStatus %d", key, status)
        }
        return status == errSecSuccess
    }

    private func keychainDelete(key: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: AppDelegate.keychainService,
            kSecAttrAccount: key,
        ]
        SecItemDelete(query as CFDictionary)
    }

    @discardableResult
    private func shell(_ command: String) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", command]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        try? task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
