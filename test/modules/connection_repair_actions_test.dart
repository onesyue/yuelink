import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/core/providers/core_provider.dart';
import 'package:yuelink/modules/settings/connection_repair/connection_repair_actions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Redirect path_provider to a clean tmp dir so SettingsService.get*
  // returns null on a fresh filesystem (no prior settings file).
  late Directory pathProviderDir;
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  setUpAll(() {
    pathProviderDir = Directory.systemTemp.createTempSync(
      'yl_repair_actions_path_',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
          if (call.method == 'getApplicationSupportDirectory') {
            return pathProviderDir.path;
          }
          return null;
        });
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    if (pathProviderDir.existsSync()) {
      pathProviderDir.deleteSync(recursive: true);
    }
  });

  group('ConnectionRepairActions.clearLocalCache', () {
    late Directory tmp;
    late ProviderContainer container;
    late ConnectionRepairActions actions;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('yl_cache_clear_');
      container = ProviderContainer();
      actions = container.read(connectionRepairActionsProvider);
    });

    tearDown(() {
      container.dispose();
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test(
      'deletes only the target file set, leaves other files alone',
      () async {
        final coreLog = File('${tmp.path}/core.log')..writeAsStringSync('a');
        final crashLog = File('${tmp.path}/crash.log')..writeAsStringSync('b');
        final eventLog = File('${tmp.path}/event.log')..writeAsStringSync('c');
        final configYaml = File('${tmp.path}/config.yaml')
          ..writeAsStringSync('d');
        final startupReport = File('${tmp.path}/startup_report.json')
          ..writeAsStringSync('e');
        // Files outside the target set must survive.
        final unrelated = File('${tmp.path}/keep_me.txt')
          ..writeAsStringSync('keep');
        final rotated = File('${tmp.path}/core.log.1')
          ..writeAsStringSync('rotated');

        await actions.clearLocalCache(tmp);

        expect(coreLog.existsSync(), isFalse);
        expect(crashLog.existsSync(), isFalse);
        expect(eventLog.existsSync(), isFalse);
        expect(configYaml.existsSync(), isFalse);
        expect(startupReport.existsSync(), isFalse);
        expect(unrelated.existsSync(), isTrue);
        // Rotated sidecars are NOT in the clear-cache target list — that's
        // by design (they'd already be log-export-only artifacts), but it's
        // also a regression line in case anyone widens the target set.
        expect(rotated.existsSync(), isTrue);
      },
    );

    test('idempotent: no-op when none of the targets exist', () async {
      // Tmp dir is empty. The call must not throw.
      await actions.clearLocalCache(tmp);

      expect(tmp.existsSync(), isTrue);
      expect(tmp.listSync(), isEmpty);
    });

    test('partial: deletes only the targets that happen to exist', () async {
      File('${tmp.path}/core.log').writeAsStringSync('only');

      await actions.clearLocalCache(tmp);

      expect(File('${tmp.path}/core.log').existsSync(), isFalse);
      // never existed
      expect(File('${tmp.path}/crash.log').existsSync(), isFalse);
      expect(tmp.listSync(), isEmpty);
    });
  });

  group('ConnectionRepairActions.oneClickRepairAndReconnect', () {
    test(
      'returns MissingConfig (noActiveProfile) AFTER platform cleanup ran '
      '— proves no preflight load blocks the sync-rescue path',
      () async {
        final fakeCore = _FakeCoreActions();
        final container = ProviderContainer(
          overrides: [coreActionsProvider.overrideWithValue(fakeCore)],
        );
        addTearDown(container.dispose);
        final actions = container.read(connectionRepairActionsProvider);

        final result = await actions.oneClickRepairAndReconnect();

        // No active profile + empty SettingsService → noActiveProfile.
        expect(result, isA<RepairReconnectMissingConfig>());
        expect(
          (result as RepairReconnectMissingConfig).reason,
          MissingConfigReason.noActiveProfile,
        );

        // The whole point of this test: clearSystemProxy ran BEFORE the
        // load step short-circuited. If a preflight load were reintroduced
        // it would short-circuit at step 0 and clearSystemProxy would
        // never fire (counter would be 0).
        if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
          expect(
            fakeCore.clearSystemProxyCalls,
            1,
            reason: 'desktop cleanup must run before the load step',
          );
        }

        // start MUST NOT have been called — we returned at missing-config.
        expect(fakeCore.startCalls, 0);
      },
    );

    test('result types are exhaustively pattern-matchable', () {
      // Compile-time guard: if a new variant is added without updating
      // call sites, this switch will fail to compile.
      const results = <RepairReconnectResult>[
        RepairReconnectSuccess(),
        RepairReconnectFailed(),
        RepairReconnectMissingConfig(MissingConfigReason.noActiveProfile),
      ];
      final labels = results.map((r) {
        switch (r) {
          case RepairReconnectSuccess():
            return 'ok';
          case RepairReconnectFailed():
            return 'fail';
          case RepairReconnectMissingConfig():
            return 'missing';
        }
      }).toList();
      expect(labels, ['ok', 'fail', 'missing']);
    });
  });
}

/// Fake CoreActions used to neutralise platform side-effects (system proxy,
/// core start) so we can assert on call counts. `noSuchMethod` swallows the
/// methods this test doesn't care about (toggle, restart, hotSwitch, etc).
class _FakeCoreActions implements CoreActions {
  int clearSystemProxyCalls = 0;
  int startCalls = 0;
  String? lastStartYaml;
  bool startResult = true;

  @override
  Future<void> clearSystemProxy() async {
    clearSystemProxyCalls++;
  }

  @override
  Future<bool> start(String configYaml) async {
    startCalls++;
    lastStartYaml = configYaml;
    return startResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
