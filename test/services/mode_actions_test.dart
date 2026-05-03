import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yuelink/core/providers/core_provider.dart';
import 'package:yuelink/core/storage/settings_service.dart';
import 'package:yuelink/modules/dashboard/mode_actions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('yuelink_mode_actions_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (MethodCall methodCall) async {
            if (methodCall.method == 'getApplicationSupportDirectory' ||
                methodCall.method == 'getApplicationDocumentsDirectory') {
              return tempDir.path;
            }
            return null;
          },
        );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    SettingsService.invalidateCache();
    await SettingsService.setConnectionMode('systemProxy');
    await SettingsService.flush();
  });

  testWidgets('connection-mode switch rolls back when runtime switch fails', (
    tester,
  ) async {
    final fakeActions = _FakeCoreActions(hotSwitchResult: false);
    late WidgetRef capturedRef;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          coreStatusProvider.overrideWith(
            () => CoreStatusNotifier(CoreStatus.running),
          ),
          connectionModeProvider.overrideWith(
            () => ConnectionModeNotifier('systemProxy'),
          ),
          coreActionsProvider.overrideWithValue(fakeActions),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            capturedRef = ref;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    await tester.runAsync(() async {
      await ModeActions.setConnectionMode(capturedRef, 'tun');
      await SettingsService.flush();
    });

    expect(fakeActions.hotSwitchCalls, 1);
    expect(fakeActions.lastMode, 'tun');
    expect(fakeActions.lastFallbackMode, 'systemProxy');
    expect(capturedRef.read(connectionModeProvider), 'systemProxy');
    expect(await SettingsService.getConnectionMode(), 'systemProxy');
  });

  testWidgets('connection-mode switch keeps optimistic state on success', (
    tester,
  ) async {
    final fakeActions = _FakeCoreActions(hotSwitchResult: true);
    late WidgetRef capturedRef;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          coreStatusProvider.overrideWith(
            () => CoreStatusNotifier(CoreStatus.running),
          ),
          connectionModeProvider.overrideWith(
            () => ConnectionModeNotifier('systemProxy'),
          ),
          coreActionsProvider.overrideWithValue(fakeActions),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            capturedRef = ref;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    await tester.runAsync(() async {
      await ModeActions.setConnectionMode(capturedRef, 'tun');
      await SettingsService.flush();
    });

    expect(fakeActions.hotSwitchCalls, 1);
    expect(capturedRef.read(connectionModeProvider), 'tun');
    expect(await SettingsService.getConnectionMode(), 'tun');
  });
}

class _FakeCoreActions implements CoreActions {
  _FakeCoreActions({required this.hotSwitchResult});

  final bool hotSwitchResult;
  int hotSwitchCalls = 0;
  String? lastMode;
  String? lastFallbackMode;

  @override
  Future<bool> hotSwitchConnectionMode(
    String newMode, {
    String? fallbackMode,
  }) async {
    hotSwitchCalls++;
    lastMode = newMode;
    lastFallbackMode = fallbackMode;
    return hotSwitchResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
