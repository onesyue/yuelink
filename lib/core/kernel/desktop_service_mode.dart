part of 'core_manager.dart';

/// Desktop "service mode": mihomo runs as a subprocess of an installed
/// privileged helper, talked to over a Unix socket / named pipe. Used
/// when the user has the helper installed AND has opted into TUN mode
/// on macOS / Linux / Windows.
///
/// Body of `_startDesktopServiceMode` + `_shouldUseDesktopServiceMode`
/// lifted out of core_manager.dart (~230 lines) so the FFI start path
/// stays readable. Both members live on `CoreManager` via `part of` —
/// they need to mutate `_apiPort`, `_running`, `_serviceModeActive`,
/// `_pendingOperation`, `_api` / `_stream` / `_clashCore` invalidation,
/// which belong on the singleton, not in a separate sidecar.

extension _DesktopServiceMode on CoreManager {
  Future<bool> _shouldUseDesktopServiceMode(String connectionMode) async {
    if (!ServiceManager.isSupported || isMockMode) return false;
    // ServiceManager.isSupported already gates by platform (mac/linux/win).
    // The previous extra `Platform.isMacOS || isWindows` clause silently
    // excluded Linux even though the install UI showed it as supported,
    // leaving Linux users with a "Service Mode installed" badge that did
    // nothing. Linux + Unix-socket helper is now first-class.
    if (!(Platform.isMacOS || Platform.isLinux || Platform.isWindows)) {
      return false;
    }
    if (connectionMode != 'tun') return false;
    return ServiceManager.isInstalled();
  }

  Future<bool> _startDesktopServiceMode(
    String configYaml,
    List<StartupStep> steps, {
    required String connectionMode,
    required String desktopTunStack,
    List<String> tunBypassAddresses = const [],
    List<String> tunBypassProcesses = const [],
    String quicRejectPolicy = ConfigTemplate.defaultQuicRejectPolicy,
  }) async {
    String processed = configYaml;
    String? homeDir;

    try {
      await diag.runStartupStep(
        steps,
        'ensureGeo',
        StartupError.geoFilesFailed,
        () async {
          final installed = await GeoDataService.ensureFiles();
          return 'installed=$installed';
        },
      );

      await diag.runStartupStep(
        steps,
        'buildConfig',
        StartupError.configBuildFailed,
        () async {
          final appDir = await getApplicationSupportDirectory();
          homeDir = appDir.path;

          // A5a relay wiring on desktop service-mode path.
          final relay = await _resolveRelay();
          final withOverwrite = await _prepareConfig(
            configYaml,
            relayProfile: relay.profile,
          );
          processed = await ConfigTemplate.processInIsolate(
            withOverwrite,
            apiPort: _apiPort,
            secret: _apiSecret,
            connectionMode: connectionMode,
            desktopTunStack: desktopTunStack,
            tunBypassAddresses: tunBypassAddresses,
            tunBypassProcesses: tunBypassProcesses,
            quicRejectPolicy: quicRejectPolicy,
            relayHostWhitelist: relay.bypassHosts,
          );
          _apiPort = ConfigTemplate.getApiPort(processed);
          _mixedPort = ConfigTemplate.getMixedPort(processed);
          final parsedSecret = ConfigTemplate.getSecret(processed);
          if (parsedSecret != null && parsedSecret.isNotEmpty) {
            _apiSecret = parsedSecret;
          }
          _api = null;
          _stream = null;
          _clashCore = null;
          return 'output=${processed.length}b, apiPort=$_apiPort, '
              'mixedPort=$_mixedPort, homeDir=$homeDir';
        },
      );

      // Two-factor readiness: SCM registered (isInstalled) + HTTP listener
      // actually answering. Without the second factor, install() can return
      // success while the helper's listener is still binding, causing the
      // subsequent POST /v1/start to race and fail — the classic "user has
      // to refresh once before it connects" symptom. Matches FlClash's
      // `sc query RUNNING && ping` and CVR's `wait_for_service_ipc`.
      await diag.runStartupStep(
        steps,
        'waitService',
        StartupError.coreStartFailed,
        () async {
          for (var i = 0; i < 150; i++) {
            if (await ServiceClient.ping()) {
              return 'ready after ${i + 1} ping(s)';
            }
            await Future.delayed(const Duration(milliseconds: 200));
          }
          throw Exception(
            'service helper not answering ping after 30s — likely a cold '
            'install + Windows Defender / TUN driver init. Retry usually '
            'works once the helper has bound its listener.',
          );
        },
      );

      await diag.runStartupStep(
        steps,
        'startService',
        StartupError.coreStartFailed,
        () async {
          // Write the processed config to a file in homeDir BEFORE calling
          // the helper. The helper no longer accepts raw YAML over IPC — it
          // reads from the file path we hand it (which it validates against
          // its install-time path allowlist). This eliminates the previous
          // "client → root file write" attack surface.
          final configFile = File('$homeDir/yuelink-service.yaml');
          await configFile.parent.create(recursive: true);
          await configFile.writeAsString(processed);

          // One silent retry on first start — the helper may have passed
          // ping but mihomo subprocess spawn can still lose a race against
          // Windows' TUN driver registration on the very first connect.
          DesktopServiceInfo status;
          try {
            status = await ServiceClient.start(
              configPath: configFile.path,
              homeDir: homeDir!,
            );
          } catch (e) {
            debugPrint(
              '[CoreManager] startService attempt-1 failed: $e — '
              'retrying once after 1.5 s warmup',
            );
            await Future.delayed(const Duration(milliseconds: 1500));
            status = await ServiceClient.start(
              configPath: configFile.path,
              homeDir: homeDir!,
            );
          }
          _running = true;
          _serviceModeActive = true;
          return 'service OK, pid=${status.pid ?? 0}';
        },
      );

      await diag.runStartupStep(
        steps,
        'waitApi',
        StartupError.apiTimeout,
        () async {
          // Windows cold-start budget: wintun.dll first-load + Defender scan
          // + mihomo process start + external-controller bind can push past
          // 10 s on older machines. Previous 5 s cap caused "install OK,
          // first connect fails, second connect works" — users had to click
          // twice because the app was racing the TUN driver. 300 × 100 ms
          // = 30 s also gives the service watchdog time to recover from one
          // early child crash before the UI declares startup failed.
          var lastState = 'no service status yet';
          for (var i = 1; i <= 300; i++) {
            if (await api.isAvailable()) {
              return 'ready after $i attempts, $lastState';
            }
            try {
              final status = await ServiceClient.status();
              if (!status.mihomoRunning) {
                lastState =
                    'child stopped: '
                    '${status.lastError ?? status.lastExit ?? 'unknown'}';
              } else {
                lastState = 'child running pid=${status.pid ?? 0}';
              }
            } catch (e) {
              lastState = 'service status unavailable: $e';
            }
            await Future.delayed(const Duration(milliseconds: 100));
          }
          throw Exception(
            'API not available after 300 attempts (30s); $lastState',
          );
        },
      );

      // ── waitProxies (v1.0.22 P0-2, desktop service mode) ─────────
      // Service-helper-hosted mihomo binds /version before /proxies
      // is fully populated, same as the FFI path. See _waitProxiesReady.
      await diag.runStartupStep(
        steps,
        'waitProxies',
        StartupError.apiTimeout,
        () async {
          return await _waitProxiesReady();
        },
      );

      await diag.runStartupStep(
        steps,
        'verify',
        StartupError.coreDiedAfterStart,
        () async {
          final status = await ServiceClient.status();
          final apiOk = await api.isAvailable();

          if (!status.mihomoRunning) {
            throw Exception('service child is not running');
          }
          if (!apiOk) {
            throw Exception('API unavailable after startup');
          }

          final appDir = await getApplicationSupportDirectory();
          await File(
            '${appDir.path}/${CoreManager._kLastWorkingConfig}',
          ).writeAsString(processed);

          var info = 'serviceRunning=${status.mihomoRunning}, apiOk=$apiOk';
          try {
            final dns = await api.queryDns('google.com');
            final answers = dns['Answer'] as List?;
            info += ', dns=${answers?.length ?? 0}answers';
          } catch (e) {
            info += ', dnsErr=$e';
          }
          return info;
        },
      );

      await _persistPorts();
      await _finishReport(steps, true, null);
      // A5b: kick off the background probe AFTER finishReport so the
      // current start's report is finalised first. Fire-and-forget by
      // design — probe results land in metrics for the NEXT start, not
      // this one.
      unawaited(_backgroundProbe());
      // A5c-2: sample the client-side network profile (IPv6/NAT/medium)
      // — also fire-and-forget. No-ops when the cached sample is younger
      // than 6h, so users restarting frequently don't get sampled
      // repeatedly.
      unawaited(_backgroundNetworkSample());
      _pendingOperation?.complete();
      _pendingOperation = null;
      return true;
    } catch (e) {
      final failedName =
          steps.where((s) => !s.success).firstOrNull?.name ?? 'unknown';
      await _finishReport(steps, false, failedName);

      if (_running || _serviceModeActive) {
        _running = false;
        try {
          await ServiceClient.stop();
        } catch (stopError) {
          debugPrint(
            '[CoreManager] cleanup ServiceClient.stop() after failed '
            'desktop start: $stopError',
          );
        }
      }
      _serviceModeActive = false;
      _pendingOperation?.complete();
      _pendingOperation = null;
      rethrow;
    }
  }
}
