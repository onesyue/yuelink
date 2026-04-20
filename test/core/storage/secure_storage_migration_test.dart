import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/core/storage/secure_storage_migration.dart';

/// Unit coverage for [SecureStorageMigration]. Uses function-level
/// callback injection (not the MethodChannel path) so these tests don't
/// depend on flutter_secure_storage or path_provider plugin loading.
///
/// Cases locked down:
///   A) fresh backup copies every non-empty known key + profile key
///   B) missing keys (reader returns null) don't count as failures
///   C) second call with marker already written → alreadyMigrated=true,
///      no new reads
///   D) reader throws on some keys → failed++, other keys still backed up
///   E) reader values never leak into EventLog — only key names do
///      (verified via event.log file contents)

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Shared across all tests in this file. Rationale: EventLog caches
  // its File handle in a static field (_file) and has no public reset
  // API, so per-test tempDirs would leave stale handles pointing at
  // deleted paths — event.log writes in later tests would silently
  // fail inside EventLog's own catch(_). One shared tempDir for
  // path_provider keeps EventLog's cache valid.
  //
  // Each test still gets its own `shadowSubDir` for migration state,
  // so shadow-file assertions don't leak between tests.
  late Directory eventDir;

  setUpAll(() {
    eventDir = Directory.systemTemp.createTempSync('yuelink_migration_evt_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        if (call.method == 'getApplicationSupportDirectory' ||
            call.method == 'getApplicationDocumentsDirectory') {
          return eventDir.path;
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
    eventDir.deleteSync(recursive: true);
  });

  late Directory shadowSubDir;
  setUp(() {
    shadowSubDir = Directory.systemTemp.createTempSync('yuelink_migration_sh_');
  });
  tearDown(() {
    shadowSubDir.deleteSync(recursive: true);
  });

  File shadowFile() =>
      File('${shadowSubDir.path}/secure_storage_shadow_v1.json');

  // ── Case A ────────────────────────────────────────────────────────
  test('backupToShadow copies every non-empty known and profile key',
      () async {
    final store = <String, String>{
      'mihomo_api_secret': 'secret-xyz',
      'yue_auth_token': 'bearer-abc',
      'yue_subscribe_url': 'https://sub.example/abc',
      // yue_user_profile / yue_profile_cached_at / yue_api_host left
      // unset to exercise the null-value skip branch too.
      'sub_url_profile-A': 'https://sub.a',
      'sub_url_profile-B': 'https://sub.b',
    };

    final migration = SecureStorageMigration(
      reader: (k) async => store[k],
      shadowDir: shadowSubDir,
    );

    final result = await migration.backupToShadow(
      profileIds: ['profile-A', 'profile-B'],
    );

    // 6 static + 2 profile-scoped = 8 scanned
    expect(result.scannedKeys, 8);
    // 3 static set + 2 profile set = 5 backed up
    expect(result.backedUpKeys, 5);
    expect(result.skippedKeys, 0);
    expect(result.failedKeys, 0);
    expect(result.alreadyMigrated, false);

    // Shadow file contains only keys we actually had values for, plus
    // the migration marker.
    expect(shadowFile().existsSync(), true);
    final decoded = jsonDecode(shadowFile().readAsStringSync()) as Map;
    expect(decoded['mihomo_api_secret'], 'secret-xyz');
    expect(decoded['yue_auth_token'], 'bearer-abc');
    expect(decoded['yue_subscribe_url'], 'https://sub.example/abc');
    expect(decoded['sub_url_profile-A'], 'https://sub.a');
    expect(decoded['sub_url_profile-B'], 'https://sub.b');
    expect(decoded.containsKey('yue_user_profile'), false);
    expect(decoded['__migrated_v1__'], 'true');
  });

  // ── Case B ────────────────────────────────────────────────────────
  test('missing values do not count as failures', () async {
    final migration = SecureStorageMigration(
      reader: (_) async => null,
      shadowDir: shadowSubDir,
    );

    final result = await migration.backupToShadow();

    // All 6 static keys scanned, none had values, none failed.
    expect(result.scannedKeys, 6);
    expect(result.backedUpKeys, 0);
    expect(result.failedKeys, 0);
    // Marker still gets written so we don't retry every launch.
    final decoded = jsonDecode(shadowFile().readAsStringSync()) as Map;
    expect(decoded['__migrated_v1__'], 'true');
  });

  // ── Case C ────────────────────────────────────────────────────────
  test('second call after marker is set is a no-op', () async {
    final store = <String, String>{'yue_auth_token': 'initial'};
    var readCalls = 0;

    SecureStorageMigration build() => SecureStorageMigration(
          reader: (k) async {
            readCalls++;
            return store[k];
          },
          shadowDir: shadowSubDir,
        );

    final first = await build().backupToShadow();
    expect(first.alreadyMigrated, false);
    expect(first.backedUpKeys, 1);
    final firstReads = readCalls;
    expect(firstReads, greaterThan(0));

    // Even though the real store now has a newer value, idempotency
    // means we don't re-read: marker short-circuits.
    store['yue_auth_token'] = 'changed-after-backup';

    final second = await build().backupToShadow();
    expect(second.alreadyMigrated, true);
    expect(second.scannedKeys, 0);
    expect(second.backedUpKeys, 0);
    // No new reads between the two calls.
    expect(readCalls, firstReads);

    // Shadow still reflects the value at first-backup time — NOT the
    // later in-memory mutation.
    final decoded = jsonDecode(shadowFile().readAsStringSync()) as Map;
    expect(decoded['yue_auth_token'], 'initial');
  });

  // ── Case D ────────────────────────────────────────────────────────
  test('reader exceptions on some keys count as failed, others still back up',
      () async {
    final store = <String, String>{
      'yue_auth_token': 'good-token',
      'yue_api_host': 'https://host.example',
    };
    const poisonedKey = 'mihomo_api_secret';

    final migration = SecureStorageMigration(
      reader: (k) async {
        if (k == poisonedKey) throw StateError('simulated backend glitch');
        return store[k];
      },
      shadowDir: shadowSubDir,
    );

    final result = await migration.backupToShadow();

    expect(result.failedKeys, 1);
    expect(result.backedUpKeys, 2);

    final decoded = jsonDecode(shadowFile().readAsStringSync()) as Map;
    expect(decoded['yue_auth_token'], 'good-token');
    expect(decoded['yue_api_host'], 'https://host.example');
    expect(decoded.containsKey(poisonedKey), false);
  });

  // ── Case E ────────────────────────────────────────────────────────
  test('EventLog never contains raw secret values', () async {
    const secretValue =
        'VERY-SENSITIVE-TOKEN-VALUE-DO-NOT-LEAK-abcdef1234567890';
    final store = <String, String>{
      'yue_auth_token': secretValue,
      'mihomo_api_secret': 'another-secret',
    };

    final migration = SecureStorageMigration(
      reader: (k) async => store[k],
      shadowDir: shadowSubDir,
    );

    await migration.backupToShadow();

    // EventLog writes to getApplicationSupportDirectory()/event.log,
    // which we mocked to `eventDir` at setUpAll.
    final eventLog = File('${eventDir.path}/event.log');
    // Give the fire-and-forget append a moment to flush.
    for (var i = 0; i < 20 && !eventLog.existsSync(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(eventLog.existsSync(), true,
        reason: 'backup_done event should have been appended');
    final logContent = eventLog.readAsStringSync();

    expect(logContent, isNot(contains(secretValue)),
        reason: 'raw token value must never appear in event.log');
    expect(logContent, isNot(contains('another-secret')),
        reason: 'mihomo api secret value must never appear in event.log');
    // But the structured counters / event name must be there so the
    // log is still useful for debugging.
    expect(logContent, contains('[SecureMigration]'));
    expect(logContent, contains('backup_done'));
  });

  // ── Bonus: readShadow / hasShadow / clearShadow round-trip ────────
  test('readShadow strips the marker; clearShadow removes the file',
      () async {
    final store = <String, String>{'yue_auth_token': 'token-42'};
    final migration = SecureStorageMigration(
      reader: (k) async => store[k],
      shadowDir: shadowSubDir,
    );

    await migration.backupToShadow();

    expect(await migration.hasShadow(), true);
    final map = await migration.readShadow();
    expect(map, {'yue_auth_token': 'token-42'});
    expect(map.containsKey('__migrated_v1__'), false);

    await migration.clearShadow();
    expect(await migration.hasShadow(), false);
    expect(await migration.readShadow(), isEmpty);
  });
}
