import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../shared/event_log.dart';
import 'auth_token_service.dart';
import 'secure_storage_service.dart';

/// Callback shape so unit tests can inject an in-memory fake without
/// mocking the FlutterSecureStorage MethodChannel. Matches
/// [SecureStorageService.read] 1:1. The restore half (write + delete)
/// will grow its own typedefs when it lands.
typedef KeyReader = Future<String?> Function(String key);

class MigrationResult {
  final int scannedKeys;
  final int backedUpKeys;

  /// Already-present entries in the shadow that we left untouched.
  final int skippedKeys;

  /// Read errors — key was expected but the secure store threw. The
  /// shadow still marks itself as complete so we don't retry every
  /// launch, but these are logged to event.log so users hitting them
  /// can share the log for diagnosis.
  final int failedKeys;

  /// True if the shadow file was already marked as migrated before this
  /// call — no new reads happened.
  final bool alreadyMigrated;

  const MigrationResult({
    required this.scannedKeys,
    required this.backedUpKeys,
    required this.skippedKeys,
    required this.failedKeys,
    required this.alreadyMigrated,
  });

  bool get isNoop => alreadyMigrated || scannedKeys == 0;
}

/// Copies secrets out of [SecureStorageService] (backed by
/// `flutter_secure_storage` on every platform except macOS) into a
/// file-backed "shadow" so the values survive a fss 9 → fss 10 upgrade
/// where the native backend changes under the app's feet (Android
/// EncryptedSharedPreferences → new cipher, Windows Credential Locker →
/// file store).
///
/// This is the **backup half** of the migration. The restore half runs
/// on the post-upgrade release: when fss 10 reads return null, the app
/// pulls values out of the shadow, writes them through the new backend,
/// and calls [clearShadow].
///
/// ## Security
///
/// The shadow is currently plaintext JSON under Application Support.
/// This is acceptable only because the expected lifetime is *minutes*
/// (created on last-fss-9 release startup, consumed + cleared on
/// first-fss-10 release startup). Before wiring this into production
/// startup, swap the file backend for the same AES-256-GCM envelope
/// `_MacEncryptedStore` already uses — see TODO below.
///
/// Callers must never log [MigrationResult] values to disk with any of
/// the actual secret content; this class's own logging uses
/// [EventLog.writeTagged] with counts and key *names* only — values are
/// never placed in the context map.
///
/// ## Not wired into startup
///
/// This file deliberately has no side effects on import and is not
/// called from `main.dart`. Integration into app startup is a separate
/// follow-up change once the encryption work above lands.
class SecureStorageMigration {
  /// Read hook — defaults to the real [SecureStorageService] singleton.
  /// Tests pass an in-memory fake.
  final KeyReader _read;

  /// Directory override for tests. Production code uses
  /// `getApplicationSupportDirectory()` lazily.
  final Directory? _shadowDir;

  SecureStorageMigration({
    KeyReader? reader,
    Directory? shadowDir,
  })  : _read = reader ?? SecureStorageService.instance.read,
        _shadowDir = shadowDir;

  static const _shadowFileName = 'secure_storage_shadow_v1.json';

  /// Sentinel stored inside the shadow map so [backupToShadow] is
  /// idempotent — a second call finds the marker and short-circuits.
  static const _migrationMarker = '__migrated_v1__';

  /// Static set of keys known to the codebase today. Enumerated from
  /// [SecureStorageService] and [AuthTokenService]. Profile-scoped keys
  /// (`sub_url_*`) are passed in by the caller since the profile IDs
  /// aren't known statically.
  ///
  /// If a new secure-storage key is added anywhere in the codebase,
  /// add it here so the migration picks it up.
  static const knownStaticKeys = <String>[
    // SecureStorageService
    'mihomo_api_secret',
    // AuthTokenService
    'yue_auth_token',
    'yue_subscribe_url',
    'yue_user_profile',
    'yue_profile_cached_at',
    'yue_api_host',
  ];

  Future<File> _shadowFile() async {
    final dir = _shadowDir ?? await getApplicationSupportDirectory();
    return File('${dir.path}/$_shadowFileName');
  }

  /// Read all known keys from secure storage and persist them into the
  /// shadow file. Safe to call repeatedly — once the file contains
  /// [_migrationMarker] subsequent calls short-circuit.
  ///
  /// [profileIds] — subscription profile IDs currently known to the app.
  /// Each one contributes a `sub_url_<id>` key to the scan. Pass the
  /// output of `ProfileRepository.loadProfiles()`'s IDs.
  Future<MigrationResult> backupToShadow({
    List<String> profileIds = const [],
  }) async {
    final file = await _shadowFile();

    Map<String, String> existing = {};
    if (await file.exists()) {
      try {
        final raw = await file.readAsString();
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          if (decoded[_migrationMarker] == 'true') {
            EventLog.writeTagged(
              'SecureMigration',
              'skip_already_migrated',
            );
            return const MigrationResult(
              scannedKeys: 0,
              backedUpKeys: 0,
              skippedKeys: 0,
              failedKeys: 0,
              alreadyMigrated: true,
            );
          }
          existing = decoded
              .map((k, v) => MapEntry(k, v is String ? v : v.toString()));
        }
      } catch (e) {
        EventLog.writeTagged(
          'SecureMigration',
          'shadow_read_corrupt',
          context: {'error': e.toString()},
        );
        // Corrupted shadow — treat as absent. Overwrite below.
        existing = {};
      }
    }

    int scanned = 0;
    int backedUp = 0;
    int skipped = 0;
    int failed = 0;

    final targets = <String>[
      ...knownStaticKeys,
      ...profileIds.map((id) => 'sub_url_$id'),
    ];

    for (final key in targets) {
      scanned++;
      if (existing.containsKey(key)) {
        skipped++;
        continue;
      }
      try {
        final value = await _read(key);
        if (value == null || value.isEmpty) {
          // Key genuinely unset — nothing to do, not a failure.
          continue;
        }
        existing[key] = value;
        backedUp++;
      } catch (e) {
        failed++;
        // Intentionally omit the value from context — only the key name
        // and error string land on disk.
        EventLog.writeTagged(
          'SecureMigration',
          'key_read_failed',
          context: {'key': key, 'error': e.toString()},
        );
      }
    }

    // Set the marker even if nothing was backed up — a truly empty
    // secure store shouldn't force a re-scan on every launch.
    existing[_migrationMarker] = 'true';

    try {
      await file.parent.create(recursive: true);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode(existing));
      await tmp.rename(file.path);
    } catch (e) {
      EventLog.writeTagged(
        'SecureMigration',
        'shadow_write_failed',
        context: {'error': e.toString()},
      );
      // Fall through — we still report counts for the caller so it
      // knows the scan happened even if persistence failed.
    }

    EventLog.writeTagged(
      'SecureMigration',
      'backup_done',
      context: {
        'scanned': scanned,
        'backed_up': backedUp,
        'skipped': skipped,
        'failed': failed,
      },
    );

    return MigrationResult(
      scannedKeys: scanned,
      backedUpKeys: backedUp,
      skippedKeys: skipped,
      failedKeys: failed,
      alreadyMigrated: false,
    );
  }

  /// Whether a shadow file exists on disk. Cheap; does not parse.
  Future<bool> hasShadow() async {
    final file = await _shadowFile();
    return file.exists();
  }

  /// Decode the shadow into a plain key→value map, stripping the
  /// migration marker. Returns an empty map if the file is missing or
  /// corrupt. Use this from the post-upgrade release to repopulate the
  /// new secure-storage backend.
  Future<Map<String, String>> readShadow() async {
    final file = await _shadowFile();
    if (!await file.exists()) return const {};
    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      return {
        for (final e in decoded.entries)
          if (e.key != _migrationMarker && e.value is String)
            e.key.toString(): e.value as String,
      };
    } catch (e) {
      EventLog.writeTagged(
        'SecureMigration',
        'shadow_decode_failed',
        context: {'error': e.toString()},
      );
      return const {};
    }
  }

  /// Delete the shadow file. Call this from the post-upgrade release
  /// after `restoreFromShadow` has successfully repopulated the new
  /// backend, so the plaintext shadow doesn't sit on disk longer than
  /// needed.
  Future<void> clearShadow() async {
    final file = await _shadowFile();
    if (await file.exists()) {
      try {
        await file.delete();
        EventLog.writeTagged('SecureMigration', 'shadow_cleared');
      } catch (e) {
        EventLog.writeTagged(
          'SecureMigration',
          'shadow_clear_failed',
          context: {'error': e.toString()},
        );
      }
    }
  }
}
