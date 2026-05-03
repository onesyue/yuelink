import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/core/kernel/core_manager.dart';
import 'package:yuelink/core/providers/core_provider.dart';
import 'package:yuelink/modules/logs/providers/logs_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    CoreManager.resetForTesting();
    final manager = CoreManager.instance;
    manager.configure(mode: CoreMode.mock);
    manager.core.init('/tmp/yuelink_log_provider_test');
    manager.core.start('mixed-port: 7890');
  });

  tearDown(() {
    CoreManager.instance.core.shutdown();
    CoreManager.resetForTesting();
  });

  test('starts listening when built after core is already running', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(coreStatusProvider.notifier).set(CoreStatus.running);
    expect(container.read(logEntriesProvider), isEmpty);

    await Future<void>.delayed(const Duration(milliseconds: 2300));

    expect(container.read(logEntriesProvider), isNotEmpty);
  });
}
