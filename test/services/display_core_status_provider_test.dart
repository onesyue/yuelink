import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/core/providers/core_runtime_providers.dart';

void main() {
  group('displayCoreStatusProvider', () {
    test('passes coreStatus through when user has not stopped', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(coreStatusProvider.notifier).set(CoreStatus.running);
      container.read(userStoppedProvider.notifier).set(false);

      expect(container.read(displayCoreStatusProvider), CoreStatus.running);
    });

    test('collapses to stopped when userStoppedProvider is true', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Simulates the resume race: core actually still answering "running"
      // (mihomo helper in flight) while the user has already tapped Stop.
      container.read(coreStatusProvider.notifier).set(CoreStatus.running);
      container.read(userStoppedProvider.notifier).set(true);

      expect(container.read(displayCoreStatusProvider), CoreStatus.stopped);
    });

    test('starting/stopping also masked when user has stopped', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(userStoppedProvider.notifier).set(true);

      container.read(coreStatusProvider.notifier).set(CoreStatus.starting);
      expect(container.read(displayCoreStatusProvider), CoreStatus.stopped);

      container.read(coreStatusProvider.notifier).set(CoreStatus.stopping);
      expect(container.read(displayCoreStatusProvider), CoreStatus.stopped);
    });

    test('flips back when userStoppedProvider clears', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(coreStatusProvider.notifier).set(CoreStatus.running);
      container.read(userStoppedProvider.notifier).set(true);
      expect(container.read(displayCoreStatusProvider), CoreStatus.stopped);

      // Fresh user-initiated start clears userStoppedProvider — UI should
      // immediately reflect the underlying running status.
      container.read(userStoppedProvider.notifier).set(false);
      expect(container.read(displayCoreStatusProvider), CoreStatus.running);
    });
  });
}
