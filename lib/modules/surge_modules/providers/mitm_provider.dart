import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/ffi/core_controller.dart';
import '../../../domain/surge_modules/module_entity.dart';
import 'module_provider.dart';

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
  MitmNotifier(this._ref) : super(const MitmState()) {
    refresh();
  }

  final Ref _ref;
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

  /// Push the current enabled-module config to the MITM engine.
  /// Safe to call at any time; no-op when engine is not running.
  void pushConfig(List<ModuleRecord> modules) {
    if (!state.engine.running) return;
    final config = _buildConfigJson(modules);
    final err = _core.updateMitmConfig(config);
    if (err != null && err.isNotEmpty) {
      debugPrint('[MitmProvider] updateMitmConfig error: $err');
    }
  }

  /// Start the MITM engine, then immediately push the current module config.
  Future<void> startEngine() async {
    state = state.copyWith(isLoading: true, clearError: true);
    final err = _core.startMitmEngine();
    if (err != null && err.isNotEmpty) {
      state = state.copyWith(isLoading: false, error: err);
      return;
    }
    refresh();
    state = state.copyWith(isLoading: false);
    // Push Phase-2 config now that the engine is running.
    try {
      final modules = _ref.read(moduleProvider).modules;
      pushConfig(modules);
    } catch (e) {
      debugPrint('[MitmProvider] pushConfig after start error: $e');
    }
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

  /// Build a MITMConfig JSON string from a list of module records.
  /// JSON shape:
  ///   {"hostnames":[...],"url_rewrites":[...],"header_rewrites":[...],"scripts":[...]}
  static String _buildConfigJson(List<ModuleRecord> modules) {
    final hostnames = <String>{};
    final urlRewrites = <Map<String, dynamic>>[];
    final headerRewrites = <Map<String, dynamic>>[];
    final scripts = <Map<String, dynamic>>[];

    for (final m in modules) {
      if (!m.enabled) continue;
      for (final h in m.mitmHostnames) {
        if (h.trim().isNotEmpty) hostnames.add(h.trim());
      }
      for (final r in m.urlRewrites) {
        urlRewrites.add({
          'pattern': r.pattern,
          if (r.replacement != null) 'replacement': r.replacement,
          'action': r.rewriteType,
        });
      }
      for (final r in m.headerRewrites) {
        headerRewrites.add({
          'pattern': r.pattern,
          if (r.headerName != null) 'name': r.headerName,
          if (r.headerValue != null) 'value': r.headerValue,
          'action': _normaliseHeaderAction(r.headerAction),
        });
      }
      for (final s in m.scripts) {
        if (s.scriptType != 'http-response') continue;
        final code = s.scriptContent;
        if (code == null || code.isEmpty) continue;
        if (s.pattern == null || s.pattern!.isEmpty) continue;
        // Basic sanity: reject excessively large scripts (>512KB) to prevent
        // memory pressure in the Go MITM engine.
        if (code.length > 512 * 1024) continue;
        scripts.add({'pattern': s.pattern, 'code': code});
      }
    }

    return jsonEncode({
      'hostnames': hostnames.toList(),
      'url_rewrites': urlRewrites,
      'header_rewrites': headerRewrites,
      if (scripts.isNotEmpty) 'scripts': scripts,
    });
  }

  /// Normalise Surge header action names to Go's expected format.
  /// "header-add" → "add", "header-replace" → "replace", "header-del" → "del".
  /// "response-header-add" → "response-add", etc. (response-side rewrites).
  static String _normaliseHeaderAction(String action) {
    if (action.startsWith('response-header-')) {
      return 'response-${action.substring('response-header-'.length)}';
    }
    if (action.startsWith('header-')) return action.substring('header-'.length);
    return action;
  }

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
    StateNotifierProvider<MitmNotifier, MitmState>((ref) {
  final notifier = MitmNotifier(ref);

  // Auto-push Phase-2 config whenever the module list changes while running.
  ref.listen(moduleProvider, (_, next) {
    notifier.pushConfig(next.modules);
  });

  return notifier;
});

/// Derived: current MITM engine port (0 = not running).
final mitmEnginePortProvider = Provider<int>((ref) {
  final s = ref.watch(mitmProvider);
  return s.engine.running ? s.engine.port : 0;
});
