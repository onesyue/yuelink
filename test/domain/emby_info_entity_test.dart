import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/domain/emby/emby_info_entity.dart';

void main() {
  group('EmbyInfo.toJson / fromJson round-trip', () {
    test('full payload survives round-trip', () {
      final original = EmbyInfo(
        embyUrl: 'https://emby.yue.to',
        autoLoginUrl:
            'https://emby.yue.to/web?userId=u1&accessToken=tok&serverId=s1',
      );
      final round = EmbyInfo.fromJson(original.toJson());
      expect(round.embyUrl, original.embyUrl);
      expect(round.autoLoginUrl, original.autoLoginUrl);
      expect(round.parsedUserId, 'u1');
      expect(round.parsedAccessToken, 'tok');
      expect(round.parsedServerId, 's1');
    });

    test('null fields are omitted from toJson', () {
      // Cache layer only persists what's set so the round-trip stays
      // clean — no sticky `null` keys leaking back as the literal string.
      final empty = EmbyInfo();
      expect(empty.toJson(), isEmpty);

      final partial = EmbyInfo(embyUrl: 'https://x');
      expect(partial.toJson(), {'emby_url': 'https://x'});
    });

    test('hasAccess matches launchUrl semantics', () {
      expect(EmbyInfo().hasAccess, isFalse);
      expect(EmbyInfo(embyUrl: 'https://x').hasAccess, isTrue);
      expect(
        EmbyInfo(autoLoginUrl: 'https://y').hasAccess,
        isTrue,
        reason: 'auto_login_url alone is enough access',
      );
    });

    test('launchUrl prefers auto_login_url when both set', () {
      final info = EmbyInfo(
        embyUrl: 'https://emby.yue.to',
        autoLoginUrl: 'https://emby.yue.to/web?accessToken=tok',
      );
      expect(info.launchUrl, info.autoLoginUrl);
    });

    test('hasNativeAccess requires server + userId + accessToken', () {
      // Missing accessToken
      expect(
        EmbyInfo(autoLoginUrl: 'https://emby.yue.to/web?userId=u1').hasNativeAccess,
        isFalse,
      );
      // Missing userId
      expect(
        EmbyInfo(autoLoginUrl: 'https://emby.yue.to/web?accessToken=tok')
            .hasNativeAccess,
        isFalse,
      );
      // Full
      expect(
        EmbyInfo(
                autoLoginUrl:
                    'https://emby.yue.to/web?userId=u1&accessToken=tok')
            .hasNativeAccess,
        isTrue,
      );
    });

    test('serverBaseUrl strips default port and path', () {
      // Standard scheme/port normalisation — important because the
      // cached value feeds straight into emby_client.dart's host
      // matching, and a stray ":443" would break URL equality.
      expect(
        EmbyInfo(autoLoginUrl: 'https://emby.yue.to:443/web?x=1').serverBaseUrl,
        'https://emby.yue.to',
      );
      expect(
        EmbyInfo(autoLoginUrl: 'http://1.2.3.4:8096/web').serverBaseUrl,
        'http://1.2.3.4:8096',
      );
    });
  });
}
