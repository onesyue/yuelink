import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/core/kernel/config/dns_policy_catalog.dart';

/// Catalog-internal invariants. These guard the "single source of truth"
/// contract — every other transformer reads from this catalog, so any
/// drift here cascades into runtime behaviour.
void main() {
  group('DnsPolicyCatalog invariants', () {
    test('overseasDohServers contains both Cloudflare and Google', () {
      expect(
        DnsPolicyCatalog.overseasDohServers,
        containsAll([
          'https://cloudflare-dns.com/dns-query',
          'https://dns.google/dns-query',
        ]),
      );
    });

    test('cnDnsServers contains both AliDNS and Tencent doh.pub', () {
      expect(
        DnsPolicyCatalog.cnDnsServers,
        containsAll([
          'https://dns.alidns.com/dns-query',
          'https://doh.pub/dns-query',
        ]),
      );
    });

    test('secureDnsDomains covers all 5 ECH/DoH probe targets', () {
      expect(
        DnsPolicyCatalog.secureDnsDomains,
        equals([
          'cloudflare-dns.com',
          'chrome.cloudflare-dns.com',
          'mozilla.cloudflare-dns.com',
          'dns.google',
          'cloudflare-ech.com',
        ]),
      );
    });

    test('aiDomains has no duplicates', () {
      final set = DnsPolicyCatalog.aiDomains.toSet();
      expect(
        set.length,
        DnsPolicyCatalog.aiDomains.length,
        reason: 'duplicate AI domain in catalog',
      );
    });

    test('aiDomains all start with "+." (suffix-match form)', () {
      for (final d in DnsPolicyCatalog.aiDomains) {
        expect(
          d.startsWith('+.'),
          isTrue,
          reason: 'AI domain "$d" should be a suffix-match (+.) entry',
        );
      }
    });

    test('aiDomains covers the canonical big-name AI providers', () {
      // Smoke check — these are the non-negotiables. Adding new ones is
      // fine; removing any of these means a regression.
      const canonical = [
        '+.openai.com',
        '+.chatgpt.com',
        '+.anthropic.com',
        '+.claude.ai',
        '+.gemini.google.com',
        '+.cursor.com',
        '+.copilot.microsoft.com',
        '+.x.ai',
        '+.grok.com',
        '+.perplexity.ai',
        '+.huggingface.co',
        '+.midjourney.com',
      ];
      expect(DnsPolicyCatalog.aiDomains, containsAll(canonical));
    });

    test('chinaCriticalDomains covers banking, carriers, AD', () {
      // Smoke check — major CN App auth domains must be present.
      expect(
        DnsPolicyCatalog.chinaCriticalDomains,
        containsAll([
          '+.cmpassport.com', // 中国移动一证通
          '+.cmbchina.com', // 招商银行
          '+.icbc.com.cn', // 工商银行
          '+.alipay.com', // 支付宝
          'PDC._msDCS.*.*', // Active Directory
        ]),
      );
    });

    test('rulesConnectivityDomains excludes google/gstatic/msft', () {
      final excluded = ['google', 'gstatic', 'msft'];
      for (final d in DnsPolicyCatalog.rulesConnectivityDomains()) {
        for (final tag in excluded) {
          expect(
            d.contains(tag),
            isFalse,
            reason:
                'rulesConnectivityDomains should not include "$d" (matches '
                '"$tag" — those domains are typically DIRECT via geosite:cn '
                'and rule-injecting them is just noise)',
          );
        }
      }
    });

    test('rulesConnectivityDomains is a subset of connectivityDomains', () {
      expect(
        DnsPolicyCatalog.connectivityDomains,
        containsAll(DnsPolicyCatalog.rulesConnectivityDomains()),
      );
    });

    test('connectivityDomains covers 13 OEM brands', () {
      final allLower = DnsPolicyCatalog.connectivityDomains
          .map((d) => d.toLowerCase())
          .join(' ');
      const oems = [
        'samsung',
        'hicloud', // Huawei
        'xiaomi',
        'coloros', // OPPO/Realme
        'hihonor', // Honor
        'meizu',
        'vivo',
        'apple',
        'gstatic', // Google/Android
        'msft', // Microsoft
      ];
      for (final oem in oems) {
        expect(
          allLower.contains(oem),
          isTrue,
          reason: 'connectivityDomains missing OEM marker "$oem"',
        );
      }
    });
  });
}
