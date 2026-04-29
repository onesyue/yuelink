import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/domain/checkin/checkin_result_entity.dart';
import 'package:yuelink/domain/checkin/sign_calendar_entity.dart';
import 'package:yuelink/infrastructure/checkin/checkin_repository.dart';
import 'package:yuelink/modules/checkin/providers/checkin_provider.dart';
import 'package:yuelink/modules/yue_auth/providers/yue_auth_providers.dart';

/// Fake repo that hands the test complete control over when each call
/// completes. Lets us hold `_repo.checkin` in flight, dispose the provider,
/// then complete — reproducing the user flow where the checkin page is
/// dismissed mid-request.
class _FakeCheckinRepo implements CheckinRepository {
  _FakeCheckinRepo({required this.checkinFuture, required this.statusFuture});
  final Future<CheckinResult> checkinFuture;
  final Future<CheckinResult?> statusFuture;

  @override
  Future<CheckinResult> checkin(String token) => checkinFuture;

  @override
  Future<CheckinResult?> getCheckinStatus(String token) => statusFuture;

  // Calendar / resign aren't exercised in this dispose-guard test; provide
  // safe stubs so the class stays concrete.
  @override
  Future<SignCalendarMonth?> fetchHistory(String token, {String? month}) async =>
      null;

  @override
  Future<ResignResult> resign(String token) async =>
      const ResignResult(success: false, errorCode: 'unknown');
}

const _kAlreadyLoggedIn =
    AuthState(status: AuthStatus.loggedIn, token: 'test-token');

const _kSuccessResult = CheckinResult(
  type: 'traffic',
  amount: 0,
  amountText: '10GB',
  alreadyChecked: false,
);

bool _isDisposeError(Object e) {
  final s = e.toString().toLowerCase();
  // Riverpod emits slightly different wording across versions — match the
  // common tokens that unambiguously mean "write after dispose".
  return s.contains('disposed') ||
      s.contains('cannot use state') ||
      s.contains('after it was disposed');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() {
    // SettingsService.load() calls getApplicationSupportDirectory(); mock it
    // so CheckinLocalDatasource reads/writes under the temp dir instead of
    // the real host path (which would not exist in unit-test env).
    tempDir = Directory.systemTemp.createTempSync('yuelink_checkin_guard_');
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

  // ── case A: in-flight checkin completes after dispose ──────────────────
  //
  // Reproduces the original P0-B/A: user taps "check in" → await repo.checkin
  // → pops back / logs out / account-switches → provider dispose → network
  // response lands. The pre-fix code wrote `state = copyWith(checkedIn: true)`
  // here and threw "Cannot use state of a disposed provider" into the Zone.
  test('checkin completion after provider dispose does not write state',
      () async {
    final checkinTrigger = Completer<CheckinResult>();
    final statusTrigger = Completer<CheckinResult?>();
    final errors = <Object>[];

    await runZonedGuarded<Future<void>>(() async {
      final container = ProviderContainer(overrides: [
        preloadedAuthStateProvider.overrideWithValue(_kAlreadyLoggedIn),
        checkinRepositoryProvider.overrideWithValue(_FakeCheckinRepo(
          checkinFuture: checkinTrigger.future,
          statusFuture: statusTrigger.future,
        )),
      ]);

      final notifier = container.read(checkinProvider.notifier);
      // Fire and forget — we want to race the repo's completion against
      // the dispose below.
      unawaited(notifier.checkin());

      // Yield one microtask so the sync prelude of checkin() runs
      // (including `state = copyWith(loading: true)`), then dispose while
      // the repo call is still pending.
      await Future<void>.delayed(Duration.zero);
      container.dispose();

      // Now complete the in-flight future. Without the dispose guard, the
      // continuation after `await _repo.checkin` would write
      // `state = copyWith(checkedIn: true, ...)` on a disposed Notifier.
      checkinTrigger.complete(_kSuccessResult);
      // status fetch started from build() — terminate it cleanly too.
      statusTrigger.complete(null);

      // Give microtasks a few hops to run the continuations.
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }, (err, _) => errors.add(err));

    final disposeErrors = errors.where(_isDisposeError).toList();
    expect(disposeErrors, isEmpty,
        reason:
            'checkin() continuation must not touch state after dispose; got: $disposeErrors');
  });

  // ── case B: calling checkin() on an already-disposed notifier ──────────
  //
  // Sync path: if a cached notifier reference is held by UI code and the
  // provider is disposed before the user taps, the first `state = ...`
  // inside checkin() was the line that threw. The early `if (_disposed)
  // return;` gate at the top of checkin() must cover this.
  test('checkin() on an already-disposed notifier is a safe no-op', () async {
    final errors = <Object>[];

    await runZonedGuarded<Future<void>>(() async {
      final container = ProviderContainer(overrides: [
        preloadedAuthStateProvider.overrideWithValue(_kAlreadyLoggedIn),
        checkinRepositoryProvider.overrideWithValue(_FakeCheckinRepo(
          checkinFuture: Future.value(_kSuccessResult),
          statusFuture: Future.value(null),
        )),
      ]);

      final notifier = container.read(checkinProvider.notifier);
      container.dispose();

      // Must return without throwing, even though every subsequent
      // `state = ...` would be illegal.
      await notifier.checkin();
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }, (err, _) => errors.add(err));

    final disposeErrors = errors.where(_isDisposeError).toList();
    expect(disposeErrors, isEmpty,
        reason:
            'checkin() must early-return on _disposed; got: $disposeErrors');
  });
}
