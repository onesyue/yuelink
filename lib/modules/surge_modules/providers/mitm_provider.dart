import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ffi/core_controller.dart';

// ── Data classes ──────────────────────────────────────────────────────────────

/// MITM engine runtime status (mirrors Go MitmEngineStatus JSON).
class MitmEngineStatus {
  final bool running;
  final int port;
  final String address;
  final bool healthy;
  final String lastError;

  const MitmEngineStatus({
    this.running = false,
    this.port = 9091,
    this.address = '',
    this.healthy = false,
    this.lastError = '',
  });

  factory MitmEngineStatus.fromJson(Map<String, dynamic> j) => MitmEngineStatus(
        running: j['running'] as bool? ?? false,
        port: (j['port'] as num?)?.toInt() ?? 9091,
        address: j['address'] as String? ?? '',
        healthy: j['healthy'] as bool? ?? false,
        lastError: j['last_error'] as String? ?? '',
      );

  static const empty = MitmEngineStatus();
}

/// Root CA certificate status (mirrors Go RootCAStatus JSON).
class RootCaStatus {
  final bool exists;
  final String fingerprint;
  final DateTime? createdAt;
  final DateTime? expiresAt;
  final String exportPath;

  const RootCaStatus({
    this.exists = false,
    this.fingerprint = '',
    this.createdAt,
    this.expiresAt,
    this.exportPath = '',
  });

  factory RootCaStatus.fromJson(Map<String, dynamic> j) => RootCaStatus(
        exists: j['exists'] as bool? ?? false,
        fingerprint: j['fingerprint'] as String? ?? '',
        createdAt: j['created_at'] != null
            ? DateTime.tryParse(j['created_at'] as String)
            : null,
        expiresAt: j['expires_at'] != null
            ? DateTime.tryParse(j['expires_at'] as String)
            : null,
        exportPath: j['export_path'] as String? ?? '',
      );

  static const empty = RootCaStatus();
}

// ── State ─────────────────────────────────────────────────────────────────────

class MitmState {
  final MitmEngineStatus engine;
  final RootCaStatus ca;
  final bool isLoading;
  final String? error;

  const MitmState({
    this.engine = MitmEngineStatus.empty,
    this.ca = RootCaStatus.empty,
    this.isLoading = false,
    this.error,
  });

  MitmState copyWith({
    MitmEngineStatus? engine,
    RootCaStatus? ca,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) =>
      MitmState(
        engine: engine ?? this.engine,
        ca: ca ?? this.ca,
        isLoading: isLoading ?? this.isLoading,
        error: clearError ? null : (error ?? this.error),
      );
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class MitmNotifier extends StateNotifier<MitmState> {
  MitmNotifier() : super(const MitmState()) {
    refresh();
  }

  final _core = CoreController.instance;

  /// Refresh engine + CA status from the Go core.
  void refresh() {
    try {
      final engine = _parseEngine(_core.getMitmEngineStatusJson());
      final ca = _parseCa(_core.getRootCaStatusJson());
      state = state.copyWith(engine: engine, ca: ca, clearError: true);
    } catch (e) {
      debugPrint('[MitmProvider] refresh error: $e');
    }
  }

  /// Start the MITM engine.
  Future<void> startEngine() async {
    state = state.copyWith(isLoading: true, clearError: true);
    final err = _core.startMitmEngine();
    if (err != null && err.isNotEmpty) {
      state = state.copyWith(isLoading: false, error: err);
      return;
    }
    refresh();
    state = state.copyWith(isLoading: false);
  }

  /// Stop the MITM engine.
  Future<void> stopEngine() async {
    state = state.copyWith(isLoading: true, clearError: true);
    final err = _core.stopMitmEngine();
    if (err != null && err.isNotEmpty) {
      state = state.copyWith(isLoading: false, error: err);
      return;
    }
    refresh();
    state = state.copyWith(isLoading: false);
  }

  /// Generate (or regenerate) the Root CA.
  Future<void> generateCa() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final json = _core.generateRootCaJson();
      final ca = _parseCa(json);
      if (!ca.exists) {
        state = state.copyWith(
            isLoading: false,
            error: 'CA generation failed — check logs');
        return;
      }
      state = state.copyWith(ca: ca, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  // ── helpers ──────────────────────────────────────────────────────────────

  static MitmEngineStatus _parseEngine(String jsonStr) {
    try {
      if (jsonStr.isEmpty || jsonStr == '{}') return MitmEngineStatus.empty;
      return MitmEngineStatus.fromJson(
          jsonDecode(jsonStr) as Map<String, dynamic>);
    } catch (_) {
      return MitmEngineStatus.empty;
    }
  }

  static RootCaStatus _parseCa(String jsonStr) {
    try {
      if (jsonStr.isEmpty || jsonStr == '{}') return RootCaStatus.empty;
      return RootCaStatus.fromJson(
          jsonDecode(jsonStr) as Map<String, dynamic>);
    } catch (_) {
      return RootCaStatus.empty;
    }
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

final mitmProvider =
    StateNotifierProvider<MitmNotifier, MitmState>((ref) => MitmNotifier());

/// Derived: current MITM engine port (0 = not running).
final mitmEnginePortProvider = Provider<int>((ref) {
  final s = ref.watch(mitmProvider);
  return s.engine.running ? s.engine.port : 0;
});
