import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/core_provider.dart';
import '../services/unlock_test_service.dart';

class UnlockTestPage extends ConsumerWidget {
  const UnlockTestPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(unlockResultsProvider);
    final testing = ref.watch(unlockTestingProvider);
    final actions = ref.read(unlockTestActionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('节点解锁检测'),
        actions: [
          if (testing)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.play_arrow_rounded),
              tooltip: '开始检测',
              onPressed: actions.runAll,
            ),
        ],
      ),
      body: results.isEmpty && !testing
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock_open_outlined,
                      size: 64,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withValues(alpha: 0.4)),
                  const SizedBox(height: 16),
                  Text('点击右上角按钮开始检测',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: UnlockTestService.services.length,
              itemBuilder: (context, i) {
                final svc = UnlockTestService.services[i];
                final result = results[svc.id];
                return _ServiceTile(service: svc, result: result);
              },
            ),
    );
  }
}

class _ServiceTile extends StatelessWidget {
  final UnlockService service;
  final UnlockResult? result;

  const _ServiceTile({required this.service, this.result});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Text(service.icon,
            style: const TextStyle(fontSize: 24)),
        title: Text(service.name,
            style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text(service.testUrl,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
        trailing: result == null
            ? const Icon(Icons.remove, color: Colors.grey)
            : _StatusWidget(result: result!),
      ),
    );
  }
}

class _StatusWidget extends StatelessWidget {
  final UnlockResult result;
  const _StatusWidget({required this.result});

  @override
  Widget build(BuildContext context) {
    return switch (result.status) {
      UnlockStatus.testing => const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2)),
      UnlockStatus.unlocked => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 18),
                const SizedBox(width: 4),
                Text('可用',
                    style: const TextStyle(
                        color: Colors.green, fontWeight: FontWeight.w500)),
              ],
            ),
            if (result.latencyMs != null)
              Text('${result.latencyMs}ms',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      UnlockStatus.blocked => const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.block, color: Colors.red, size: 18),
            SizedBox(width: 4),
            Text('被封锁',
                style: TextStyle(
                    color: Colors.red, fontWeight: FontWeight.w500)),
          ],
        ),
      UnlockStatus.timeout => const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timer_off_outlined, color: Colors.orange, size: 18),
            SizedBox(width: 4),
            Text('超时',
                style: TextStyle(
                    color: Colors.orange, fontWeight: FontWeight.w500)),
          ],
        ),
      UnlockStatus.error => const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: Colors.grey, size: 18),
            SizedBox(width: 4),
            Text('错误', style: TextStyle(color: Colors.grey)),
          ],
        ),
    };
  }
}
