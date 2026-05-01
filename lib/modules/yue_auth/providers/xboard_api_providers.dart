import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../infrastructure/datasources/xboard/index.dart';

/// XBoard HTTP-client providers + the host-fallback configuration that
/// drives them.
///
/// Was inlined in `yue_auth_providers.dart`. Pulled out so widgets that
/// only need the bootstrap-tier API client don't drag AuthNotifier's
/// heavy import surface (CoreManager, RecoveryManager, …) through them.
/// `businessProxyPortProvider` + `businessXboardApiProvider` stay in the
/// auth-providers file because they depend on `authProvider`, which
/// would create a cycle here.

/// Default XBoard panel URL — override via AuthTokenService.saveApiHost().
/// The current primary bootstrap route is the raw panel IP on port 8001.
///
/// Note: this endpoint only speaks plain HTTP on 66.55.76.208:8001;
/// HTTPS fails the TLS handshake, so the scheme here must stay `http://`.
const kDefaultApiHost = 'http://66.55.76.208:8001';

/// Ordered fallback hosts tried when the primary returns a transport-
/// level error (502/503/504 / timeout / socket / TLS).
///
/// Keep the old CDN / business domains as alternates so the app can fail
/// over if the raw IP route is unreachable on a given network.
const kFallbackHosts = <String>[
  'https://d7ccm19ki90mg.cloudfront.net',
  'https://yue.yuebao.website',
  'https://yuetong.app',
];

const kBootstrapTimeout = Duration(seconds: 8);
const kBootstrapRetries = 1;

/// Tracks the current API host — updated on login and restored from
/// storage. AuthNotifier writes to it on host migration; widgets read
/// indirectly via [xboardApiProvider].
///
/// Riverpod 3.0: migrated from `StateProvider<String>` to a [Notifier]
/// because the protected `state` setter prevents external writes. The
/// public [ApiHostNotifier.setHost] method preserves the
/// `ref.read(apiHostProvider.notifier).setHost(...)` call shape that
/// auth flows already use.
class ApiHostNotifier extends Notifier<String> {
  @override
  String build() => kDefaultApiHost;

  /// Replace the current API host. Emits a state change even when the
  /// new value equals the old — keeps AuthNotifier's "force re-resolve"
  /// callsites idempotent.
  void setHost(String host) => state = host;
}

final apiHostProvider =
    NotifierProvider<ApiHostNotifier, String>(ApiHostNotifier.new);

List<String> fallbackHostsFor(String primaryHost) => [
      for (final host in [kDefaultApiHost, ...kFallbackHosts])
        if (host != primaryHost) host,
    ];

/// Bootstrap / auth-flow XBoard client. Always direct (no proxy) so
/// login + subscription recovery never depend on the user's currently
/// selected node being healthy.
final xboardApiProvider = Provider<XBoardApi>((ref) {
  final host = ref.watch(apiHostProvider);
  return XBoardApi(baseUrl: host, fallbackUrls: fallbackHostsFor(host));
});
