import 'dart:io';

import 'service_client.dart';
import 'service_models.dart';

/// Test seams for the four read-only `ServiceManager` methods (`isInstalled`,
/// `isReady`, `getInfo`, `waitUntilReachable`). Each interface is intentionally
/// narrow (≤5 methods) and covers exactly one external dependency these
/// methods touch.
///
/// **Out of scope.** `install` / `update` / `uninstall` and the platform-
/// specific install-script generators (`_macInstallScript`,
/// `_linuxInstallScript`, `_windowsInstallScript`) keep their direct calls
/// to `Process.run` / `File` / `osascript` / `pkexec` / etc. Refactoring
/// those would expand blast radius far beyond what these probes are for —
/// see CLAUDE.md "S2 scope" for rationale.

/// File-existence + read-text checks. Used by `isInstalled` (helper /
/// mihomo / plist / unit file probes) and by `_collectUnreachableDiagnostics`
/// (helper.log tail).
abstract class ServiceFileSystem {
  /// `File(path).existsSync()`. Sync because the call sites are inside
  /// per-platform branches that already gated on Platform.isXxx.
  bool exists(String path);

  /// Read the file at [path] as a UTF-8 string. Returns null when the file
  /// is absent OR when reading fails — callers treat both as "no signal".
  Future<String?> readString(String path);
}

/// Subprocess runner. The only call sites are the SCM/launchctl/systemctl
/// probes and `id -u` — all read-only. The install-script execution path
/// (`osascript`, `pkexec`, `Start-Process -Verb RunAs`) is NOT routed
/// through here and stays inside `ServiceManager` as direct `Process.run`
/// calls.
abstract class ServiceProcessRunner {
  /// `Process.run(executable, arguments)` with optional [timeout]. The
  /// timeout is honoured by wrapping the future in `.timeout(...)`; no
  /// signal is sent to the child process on timeout (matches the existing
  /// `_collectUnreachableDiagnostics` behaviour where stuck probes simply
  /// surface as `<probe_err=TimeoutException>` lines).
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    Duration? timeout,
  });
}

/// IPC client + version source for `getInfo` / `isReady` / `waitUntilReachable`.
/// `expectedVersion` lives here (rather than a separate "asset" probe)
/// because it pairs with `remoteVersion` for the version-mismatch check —
/// keeping them together avoids spreading version logic across two interfaces.
abstract class ServiceClientProbe {
  /// Cheap reachability ping. True when the helper's IPC listener answers
  /// within the client's own timeout (currently ~500 ms).
  Future<bool> ping();

  /// Full status snapshot (running, pid, paths, last-error, …). Throws
  /// when IPC is unreachable — callers in `getInfo` catch and surface
  /// `installed=true reachable=false`.
  Future<DesktopServiceInfo> status();

  /// Protocol version reported by the running helper. Null when the
  /// helper predates the version endpoint.
  Future<String?> remoteVersion();

  /// Protocol version this build expects. Comes from the bundled
  /// `service/protocol_version.txt` asset in production; tests inject a
  /// known value via the probe.
  Future<String> expectedVersion();
}

/// Read-only platform probe for `ServiceManager` state-combination tests.
/// Kept separate from install/update/uninstall script generation; production
/// delegates directly to `dart:io`'s [Platform].
abstract class ServicePlatformProbe {
  bool get isMacOS;
  bool get isWindows;
  bool get isLinux;
}

// ── Real implementations ─────────────────────────────────────────────────

class RealServiceFileSystem implements ServiceFileSystem {
  const RealServiceFileSystem();

  @override
  bool exists(String path) => File(path).existsSync();

  @override
  Future<String?> readString(String path) async {
    try {
      final f = File(path);
      if (!f.existsSync()) return null;
      return await f.readAsString();
    } catch (_) {
      return null;
    }
  }
}

class RealServiceProcessRunner implements ServiceProcessRunner {
  const RealServiceProcessRunner();

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    Duration? timeout,
  }) {
    final future = Process.run(executable, arguments);
    return timeout == null ? future : future.timeout(timeout);
  }
}

/// Default probe that delegates to the real `ServiceClient` static methods
/// for IPC and to `ServiceManager.expectedVersion()` for the bundled
/// version. Constructed via a callback so this file doesn't have to import
/// (or be imported by) `service_manager.dart` and create a circular dep.
class RealServiceClientProbe implements ServiceClientProbe {
  final Future<String> Function() _expectedVersionLoader;
  const RealServiceClientProbe(this._expectedVersionLoader);

  @override
  Future<bool> ping() => ServiceClient.ping();

  @override
  Future<DesktopServiceInfo> status() => ServiceClient.status();

  @override
  Future<String?> remoteVersion() => ServiceClient.version();

  @override
  Future<String> expectedVersion() => _expectedVersionLoader();
}

class RealServicePlatformProbe implements ServicePlatformProbe {
  const RealServicePlatformProbe();

  @override
  bool get isMacOS => Platform.isMacOS;

  @override
  bool get isWindows => Platform.isWindows;

  @override
  bool get isLinux => Platform.isLinux;
}
