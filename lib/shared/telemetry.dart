import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/storage/settings_service.dart';

/// Canonical event names. Using constants instead of free strings so typos
/// surface at compile time and dashboards don't fragment across rename drift.
class TelemetryEvents {
  TelemetryEvents._();

  // Lifecycle
  static const sessionStart = 'session_start';
  static const appResumed = 'app_resumed';
  static const appBackgrounded = 'app_backgrounded';

  // Startup (core.dart 8-step pipeline)
  static const startupOk = 'startup_ok';
  static const startupFail = 'startup_fail';

  // Connection
  static const connectStart = 'connect_start';
  static const connectOk = 'connect_ok';
  static const connectFailed = 'connect_failed';

  // Auth
  static const loginSuccess = 'login_success';
  static const loginFailed = 'login_failed';
  static const logout = 'logout';

  // Subscription / profiles
  static const subscriptionSync = 'subscription_sync';
  static const profileSwitch = 'profile_switch';
  static const profileDelete = 'profile_delete';
  static const qrScanSuccess = 'qr_scan_success';

  // User preferences
  static const themeChange = 'theme_change';
  static const routingModeChange = 'routing_mode_change';
  static const connectionModeChange = 'connection_mode_change';
  static const languageChange = 'language_change';

  // Feature usage
  static const nodeManualSelect = 'node_manual_select';
  static const checkinOk = 'checkin_ok';
  static const checkinFail = 'checkin_fail';
  static const embyOpen = 'emby_open';
  static const logExport = 'log_export';
  static const diagnosticExport = 'diagnostic_export';
  static const purchaseStart = 'purchase_start';
  static const purchaseSuccess = 'purchase_success';
  static const purchaseFail = 'purchase_fail';
  static const orderCancel = 'order_cancel';
  static const pendingOrderReuse = 'pending_order_reuse';

  // Onboarding (persona split — feature-flagged via `onboarding_split`)
  static const onboardingStart = 'onboarding_start';
  static const onboardingAnswer = 'onboarding_answer';
  static const onboardingFinish = 'onboarding_finish';

  // Delay test / core recovery
  static const delayTestAllTimeout = 'delay_test_all_timeout';
  static const delayTestAutoRecovered = 'delay_test_auto_recovered';
  static const coreRestarted = 'core_restarted';

  // Errors
  static const crash = 'crash';
  static const networkError = 'network_error';

  // Relay scheduler (Phase 1B). Field schemas live in
  // `lib/core/relay/relay_telemetry.dart` — every emitter must build
  // props through the helpers there so the closed-set field contract
  // is enforced in one place.
  static const relayProbe = 'relay_probe';
  static const relaySelected = 'relay_selected';
  static const relayFallback = 'relay_fallback';
  static const networkProfileSample = 'network_profile_sample';
}

/// Anonymous, opt-in telemetry for understanding feature usage.
///
/// Privacy model:
/// - No PII: no email, token, subscription URL, node server, or config.
/// - Events carry only: `client_id` (random UUID generated on first launch,
///   stored locally, never tied to a user identifier), `session_id` (per
///   launch), platform, version, event name, timestamp, and a small
///   bounded prop bag.
/// - The `client_id` can be reset any time by clearing storage; the user
///   can also view the last N events they've sent in Settings →
///   Telemetry → View sent events.
///
/// Delivery:
/// - Events are batched in-memory, flushed every 60 s, on app pause, or
///   when the buffer reaches [_softMaxBuffer].
/// - Error/crash events go to a priority buffer and survive overflow
///   pruning — we care about errors more than themechanges.
class Telemetry {
  Telemetry._();

  static const _endpoint = 'https://yue.yuebao.website/api/client/telemetry';
  static const _flushInterval = Duration(seconds: 60);
  static const _httpTimeout = Duration(seconds: 10);

  // Bounded buffers. When we exceed the soft cap we flush opportunistically;
  // when we exceed the hard cap we drop the oldest non-priority event.
  static const _softMaxBuffer = 50;
  static const _hardMaxBuffer = 200;

  // In-memory ring of recent events (for the Settings transparency view).
  // Does not participate in delivery — it's purely for the user.
  static const _recentRingSize = 50;

  static final List<Map<String, dynamic>> _buffer = [];
  static final List<Map<String, dynamic>> _priorityBuffer = [];
  static final List<Map<String, dynamic>> _recentRing = [];
  static Timer? _flushTimer;

  static bool _enabled = false;
  static String _platform = '';
  static String _version = '';
  static String _clientId = '';
  static String _sessionId = '';
  static int _sessionSeq = 0;
  static int _droppedCount = 0;

  /// Call once at app startup.
  static Future<void> init() async {
    _enabled = await SettingsService.getTelemetryEnabled();
    _platform = _detectPlatform();
    _sessionId = _uuid();
    _clientId = await _loadOrCreateClientId();
    try {
      final info = await PackageInfo.fromPlatform();
      _version = info.version;
    } catch (_) {}
    if (_enabled) {
      _startTimer();
      event(TelemetryEvents.sessionStart);
    }
  }

  static void setEnabled(bool enabled) {
    final wasEnabled = _enabled;
    _enabled = enabled;
    SettingsService.setTelemetryEnabled(enabled);
    if (enabled) {
      _startTimer();
      if (!wasEnabled) event(TelemetryEvents.sessionStart);
    } else {
      _flushTimer?.cancel();
      _buffer.clear();
      _priorityBuffer.clear();
    }
  }

  static bool get isEnabled => _enabled;
  static String get clientId => _clientId;
  static String get sessionId => _sessionId;

  /// Record a standard event. Cheap — no I/O.
  ///
  /// Pass [priority] = true for errors / crashes; those survive buffer
  /// pruning and still get delivered when the app is shutting down.
  static void event(
    String name, {
    Map<String, dynamic>? props,
    bool priority = false,
  }) {
    if (!_enabled) return;

    final payload = <String, dynamic>{
      'event': name,
      'client_id': _clientId,
      'session_id': _sessionId,
      'seq': _sessionSeq++,
      'platform': _platform,
      'version': _version,
      'ts': DateTime.now().millisecondsSinceEpoch,
      if (props != null) ..._sanitizeProps(props),
    };

    (priority ? _priorityBuffer : _buffer).add(payload);

    // Add a shallow copy (without client_id) to the UI ring.
    final preview = Map<String, dynamic>.from(payload)..remove('client_id');
    _recentRing.add(preview);
    if (_recentRing.length > _recentRingSize) {
      _recentRing.removeAt(0);
    }

    // Enforce hard cap on the normal buffer. Priority buffer is small by
    // construction (crashes are rare) so we let it grow unbounded-ish.
    while (_buffer.length > _hardMaxBuffer) {
      _buffer.removeAt(0);
      _droppedCount++;
    }

    // Opportunistic early flush once we cross the soft cap.
    if (_buffer.length + _priorityBuffer.length >= _softMaxBuffer) {
      unawaited(flush());
    }
  }

  /// Convenience: record an exception's runtime type (no stack, no message).
  /// Pass [context] to identify the call-site group.
  static void recordException(Object error, {String context = ''}) {
    event(
      TelemetryEvents.crash,
      priority: true,
      props: {
        'type': error.runtimeType.toString(),
        if (context.isNotEmpty) 'ctx': context,
      },
    );
  }

  /// Read-only snapshot of the last N recorded events. Used by the Settings
  /// transparency UI so the user can see exactly what's been sent.
  static List<Map<String, dynamic>> recentEvents() =>
      List<Map<String, dynamic>>.unmodifiable(_recentRing);

  static void _startTimer() {
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(_flushInterval, (_) => flush());
  }

  /// Flush all buffered events to server. Fire-and-forget.
  static Future<void> flush() async {
    if (_buffer.isEmpty && _priorityBuffer.isEmpty) return;

    final events = <Map<String, dynamic>>[..._priorityBuffer, ..._buffer];
    _priorityBuffer.clear();
    _buffer.clear();

    if (_droppedCount > 0) {
      events.add({
        'event': 'buffer_dropped',
        'client_id': _clientId,
        'session_id': _sessionId,
        'platform': _platform,
        'version': _version,
        'ts': DateTime.now().millisecondsSinceEpoch,
        'count': _droppedCount,
      });
      _droppedCount = 0;
    }

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);
    try {
      final req = await client.postUrl(Uri.parse(_endpoint));
      req.headers.set('Content-Type', 'application/json');
      req.write(jsonEncode({'events': events}));
      await req.close().timeout(_httpTimeout);
    } catch (e) {
      debugPrint('[Telemetry] flush failed: $e');
      // Best-effort re-queue of priority events. Keep lossy for normal events
      // (would otherwise grow unbounded during prolonged offline windows).
      _priorityBuffer.insertAll(
        0,
        events.where(
          (e) =>
              e['event'] == TelemetryEvents.crash ||
              e['event'] == TelemetryEvents.startupFail,
        ),
      );
    } finally {
      client.close();
    }
  }

  // ── Internals ───────────────────────────────────────────────────────

  static String _detectPlatform() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  static Future<String> _loadOrCreateClientId() async {
    final existing = await SettingsService.getTelemetryClientId();
    if (existing != null && existing.isNotEmpty) return existing;
    final generated = _uuid();
    await SettingsService.setTelemetryClientId(generated);
    return generated;
  }

  /// RFC 4122 v4 UUID using Random.secure(). Avoids a dependency.
  static String _uuid() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    // Version 4
    bytes[6] = (bytes[6] & 0x0F) | 0x40;
    // Variant 10xxxxxx
    bytes[8] = (bytes[8] & 0x3F) | 0x80;
    String hex(int i) => bytes[i].toRadixString(16).padLeft(2, '0');
    final b = List<String>.generate(16, hex);
    return '${b[0]}${b[1]}${b[2]}${b[3]}-'
        '${b[4]}${b[5]}-'
        '${b[6]}${b[7]}-'
        '${b[8]}${b[9]}-'
        '${b[10]}${b[11]}${b[12]}${b[13]}${b[14]}${b[15]}';
  }

  /// Strip props to simple scalars and clamp strings. Allows one level of
  /// nesting (`List<Map<String, scalar>>` or `List<scalar>`) so the
  /// `node_inventory` event can ship its `nodes` array — which used to be
  /// silently dropped, leaving the server-side `node_identity.region`
  /// column NULL for every user. Caps list length at 500 entries and
  /// refuses recursion deeper than one level.
  static Map<String, dynamic> _sanitizeProps(Map<String, dynamic> input) {
    final out = <String, dynamic>{};
    input.forEach((k, v) {
      final s = _sanitizeValue(v, depth: 0);
      if (s != null) out[k] = s;
    });
    return out;
  }

  static const _maxListLen = 500;

  static dynamic _sanitizeValue(dynamic v, {required int depth}) {
    if (v == null) return null;
    if (v is num || v is bool) return v;
    if (v is String) {
      return v.length > 100 ? v.substring(0, 100) : v;
    }
    // One level of nesting only — enough for node_inventory.nodes but
    // rejects arbitrary object graphs that could blow up payload size.
    if (depth >= 1) return null;
    if (v is List) {
      final out = [];
      for (final item in v.take(_maxListLen)) {
        final s = _sanitizeValue(item, depth: depth + 1);
        if (s != null) out.add(s);
      }
      return out;
    }
    if (v is Map) {
      final out = <String, dynamic>{};
      v.forEach((k, vv) {
        if (k is! String) return;
        final s = _sanitizeValue(vv, depth: depth + 1);
        if (s != null) out[k] = s;
      });
      return out.isEmpty ? null : out;
    }
    return null;
  }
}
