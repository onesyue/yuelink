import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Snapshot of Android's system Private DNS setting.
///
/// Three meaningful modes (Android `Settings.Global.private_dns_mode`):
///
///   * `off`           — fully off, no influence on yuelink.
///   * `opportunistic` — Android opportunistically tries DoT to the
///                       network's advertised resolver. yuelink TUN's
///                       `dns-hijack` typically still wins because
///                       opportunistic DoT downgrades to plain DNS:53
///                       when blocked, and our hijack listens on 53.
///                       **Diagnostic only**, no banner.
///   * `hostname`      — user has explicitly pinned a DoT server
///                       (e.g. `1dot1dot1dot1.cloudflare-dns.com`).
///                       Android will route DoT directly, **bypassing
///                       yuelink TUN dns-hijack**. This is the only
///                       mode that warrants a Dashboard banner.
///
/// Plus a sentinel for non-Android / channel error / OEM ROMs that
/// reject reads of `private_dns_*` Settings.Global keys.
@immutable
class PrivateDnsState {
  final String mode;
  final String? specifier;

  const PrivateDnsState({required this.mode, this.specifier});

  /// Sentinel when Dart hasn't pulled state yet, or platform isn't
  /// Android, or the platform call failed. Treated as "no banner".
  factory PrivateDnsState.unknown() =>
      const PrivateDnsState(mode: 'unknown');

  /// `true` only for `hostname` mode, the only mode where Android
  /// actually bypasses TUN dns-hijack and breaks yuelink DNS routing.
  bool get bypassesTun => mode == 'hostname';

  @override
  bool operator ==(Object other) =>
      other is PrivateDnsState &&
      other.mode == mode &&
      other.specifier == specifier;

  @override
  int get hashCode => Object.hash(mode, specifier);

  @override
  String toString() => 'PrivateDnsState(mode=$mode, specifier=$specifier)';
}

/// Reads Android Private DNS state via MethodChannel `getPrivateDnsState`.
///
/// **Pull, not push.** Dart calls native on three triggers:
///   1. App launch (Notifier `build()` schedules a microtask refresh).
///   2. App resumed (caller in `main.dart` invokes `.refresh()`).
///   3. VPN connected (caller listens to `coreStatusProvider` running).
///
/// Push from native would need persistent state machine
/// (subscribe/unsubscribe/replay), pull is simpler and three triggers
/// already cover every user-visible transition. Failures are silent —
/// state stays at last-known (or unknown).
class PrivateDnsStateNotifier extends Notifier<PrivateDnsState> {
  static const _channel = MethodChannel('com.yueto.yuelink/vpn');

  @override
  PrivateDnsState build() {
    if (Platform.isAndroid) {
      // Schedule on next event-loop tick so build() stays synchronous.
      Future.microtask(refresh);
    }
    return PrivateDnsState.unknown();
  }

  /// Pull current state from native side. Cheap (one Settings.Global
  /// read), safe to call repeatedly. Idempotent — if mode hasn't
  /// changed Riverpod's `state` setter is a no-op.
  Future<void> refresh() async {
    if (!Platform.isAndroid) return;
    try {
      final raw = await _channel
          .invokeMethod<dynamic>('getPrivateDnsState')
          .timeout(const Duration(seconds: 2));
      if (raw is Map) {
        final mode = (raw['mode'] as String?) ?? 'unknown';
        final specifier = raw['specifier'] as String?;
        state = PrivateDnsState(mode: mode, specifier: specifier);
      }
    } on TimeoutException {
      debugPrint('[PrivateDnsState] refresh timed out — keeping prior state');
    } catch (e) {
      debugPrint('[PrivateDnsState] refresh error: $e');
    }
  }
}

final privateDnsStateProvider =
    NotifierProvider<PrivateDnsStateNotifier, PrivateDnsState>(
      PrivateDnsStateNotifier.new,
    );
