import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/domain/account/account_overview.dart';
import 'package:yuelink/domain/account/notice.dart';
import 'package:yuelink/domain/announcements/announcement_entity.dart';
import 'package:yuelink/infrastructure/account/account_repository.dart';
import 'package:yuelink/infrastructure/announcements/announcements_repository.dart';
import 'package:yuelink/modules/announcements/providers/announcements_providers.dart';
import 'package:yuelink/modules/mine/providers/account_providers.dart';
import 'package:yuelink/modules/yue_auth/providers/yue_auth_providers.dart';

class _FakeAuthNotifier extends AuthNotifier {
  @override
  AuthState build() {
    return const AuthState(status: AuthStatus.loggedIn, token: 'test-token');
  }
}

class _FakeAuthWithProfileNotifier extends AuthNotifier {
  @override
  AuthState build() {
    return AuthState(
      status: AuthStatus.loggedIn,
      token: 'test-token',
      userProfile: UserProfile(
        email: 'cached@example.com',
        planName: '缓存套餐',
        transferEnable: 1000,
        uploadUsed: 100,
        downloadUsed: 200,
        expiredAt: 1770000000,
        onlineCount: 2,
        deviceLimit: 5,
      ),
    );
  }
}

class _FakeAccountRepository extends AccountRepository {
  _FakeAccountRepository(
    this.notices, {
    this.overview,
    this.throwOverview = false,
  });

  final List<AccountNotice> notices;
  final AccountOverview? overview;
  final bool throwOverview;
  int calls = 0;
  int overviewCalls = 0;

  @override
  Future<AccountOverview?> getAccountOverview(String token) async {
    overviewCalls += 1;
    if (throwOverview) throw StateError('sidecar unavailable');
    return overview;
  }

  @override
  Future<List<AccountNotice>> getNotices(String token) async {
    calls += 1;
    return notices;
  }
}

class _FakeAnnouncementsRepository extends AnnouncementsRepository {
  _FakeAnnouncementsRepository(this.announcements)
    : super(api: XBoardApi(baseUrl: 'https://example.com'));

  final List<Announcement> announcements;
  int calls = 0;

  @override
  Future<List<Announcement>> getAnnouncements(String token) async {
    calls += 1;
    return announcements;
  }
}

void main() {
  group('accountOverviewProvider', () {
    test(
      'shows cached auth profile while sidecar overview is unavailable',
      () async {
        final accountRepo = _FakeAccountRepository(
          const [],
          overview: null,
          throwOverview: true,
        );
        final container = ProviderContainer(
          overrides: [
            authProvider.overrideWith(_FakeAuthWithProfileNotifier.new),
            accountRepositoryProvider.overrideWithValue(accountRepo),
          ],
        );
        addTearDown(container.dispose);

        final overview = await container.read(accountOverviewProvider.future);

        expect(overview, isNotNull);
        expect(overview!.email, 'cached@example.com');
        expect(overview.planName, '缓存套餐');
        expect(overview.transferUsedBytes, 300);
        expect(overview.transferTotalBytes, 1000);
        expect(overview.transferRemainingBytes, 700);
        expect(overview.onlineCount, 2);
        expect(overview.deviceLimit, 5);
      },
    );
  });

  group('dashboardNoticesProvider', () {
    test('prefers account notices when service notices exist', () async {
      final accountRepo = _FakeAccountRepository(const [
        AccountNotice(
          title: 'Service notice',
          content: 'from account service',
          createdAt: '2026-04-18T01:00:00.000Z',
        ),
      ]);
      final announcementsRepo = _FakeAnnouncementsRepository([
        Announcement(
          id: 1,
          title: 'Fallback notice',
          content: 'from xboard',
          createdAt: 1713402000,
        ),
      ]);

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(_FakeAuthNotifier.new),
          accountRepositoryProvider.overrideWithValue(accountRepo),
          announcementsRepositoryProvider.overrideWithValue(announcementsRepo),
        ],
      );
      addTearDown(container.dispose);

      final notices = await container.read(dashboardNoticesProvider.future);

      expect(notices, hasLength(1));
      expect(notices.first.title, 'Service notice');
      expect(accountRepo.calls, 1);
      expect(
        announcementsRepo.calls,
        0,
        reason: 'dashboard should not hit fallback when service notices exist',
      );
    });

    test(
      'falls back to xboard announcements when account notices are empty',
      () async {
        final accountRepo = _FakeAccountRepository(const []);
        final announcementsRepo = _FakeAnnouncementsRepository([
          Announcement(
            id: 2,
            title: 'Panel notice',
            content: 'from fallback source',
            createdAt: 1713402000,
          ),
        ]);

        final container = ProviderContainer(
          overrides: [
            authProvider.overrideWith(_FakeAuthNotifier.new),
            accountRepositoryProvider.overrideWithValue(accountRepo),
            announcementsRepositoryProvider.overrideWithValue(
              announcementsRepo,
            ),
          ],
        );
        addTearDown(container.dispose);

        final notices = await container.read(dashboardNoticesProvider.future);

        expect(notices, hasLength(1));
        expect(notices.first.title, 'Panel notice');
        final expectedCreatedAt = DateTime.fromMillisecondsSinceEpoch(
          1713402000 * 1000,
        ).toIso8601String();
        expect(notices.first.createdAt, expectedCreatedAt);
        expect(accountRepo.calls, 1);
        expect(announcementsRepo.calls, 1);
      },
    );
  });
}
