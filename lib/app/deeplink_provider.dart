import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Pending subscription URL captured from a deep link. The profile page
/// consumes and clears it after opening the add-subscription dialog.
class DeepLinkUrlNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void setUrl(String url) => state = url;

  void clear() => state = null;
}

final deepLinkUrlProvider = NotifierProvider<DeepLinkUrlNotifier, String?>(
  DeepLinkUrlNotifier.new,
);
