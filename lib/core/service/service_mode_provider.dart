import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'service_manager.dart';
import 'service_models.dart';

/// Monotonic refresh counter — bumped by [ServiceModeActions] after every
/// install/uninstall/update so [desktopServiceInfoProvider] re-reads the
/// helper status. Riverpod 3.0: migrated from `StateProvider<int>` to a
/// [Notifier]; the public [DesktopServiceRefreshNotifier.bump] replaces
/// the previous `state++` callsite.
class DesktopServiceRefreshNotifier extends Notifier<int> {
  @override
  int build() => 0;

  /// Increment the counter, forcing dependents to re-fetch.
  void bump() => state = state + 1;
}

final desktopServiceRefreshProvider =
    NotifierProvider<DesktopServiceRefreshNotifier, int>(
  DesktopServiceRefreshNotifier.new,
);

final desktopServiceInfoProvider =
    FutureProvider<DesktopServiceInfo>((ref) async {
  ref.watch(desktopServiceRefreshProvider);
  return ServiceManager.getInfo();
});
