import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/domain/models/profile.dart';
import 'package:yuelink/infrastructure/repositories/profile_repository.dart';
import 'package:yuelink/modules/profiles/providers/profiles_providers.dart';

/// Regression coverage for the dispose guards added to ProfilesNotifier in
/// commit 13e9d12 ("fix(riverpod3): guard post-dispose state writes across 5
/// notifiers"). riverpod 3 tightened UnmountedRefException so writing `state`
/// after the provider is disposed throws.
///
/// The specific trigger caught during macOS integration runs: the dashboard
/// scaffold test tore down the container while ProfilesNotifier.load()'s
/// `await _repo.loadProfiles()` was still in flight; the continuation then
/// hit `state = AsyncValue.data(...)` on a disposed notifier.
///
/// Each guarded site follows the same shape:
///   `await _repo.<method>() → if (!ref.mounted) return; → state = ...`
/// This file locks down load() and add() — the two most common user paths.

class _FakeProfileRepo extends ProfileRepository {
  const _FakeProfileRepo({required this.loadFuture, required this.addFuture});

  final Future<List<Profile>> loadFuture;
  final Future<Profile> addFuture;

  @override
  Future<List<Profile>> loadProfiles() => loadFuture;

  @override
  Future<Profile> addProfile({
    required String name,
    required String url,
    int? proxyPort,
    ProfileSource source = ProfileSource.manual,
  }) =>
      addFuture;
}

bool _isDisposeError(Object e) {
  final s = e.toString().toLowerCase();
  return s.contains('disposed') ||
      s.contains('cannot use state') ||
      s.contains('after it was disposed');
}

Profile _sampleProfile(String id) => Profile(
      id: id,
      name: 'sample-$id',
      url: 'https://example.com/sub',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() {
    // ProfileRepository.loadProfiles (real path) calls
    // getApplicationSupportDirectory(); even though the fake bypasses it,
    // profile_repository's module-level constants still lazy-evaluate under
    // some paths, so mock to keep tests hermetic.
    tempDir = Directory.systemTemp.createTempSync('yuelink_profiles_guard_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        if (call.method == 'getApplicationSupportDirectory' ||
            call.method == 'getApplicationDocumentsDirectory') {
          return tempDir.path;
        }
        return null;
      },
    );
  });

  tearDownAll(() {
    tempDir.deleteSync(recursive: true);
  });

  // ── case A: load() continuation runs after dispose ─────────────────────
  //
  // build() calls load() synchronously; load() awaits `_repo.loadProfiles()`
  // then writes `state = AsyncValue.data(profiles)`. Before the guard, a
  // container.dispose() between the await and the state write would throw
  // "Cannot use state of a disposed provider" into the Zone.
  test('load() completion after dispose does not write state', () async {
    final loadTrigger = Completer<List<Profile>>();
    final errors = <Object>[];

    await runZonedGuarded<Future<void>>(() async {
      final container = ProviderContainer(overrides: [
        profileRepositoryProvider.overrideWithValue(_FakeProfileRepo(
          loadFuture: loadTrigger.future,
          addFuture: Future<Profile>.value(_sampleProfile('unused')),
        )),
      ]);

      // Trigger build → load() is invoked, state flips to loading, awaits
      // the repo future we control.
      container.read(profilesProvider);

      // Yield a microtask so the synchronous prelude of load() runs before
      // we dispose.
      await Future<void>.delayed(Duration.zero);
      container.dispose();

      // Now complete the in-flight future. Without the `if (!ref.mounted)
      // return` guard the continuation would write state on a disposed
      // notifier.
      loadTrigger.complete([_sampleProfile('a'), _sampleProfile('b')]);

      await Future<void>.delayed(const Duration(milliseconds: 50));
    }, (err, _) => errors.add(err));

    final bad = errors.where(_isDisposeError).toList();
    expect(bad, isEmpty,
        reason: 'load() must check ref.mounted before state =; got: $bad');
  });

  // ── case B: add() continuation runs after dispose ──────────────────────
  //
  // Realistic trigger: user taps "add subscription" → repo download is in
  // flight → user navigates away / account switch → notifier disposed →
  // download lands. The guard at `if (!ref.mounted) return profile;` after
  // `await _repo.addProfile(...)` prevents the `state = AsyncValue.data([...
  // ?current, profile])` write from firing.
  test('add() completion after dispose does not write state', () async {
    final loadTrigger = Completer<List<Profile>>();
    final addTrigger = Completer<Profile>();
    final errors = <Object>[];

    await runZonedGuarded<Future<void>>(() async {
      final container = ProviderContainer(overrides: [
        profileRepositoryProvider.overrideWithValue(_FakeProfileRepo(
          loadFuture: loadTrigger.future,
          addFuture: addTrigger.future,
        )),
      ]);

      // Get the notifier first; satisfy the initial build() load() so it
      // doesn't race with our dispose path.
      final notifier = container.read(profilesProvider.notifier);
      loadTrigger.complete(<Profile>[]);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Kick off the in-flight add — do NOT await, we want the dispose to
      // race the completion.
      unawaited(notifier.add(name: 'new', url: 'https://example.com/new'));

      // Let the sync prelude of add() run, then tear down while the repo
      // call is still pending.
      await Future<void>.delayed(Duration.zero);
      container.dispose();

      addTrigger.complete(_sampleProfile('new-id'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }, (err, _) => errors.add(err));

    final bad = errors.where(_isDisposeError).toList();
    expect(bad, isEmpty,
        reason: 'add() must check ref.mounted before state =; got: $bad');
  });
}
