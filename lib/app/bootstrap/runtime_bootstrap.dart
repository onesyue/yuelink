import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:window_manager/window_manager.dart';

import '../../constants.dart';
import '../../core/managers/system_proxy_manager.dart';
import '../../core/providers/core_provider.dart';
import '../../core/storage/settings_service.dart';
import '../../shared/error_logger.dart';
import '../../shared/event_log.dart';
import '../../shared/feature_flags.dart';
import '../../shared/telemetry.dart';

void configureAndroidEdgeToEdge() {
  if (!Platform.isAndroid) return;
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
    ),
  );
}

void configureImageCacheLimits() {
  PaintingBinding.instance.imageCache.maximumSizeBytes = 50 * 1024 * 1024;
  PaintingBinding.instance.imageCache.maximumSize = 100;
}

void initErrorLogging() {
  ErrorLogger.init();
  if (Platform.isAndroid) {
    unawaited(ErrorLogger.scanAndroidNativeCrashes());
  }
}

void initTelemetryAndFeatureFlags() {
  unawaited(
    Telemetry.init().then((_) async {
      unawaited(FeatureFlags.I.init());

      final today = DateTime.now().toUtc().toIso8601String().substring(0, 10);
      final last = await SettingsService.get<String>('telemetryDailyPingDay');
      if (last != today) {
        Telemetry.event('daily_ping');
        await SettingsService.set('telemetryDailyPingDay', today);
      }
    }),
  );
}

Future<void> cleanupDirtySystemProxy() async {
  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    await SystemProxyManager.cleanupIfDirty();
  }
}

void installSignalProxyCleanup() {
  if (!Platform.isMacOS && !Platform.isLinux) return;
  for (final sig in [ProcessSignal.sigterm, ProcessSignal.sigint]) {
    sig.watch().listen((_) async {
      try {
        await CoreActions.clearSystemProxyStatic().timeout(
          const Duration(seconds: 2),
        );
      } catch (e) {
        EventLog.writeTagged(
          'App',
          'signal_proxy_clear_failed',
          context: {'error': e},
        );
      }
      exit(0);
    });
  }
}

void setupLaunchAtStartup() {
  if (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux) return;
  try {
    launchAtStartup.setup(
      appName: AppConstants.appName,
      appPath: Platform.resolvedExecutable,
    );
  } catch (e) {
    debugPrint('[App] launchAtStartup setup: $e');
  }
}

Future<void> initializeDesktopWindow() async {
  if (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux) return;
  await windowManager.ensureInitialized();
  const windowOptions = WindowOptions(
    size: Size(1280, 720),
    minimumSize: Size(800, 560),
    center: true,
    title: AppConstants.appName,
    titleBarStyle: TitleBarStyle.normal,
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  if (Platform.isLinux) {
    await windowManager.setMinimumSize(const Size(900, 600));
  }
}
