import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/auth_token_service.dart';
import '../../infrastructure/datasources/xboard_api.dart';
import '../../modules/yue_auth/providers/yue_auth_providers.dart';

const _kDefaultApiHost = 'https://d7ccm19ki90mg.cloudfront.net';

/// Fetches the current user's Emby service info.
/// Returns null when not logged in or no Emby access.
final embyProvider = FutureProvider<EmbyInfo?>((ref) async {
  final token = ref.watch(authProvider).token;
  if (token == null) return null;

  final host = await AuthTokenService.instance.getApiHost() ?? _kDefaultApiHost;
  final api = XBoardApi(baseUrl: host);
  try {
    return await api.getEmby(token);
  } on XBoardApiException catch (e) {
    if (e.statusCode == 401 || e.statusCode == 403) {
      ref.read(authProvider.notifier).handleUnauthenticated();
      return null;
    }
    rethrow;
  }
});
