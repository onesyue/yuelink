import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/core/kernel/core_manager.dart';

void main() {
  group('isProxiesPayloadReady', () {
    test('null payload is not ready', () {
      expect(isProxiesPayloadReady(null), isFalse);
    });

    test('missing proxies key is not ready', () {
      expect(isProxiesPayloadReady({}), isFalse);
      expect(isProxiesPayloadReady({'something': 'else'}), isFalse);
    });

    test('proxies set to non-Map is not ready', () {
      expect(isProxiesPayloadReady({'proxies': 'not a map'}), isFalse);
      expect(isProxiesPayloadReady({'proxies': [1, 2, 3]}), isFalse);
    });

    test('empty proxies map is not ready (the early-init window)', () {
      // This is the exact window the v1.0.21 fix missed: /version answers
      // 200, /proxies returns {} for ~100-500ms while the config is being
      // parsed. waitApi alone would let testGroupDelay land here.
      expect(isProxiesPayloadReady({'proxies': {}}), isFalse);
    });

    test('synthetic GLOBAL group with populated all → ready', () {
      // mihomo always materialises the GLOBAL group last in graph build,
      // so a non-empty `all` here is the strongest "graph done" signal.
      expect(
        isProxiesPayloadReady({
          'proxies': {
            'GLOBAL': {'all': ['DIRECT', 'REJECT']},
          },
        }),
        isTrue,
      );
    });

    test('GLOBAL with empty all is NOT ready (early-build window)', () {
      // mihomo briefly emits GLOBAL with an empty `all` while the
      // selector graph is still being populated. The original
      // existence-only check let this through and produced the exact
      // false-positive we are guarding against.
      expect(
        isProxiesPayloadReady({
          'proxies': {
            'GLOBAL': {'all': <String>[]},
          },
        }),
        isFalse,
      );
    });

    test('GLOBAL missing all key is NOT ready', () {
      // Same reasoning — "GLOBAL exists but unpopulated" is not the
      // signal we want to act on.
      expect(
        isProxiesPayloadReady({
          'proxies': {
            'GLOBAL': <String, dynamic>{},
          },
        }),
        isFalse,
      );
    });

    test('GLOBAL empty but other group populated → ready (fallback path)', () {
      // Configs that strip GLOBAL entirely or build it sparsely are
      // valid; the secondary signal kicks in via the loop over
      // non-GLOBAL entries.
      expect(
        isProxiesPayloadReady({
          'proxies': {
            'GLOBAL': {'all': <String>[]},
            '🚀 Proxy': {'all': ['HK-1', 'JP-2'], 'now': 'HK-1'},
          },
        }),
        isTrue,
      );
    });

    test('selector group with non-empty all → ready (no GLOBAL needed)', () {
      // Some custom configs strip GLOBAL — fall back to "any group with
      // a populated `all` list" as the readiness signal.
      expect(
        isProxiesPayloadReady({
          'proxies': {
            '🚀 Proxy': {'all': ['HK-1', 'JP-2'], 'now': 'HK-1'},
          },
        }),
        isTrue,
      );
    });

    test('only inline single-node entries (no group) is not ready', () {
      // /proxies during early init can list standalone proxies without
      // the selector groups being built yet. Without an `all` list we
      // can't run testGroupDelay against anything meaningful.
      expect(
        isProxiesPayloadReady({
          'proxies': {
            'DIRECT': {'type': 'Direct'},
            'REJECT': {'type': 'Reject'},
          },
        }),
        isFalse,
      );
    });

    test('group with empty all list is not ready', () {
      expect(
        isProxiesPayloadReady({
          'proxies': {
            '🚀 Proxy': {'all': <String>[], 'now': null},
          },
        }),
        isFalse,
      );
    });

    test('group with `all` of wrong type is not ready', () {
      // Defensive: if mihomo ever returns `all: null` or a non-list during
      // a malformed parse, we don't blow up — we keep waiting.
      expect(
        isProxiesPayloadReady({
          'proxies': {
            '🚀 Proxy': {'all': 'not a list'},
          },
        }),
        isFalse,
      );
    });
  });
}
