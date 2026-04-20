import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'service_manager.dart';
import 'service_models.dart';

final desktopServiceRefreshProvider = StateProvider<int>((ref) => 0);

final desktopServiceInfoProvider =
    FutureProvider<DesktopServiceInfo>((ref) async {
  ref.watch(desktopServiceRefreshProvider);
  return ServiceManager.getInfo();
});
