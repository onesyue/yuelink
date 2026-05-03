import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/constants.dart';
import 'package:yuelink/core/service/service_manager.dart';
import 'package:yuelink/core/service/service_manager_env.dart';
import 'package:yuelink/core/service/service_models.dart';
import 'package:yuelink/core/storage/settings_service.dart';

/// State-combination tests for the four read-only `ServiceManager` methods:
/// `isInstalled`, `isReady`, `getInfo`, `waitUntilReachable`. Each method
/// is driven through the three test seams in `service_manager_env.dart`
/// (`ServiceFileSystem`, `ServiceProcessRunner`, `ServiceClientProbe`) +
/// SettingsService backed by a path_provider mock'd tmp dir.
///
/// PlatformProbe drives macOS / Linux / Windows read-only state combos
/// without touching install/update/uninstall script execution.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory pathProviderDir;
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  setUp(() {
    pathProviderDir = Directory.systemTemp.createTempSync('yl_svc_mgr_path_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
          if (call.method == 'getApplicationSupportDirectory') {
            return pathProviderDir.path;
          }
          return null;
        });
    SettingsService.invalidateCache();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    SettingsService.invalidateCache();
    ServiceManager.resetProbesForTesting();
    if (pathProviderDir.existsSync()) {
      pathProviderDir.deleteSync(recursive: true);
    }
  });

  // ── Paths the macOS `isInstalled` branch checks ────────────────────────
  // Mirror service_manager.dart private getters; kept here so tests don't
  // reach into private state.
  const macServiceDir = '/Library/Application Support/YueLink/Service';
  const macHelperPath = '$macServiceDir/yuelink-service-helper';
  const macMihomoPath = '$macServiceDir/yuelink-mihomo';
  const macPlistPath =
      '/Library/LaunchDaemons/${AppConstants.desktopServiceLabel}.plist';
  const linuxServiceDir = '/opt/yuelink-service';
  const linuxHelperPath = '$linuxServiceDir/yuelink-service-helper';
  const linuxMihomoPath = '$linuxServiceDir/yuelink-mihomo';
  const linuxUnitPath =
      '/etc/systemd/system/${AppConstants.desktopServiceLabel}.service';

  group('ServiceManager.isInstalled (macOS)', () {
    setUp(() {
      ServiceManager.setProbesForTesting(platformProbe: _FakePlatform.macOS());
    });

    test('all three files present + socket path set → true', () async {
      ServiceManager.setProbesForTesting(
        fileSystem: _FakeFileSystem.allExist({
          macPlistPath,
          macHelperPath,
          macMihomoPath,
        }),
      );
      await SettingsService.setServiceSocketPath('/var/run/yuelink-test.sock');

      expect(await ServiceManager.isInstalled(), isTrue);
    });

    test('plist absent → false (early exit, socket not consulted)', () async {
      ServiceManager.setProbesForTesting(
        fileSystem: _FakeFileSystem.allExist({macHelperPath, macMihomoPath}),
      );
      await SettingsService.setServiceSocketPath('/var/run/yuelink-test.sock');

      expect(await ServiceManager.isInstalled(), isFalse);
    });

    test('helper binary absent → false', () async {
      ServiceManager.setProbesForTesting(
        fileSystem: _FakeFileSystem.allExist({macPlistPath, macMihomoPath}),
      );
      await SettingsService.setServiceSocketPath('/var/run/yuelink-test.sock');

      expect(await ServiceManager.isInstalled(), isFalse);
    });

    test('mihomo binary absent → false', () async {
      ServiceManager.setProbesForTesting(
        fileSystem: _FakeFileSystem.allExist({macPlistPath, macHelperPath}),
      );
      await SettingsService.setServiceSocketPath('/var/run/yuelink-test.sock');

      expect(await ServiceManager.isInstalled(), isFalse);
    });

    test(
      'all files present + socket path null → false (partial-uninstall guard)',
      () async {
        ServiceManager.setProbesForTesting(
          fileSystem: _FakeFileSystem.allExist({
            macPlistPath,
            macHelperPath,
            macMihomoPath,
          }),
        );
        // Don't write socket — getServiceSocketPath returns null.

        expect(await ServiceManager.isInstalled(), isFalse);
      },
    );

    test('all files present + socket path empty string → false', () async {
      ServiceManager.setProbesForTesting(
        fileSystem: _FakeFileSystem.allExist({
          macPlistPath,
          macHelperPath,
          macMihomoPath,
        }),
      );
      await SettingsService.setServiceSocketPath('');

      expect(await ServiceManager.isInstalled(), isFalse);
    });
  });

  group('ServiceManager.isInstalled (Linux)', () {
    setUp(() {
      ServiceManager.setProbesForTesting(platformProbe: _FakePlatform.linux());
    });

    test('unit + helper + mihomo + socket path set → true', () async {
      ServiceManager.setProbesForTesting(
        fileSystem: _FakeFileSystem.allExist({
          linuxUnitPath,
          linuxHelperPath,
          linuxMihomoPath,
        }),
      );
      await SettingsService.setServiceSocketPath('/run/yuelink-test.sock');

      expect(await ServiceManager.isInstalled(), isTrue);
    });

    test('systemd unit absent → false', () async {
      ServiceManager.setProbesForTesting(
        fileSystem: _FakeFileSystem.allExist({
          linuxHelperPath,
          linuxMihomoPath,
        }),
      );
      await SettingsService.setServiceSocketPath('/run/yuelink-test.sock');

      expect(await ServiceManager.isInstalled(), isFalse);
    });

    test('files present + socket path empty → false', () async {
      ServiceManager.setProbesForTesting(
        fileSystem: _FakeFileSystem.allExist({
          linuxUnitPath,
          linuxHelperPath,
          linuxMihomoPath,
        }),
      );
      await SettingsService.setServiceSocketPath('');

      expect(await ServiceManager.isInstalled(), isFalse);
    });
  });

  group('ServiceManager.isInstalled (Windows)', () {
    setUp(() {
      ServiceManager.setProbesForTesting(
        platformProbe: _FakePlatform.windows(),
      );
    });

    test('SCM service present + auth token set → true', () async {
      ServiceManager.setProbesForTesting(
        processRunner: _FakeProcessRunner((exe, args) async {
          expect(exe, 'sc');
          expect(args, ['query', AppConstants.desktopServiceName]);
          return ProcessResult(1, 0, '', '');
        }),
      );
      await SettingsService.setServiceAuthToken('token');

      expect(await ServiceManager.isInstalled(), isTrue);
    });

    test('SCM service absent → false', () async {
      ServiceManager.setProbesForTesting(
        processRunner: _FakeProcessRunner(
          (_, _) async => ProcessResult(1, 1060, '', 'not found'),
        ),
      );
      await SettingsService.setServiceAuthToken('token');

      expect(await ServiceManager.isInstalled(), isFalse);
    });

    test('SCM service present + auth token missing → false', () async {
      ServiceManager.setProbesForTesting(
        processRunner: _FakeProcessRunner(
          (_, _) async => ProcessResult(1, 0, '', ''),
        ),
      );

      expect(await ServiceManager.isInstalled(), isFalse);
    });
  });

  group('ServiceManager.isReady', () {
    test(
      'not installed (no fs/socket setup) → false without invoking ping',
      () async {
        final clientProbe = _FakeClientProbe(pingResult: true);
        ServiceManager.setProbesForTesting(
          fileSystem: _FakeFileSystem.allExist(const {}),
          clientProbe: clientProbe,
        );

        expect(await ServiceManager.isReady(), isFalse);
        expect(
          clientProbe.pingCalls,
          0,
          reason: 'isReady must short-circuit on !isInstalled',
        );
      },
    );

    test(
      'installed + ping returns true on first try → true',
      () async {
        await _seedMacInstalled(
          plistPath: macPlistPath,
          helperPath: macHelperPath,
          mihomoPath: macMihomoPath,
        );
        final clientProbe = _FakeClientProbe(pingResult: true);
        ServiceManager.setProbesForTesting(clientProbe: clientProbe);

        expect(await ServiceManager.isReady(), isTrue);
        expect(clientProbe.pingCalls, 1);
      },
      skip: Platform.isMacOS ? null : 'macOS-only state combos',
    );

    test(
      'installed + ping always false → false after deadline (no infinite loop)',
      () async {
        await _seedMacInstalled(
          plistPath: macPlistPath,
          helperPath: macHelperPath,
          mihomoPath: macMihomoPath,
        );
        final clientProbe = _FakeClientProbe(pingResult: false);
        ServiceManager.setProbesForTesting(clientProbe: clientProbe);

        expect(
          await ServiceManager.isReady(
            deadline: const Duration(milliseconds: 50),
          ),
          isFalse,
        );
        // Polled at least once before the deadline elapsed.
        expect(clientProbe.pingCalls, greaterThan(0));
      },
      skip: Platform.isMacOS ? null : 'macOS-only state combos',
    );

    test(
      'installed + ping false then true → true (eventual success)',
      () async {
        await _seedMacInstalled(
          plistPath: macPlistPath,
          helperPath: macHelperPath,
          mihomoPath: macMihomoPath,
        );
        // Returns false twice, then true.
        final clientProbe = _FakeClientProbe.sequence([false, false, true]);
        ServiceManager.setProbesForTesting(clientProbe: clientProbe);

        expect(
          await ServiceManager.isReady(deadline: const Duration(seconds: 2)),
          isTrue,
        );
        expect(clientProbe.pingCalls, 3);
      },
      skip: Platform.isMacOS ? null : 'macOS-only state combos',
    );
  });

  group('ServiceManager.getInfo', () {
    test('not installed → DesktopServiceInfo.notInstalled', () async {
      ServiceManager.setProbesForTesting(
        fileSystem: _FakeFileSystem.allExist(const {}),
      );

      final info = await ServiceManager.getInfo();
      expect(info.installed, isFalse);
      expect(info.reachable, isFalse);
      expect(info.mihomoRunning, isFalse);
    });

    test(
      'installed + status throws → installed=true reachable=false detail set',
      () async {
        await _seedMacInstalled(
          plistPath: macPlistPath,
          helperPath: macHelperPath,
          mihomoPath: macMihomoPath,
        );
        ServiceManager.setProbesForTesting(
          clientProbe: _FakeClientProbe(
            statusError: Exception('socket EPIPE'),
            expectedVersionResult: '1',
          ),
        );

        final info = await ServiceManager.getInfo();
        expect(info.installed, isTrue);
        expect(info.reachable, isFalse);
        expect(info.detail, contains('socket EPIPE'));
      },
      skip: Platform.isMacOS ? null : 'macOS-only state combos',
    );

    test(
      'installed + status ok + version match → no needsReinstall',
      () async {
        await _seedMacInstalled(
          plistPath: macPlistPath,
          helperPath: macHelperPath,
          mihomoPath: macMihomoPath,
        );
        ServiceManager.setProbesForTesting(
          clientProbe: _FakeClientProbe(
            statusResult: const DesktopServiceInfo(
              installed: true,
              reachable: true,
              mihomoRunning: true,
            ),
            remoteVersionResult: '7',
            expectedVersionResult: '7',
          ),
        );

        final info = await ServiceManager.getInfo();
        expect(info.installed, isTrue);
        expect(info.reachable, isTrue);
        expect(info.serviceVersion, '7');
        expect(info.needsReinstall, isFalse);
      },
      skip: Platform.isMacOS ? null : 'macOS-only state combos',
    );

    test(
      'installed + version mismatch → needsReinstall=true',
      () async {
        await _seedMacInstalled(
          plistPath: macPlistPath,
          helperPath: macHelperPath,
          mihomoPath: macMihomoPath,
        );
        ServiceManager.setProbesForTesting(
          clientProbe: _FakeClientProbe(
            statusResult: const DesktopServiceInfo(
              installed: true,
              reachable: true,
              mihomoRunning: true,
            ),
            remoteVersionResult: '6',
            expectedVersionResult: '7',
          ),
        );

        final info = await ServiceManager.getInfo();
        expect(info.needsReinstall, isTrue);
        expect(info.serviceVersion, '6');
      },
      skip: Platform.isMacOS ? null : 'macOS-only state combos',
    );

    test(
      'installed + remoteVersion null → no needsReinstall (legacy helper)',
      () async {
        await _seedMacInstalled(
          plistPath: macPlistPath,
          helperPath: macHelperPath,
          mihomoPath: macMihomoPath,
        );
        ServiceManager.setProbesForTesting(
          clientProbe: _FakeClientProbe(
            statusResult: const DesktopServiceInfo(
              installed: true,
              reachable: true,
              mihomoRunning: true,
            ),
            remoteVersionResult: null,
            expectedVersionResult: '7',
          ),
        );

        final info = await ServiceManager.getInfo();
        expect(info.needsReinstall, isFalse);
        expect(info.serviceVersion, isNull);
      },
      skip: Platform.isMacOS ? null : 'macOS-only state combos',
    );
  });

  group('ServiceManager.waitUntilReachable', () {
    test(
      'ping returns true on first attempt → completes without throwing',
      () async {
        final clientProbe = _FakeClientProbe(pingResult: true);
        ServiceManager.setProbesForTesting(clientProbe: clientProbe);

        await ServiceManager.waitUntilReachable(
          deadline: const Duration(seconds: 1),
          pollInterval: const Duration(milliseconds: 10),
        );
        expect(clientProbe.pingCalls, 1);
      },
    );

    test(
      'ping false until deadline → throws ProcessException with diag info',
      () async {
        final clientProbe = _FakeClientProbe(pingResult: false);
        ServiceManager.setProbesForTesting(
          clientProbe: clientProbe,
          // Make the diagnostics path return predictable text.
          fileSystem: _FakeFileSystem(
            existsMap: const {},
            readStringMap: const {},
          ),
          processRunner: _FakeProcessRunner.alwaysThrows(
            Exception('proc-down'),
          ),
        );

        await expectLater(
          ServiceManager.waitUntilReachable(
            deadline: const Duration(milliseconds: 50),
            pollInterval: const Duration(milliseconds: 10),
          ),
          throwsA(
            isA<ProcessException>().having(
              (e) => e.message,
              'message',
              allOf(
                contains('IPC never came up'),
                contains('helper_log=<missing>'),
              ),
            ),
          ),
        );
        expect(clientProbe.pingCalls, greaterThan(0));
      },
    );

    test('ping eventually succeeds → completes without throwing', () async {
      final clientProbe = _FakeClientProbe.sequence([false, false, true]);
      ServiceManager.setProbesForTesting(clientProbe: clientProbe);

      await ServiceManager.waitUntilReachable(
        deadline: const Duration(seconds: 1),
        pollInterval: const Duration(milliseconds: 10),
      );
      expect(clientProbe.pingCalls, 3);
    });
  });
}

// ── Helpers ─────────────────────────────────────────────────────────────────

/// Seed the on-disk + SettingsService state so `isInstalled` returns true
/// on a macOS host: the three required paths are reported present by a
/// fake filesystem, and a sentinel socket path is written through the real
/// SettingsService (path_provider already redirected to a tmp dir).
Future<void> _seedMacInstalled({
  required String plistPath,
  required String helperPath,
  required String mihomoPath,
}) async {
  ServiceManager.setProbesForTesting(
    fileSystem: _FakeFileSystem.allExist({plistPath, helperPath, mihomoPath}),
  );
  await SettingsService.setServiceSocketPath('/var/run/yuelink-test.sock');
}

class _FakeFileSystem implements ServiceFileSystem {
  final Set<String> existsMap;
  final Map<String, String> readStringMap;

  _FakeFileSystem({
    required Iterable<String> existsMap,
    required this.readStringMap,
  }) : existsMap = existsMap.toSet();

  factory _FakeFileSystem.allExist(Set<String> paths) =>
      _FakeFileSystem(existsMap: paths, readStringMap: const {});

  @override
  bool exists(String path) => existsMap.contains(path);

  @override
  Future<String?> readString(String path) async => readStringMap[path];
}

class _FakeProcessRunner implements ServiceProcessRunner {
  final Future<ProcessResult> Function(
    String executable,
    List<String> arguments,
  )
  handler;

  _FakeProcessRunner(this.handler);

  factory _FakeProcessRunner.alwaysThrows(Object error) =>
      _FakeProcessRunner((_, _) async => throw error);

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    Duration? timeout,
  }) {
    final f = handler(executable, arguments);
    return timeout == null ? f : f.timeout(timeout);
  }
}

/// Configurable fake for the IPC + version probe. Two construction
/// modes: a single fixed result for all calls (default), or an explicit
/// sequence of ping results consumed left-to-right (stays on the last
/// element after exhaustion — handy for "false N times then true").
class _FakeClientProbe implements ServiceClientProbe {
  final List<bool> _pingSequence;
  final DesktopServiceInfo? statusResult;
  final Object? statusError;
  final String? remoteVersionResult;
  final String expectedVersionResult;

  int pingCalls = 0;
  int statusCalls = 0;
  int remoteVersionCalls = 0;
  int expectedVersionCalls = 0;

  _FakeClientProbe({
    bool pingResult = false,
    this.statusResult,
    this.statusError,
    this.remoteVersionResult,
    this.expectedVersionResult = '0',
  }) : _pingSequence = [pingResult];

  _FakeClientProbe.sequence(List<bool> sequence)
    : _pingSequence = List.of(sequence),
      statusResult = null,
      statusError = null,
      remoteVersionResult = null,
      expectedVersionResult = '0';

  @override
  Future<bool> ping() async {
    final i = pingCalls < _pingSequence.length
        ? pingCalls
        : _pingSequence.length - 1;
    pingCalls++;
    return _pingSequence[i];
  }

  @override
  Future<DesktopServiceInfo> status() async {
    statusCalls++;
    if (statusError != null) throw statusError!;
    return statusResult ?? DesktopServiceInfo.notInstalled();
  }

  @override
  Future<String?> remoteVersion() async {
    remoteVersionCalls++;
    return remoteVersionResult;
  }

  @override
  Future<String> expectedVersion() async {
    expectedVersionCalls++;
    return expectedVersionResult;
  }
}

class _FakePlatform implements ServicePlatformProbe {
  const _FakePlatform({
    required this.isMacOS,
    required this.isWindows,
    required this.isLinux,
  });

  factory _FakePlatform.macOS() =>
      const _FakePlatform(isMacOS: true, isWindows: false, isLinux: false);

  factory _FakePlatform.windows() =>
      const _FakePlatform(isMacOS: false, isWindows: true, isLinux: false);

  factory _FakePlatform.linux() =>
      const _FakePlatform(isMacOS: false, isWindows: false, isLinux: true);

  @override
  final bool isMacOS;

  @override
  final bool isWindows;

  @override
  final bool isLinux;
}
