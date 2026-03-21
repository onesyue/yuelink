import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Simple network connectivity state.
enum ConnectivityStatus { online, offline, checking }

/// Periodically checks network connectivity by attempting a DNS lookup.
/// Avoids external package dependency — works cross-platform with dart:io.
final connectivityProvider =
    NotifierProvider<ConnectivityNotifier, ConnectivityStatus>(
  ConnectivityNotifier.new,
);

class ConnectivityNotifier extends Notifier<ConnectivityStatus> {
  Timer? _timer;
  bool _disposed = false;

  @override
  ConnectivityStatus build() {
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      _timer?.cancel();
    });
    // Start periodic check
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _check());
    // Initial check
    _check();
    return ConnectivityStatus.checking;
  }

  Future<void> _check() async {
    try {
      final result = await InternetAddress.lookup('dns.google')
          .timeout(const Duration(seconds: 5));
      if (_disposed) return;
      state = result.isNotEmpty && result[0].rawAddress.isNotEmpty
          ? ConnectivityStatus.online
          : ConnectivityStatus.offline;
    } catch (e) {
      if (_disposed) return;
      debugPrint('[Connectivity] check failed: $e');
      state = ConnectivityStatus.offline;
    }
  }

  /// Force an immediate re-check.
  void recheck() => _check();
}
