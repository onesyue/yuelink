import 'dart:async';
import 'dart:io';

import 'app_notifier.dart';
import '../l10n/app_strings.dart';

/// Guard 模式：当内核运行且系统代理已设置时，定期检查系统代理是否仍然激活。
/// 若被外部（系统更新、网络切换等）禁用，则自动恢复并弹出提示。
class GuardService {
  static final GuardService instance = GuardService._();
  GuardService._();

  Timer? _timer;
  int _port = 0;

  void start(int mixedPort) {
    _port = mixedPort;
    _timer?.cancel();
    // 延迟 5s 再开始首次检查，避免刚设置代理就检测
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _check());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _port = 0;
  }

  Future<void> _check() async {
    if (_port == 0) return;
    if (Platform.isMacOS) {
      await _checkMacOS();
    } else if (Platform.isWindows) {
      await _checkWindows();
    }
  }

  // ── macOS ──────────────────────────────────────────────────────────────

  Future<void> _checkMacOS() async {
    try {
      final services = await _listNetworkServices();
      for (final svc in services) {
        final result =
            await Process.run('networksetup', ['-getwebproxy', svc]);
        final out = result.stdout as String;
        if (out.contains('Enabled: No') || out.contains('Enabled: 0')) {
          await _restoreMacOS(services);
          AppNotifier.warning(S.current.guardProxyRestored);
          return;
        }
      }
    } catch (_) {}
  }

  Future<void> _restoreMacOS(List<String> services) async {
    for (final svc in services) {
      try {
        await Process.run(
            'networksetup', ['-setwebproxy', svc, '127.0.0.1', '$_port']);
        await Process.run('networksetup',
            ['-setsecurewebproxy', svc, '127.0.0.1', '$_port']);
        await Process.run('networksetup',
            ['-setsocksfirewallproxy', svc, '127.0.0.1', '$_port']);
      } catch (_) {}
    }
  }

  // ── Windows ─────────────────────────────────────────────────────────────

  Future<void> _checkWindows() async {
    try {
      final result = await Process.run('reg', [
        'query',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
        '/v',
        'ProxyEnable',
      ]);
      final out = result.stdout as String;
      // When disabled, value shows 0x0
      if (out.contains('0x0')) {
        await _restoreWindows();
        AppNotifier.warning(S.current.guardProxyRestored);
      }
    } catch (_) {}
  }

  Future<void> _restoreWindows() async {
    try {
      await Process.run('reg', [
        'add',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
        '/v', 'ProxyEnable', '/t', 'REG_DWORD', '/d', '1', '/f',
      ]);
      await Process.run('reg', [
        'add',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
        '/v', 'ProxyServer', '/t', 'REG_SZ',
        '/d', '127.0.0.1:$_port', '/f',
      ]);
    } catch (_) {}
  }

  // ── Shared helpers ───────────────────────────────────────────────────────

  static Future<List<String>> _listNetworkServices() async {
    try {
      final result =
          await Process.run('networksetup', ['-listallnetworkservices']);
      return (result.stdout as String)
          .split('\n')
          .skip(1)
          .map((l) => l.startsWith('*') ? l.substring(1).trim() : l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
    } catch (_) {
      return ['Wi-Fi'];
    }
  }
}
