import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/settings_service.dart';

/// Split tunneling mode for Android VPN.
enum SplitTunnelMode {
  /// All apps go through the VPN (default).
  all,
  /// Only listed apps use the VPN (whitelist).
  whitelist,
  /// Listed apps bypass the VPN (blacklist).
  blacklist,
}

/// Installed app info returned from native side.
class AppInfo {
  final String packageName;
  final String appName;

  const AppInfo({required this.packageName, required this.appName});
}

// ── Providers ─────────────────────────────────────────────────────────────────

final splitTunnelModeProvider =
    NotifierProvider<SplitTunnelModeNotifier, SplitTunnelMode>(
  SplitTunnelModeNotifier.new,
);

class SplitTunnelModeNotifier extends Notifier<SplitTunnelMode> {
  @override
  SplitTunnelMode build() {
    _load();
    return SplitTunnelMode.all;
  }

  Future<void> _load() async {
    if (!Platform.isAndroid) return;
    final saved = await SettingsService.getSplitTunnelMode();
    state = SplitTunnelMode.values.firstWhere(
      (m) => m.name == saved,
      orElse: () => SplitTunnelMode.all,
    );
  }

  Future<void> set(SplitTunnelMode mode) async {
    state = mode;
    await SettingsService.setSplitTunnelMode(mode.name);
  }
}

/// The list of package names in the split tunnel list (whitelist or blacklist).
final splitTunnelAppsProvider =
    NotifierProvider<SplitTunnelAppsNotifier, List<String>>(
  SplitTunnelAppsNotifier.new,
);

class SplitTunnelAppsNotifier extends Notifier<List<String>> {
  @override
  List<String> build() {
    _load();
    return [];
  }

  Future<void> _load() async {
    if (!Platform.isAndroid) return;
    state = await SettingsService.getSplitTunnelApps();
  }

  Future<void> add(String packageName) async {
    if (state.contains(packageName)) return;
    state = [...state, packageName];
    await SettingsService.setSplitTunnelApps(state);
  }

  Future<void> remove(String packageName) async {
    state = state.where((p) => p != packageName).toList();
    await SettingsService.setSplitTunnelApps(state);
  }

  Future<void> toggle(String packageName) async {
    if (state.contains(packageName)) {
      await remove(packageName);
    } else {
      await add(packageName);
    }
  }
}
