import Cocoa
import FlutterMacOS
import Network

@main
class AppDelegate: FlutterAppDelegate {
    private var vpnChannel: FlutterMethodChannel?
    private var pathMonitor: NWPathMonitor?
    private let pathMonitorQueue = DispatchQueue(label: "YueLinkPathMonitor")
    private var lastTransport: String?

    override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Return false so the app stays alive in the tray when the window is hidden.
        // window_manager's setPreventClose(true) intercepts close events, but if the
        // NSWindow is ever destroyed by the system, returning true would kill the process.
        return false
    }

    override func applicationWillTerminate(_ notification: Notification) {
        // Native safety net for paths that don't reach the Dart quit handler:
        // macOS shutdown/logout, force-quit via Activity Monitor, Cmd+Q when
        // the Dart side has already torn down, and `kill` outside SIGTERM
        // reach. shell() is synchronous (waitUntilExit), so the OS gives us
        // the full clear before killing the process. Idempotent — no-op if
        // proxy already off.
        clearSystemProxy()
    }

    override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    override func applicationDidFinishLaunching(_ notification: Notification) {
        guard let controller = mainFlutterWindow?.contentViewController as? FlutterViewController else { return }
        let channel = FlutterMethodChannel(name: "com.yueto.yuelink/vpn", binaryMessenger: controller.engine.binaryMessenger)
        vpnChannel = channel
        startPathMonitor()

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

    private func startPathMonitor() {
        if pathMonitor != nil { return }
        let monitor = NWPathMonitor()
        pathMonitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            let now = self.transportLabel(for: path)
            let prev = self.lastTransport
            self.lastTransport = now
            guard let prev = prev, prev != now else { return }
            DispatchQueue.main.async { [weak self] in
                self?.vpnChannel?.invokeMethod(
                    "transportChanged",
                    arguments: ["prev": prev, "now": now]
                )
            }
        }
        monitor.start(queue: pathMonitorQueue)
    }

    private func transportLabel(for path: NWPath) -> String {
        guard path.status == .satisfied else { return "none" }
        if path.usesInterfaceType(.wifi) { return "wifi" }
        if path.usesInterfaceType(.wiredEthernet) { return "ethernet" }
        if path.usesInterfaceType(.cellular) { return "cellular" }
        return "other"
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
