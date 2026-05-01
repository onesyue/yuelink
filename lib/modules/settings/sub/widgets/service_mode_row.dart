import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/core_provider.dart';
import '../../../../core/service/service_mode_provider.dart';
import '../../../../i18n/app_strings.dart';
import '../../../../shared/app_notifier.dart';
import '../../widgets/primitives.dart';
import '../service_mode_actions.dart';

/// Desktop TUN service row — shown inside the Advanced card when
/// `connectionMode == 'tun'`. Owns its own busy-state so the parent
/// page doesn't need to wire async state for a single control.
///
/// All service work (install / uninstall / update / refresh) goes through
/// `ServiceModeActions`; this row only handles the UI:
///   - busy indicator while an action is in flight
///   - refresh / install / uninstall / update buttons
///   - AppNotifier success/error/warning on result
class ServiceModeRow extends ConsumerStatefulWidget {
  const ServiceModeRow({super.key});

  @override
  ConsumerState<ServiceModeRow> createState() => _ServiceModeRowState();
}

class _ServiceModeRowState extends ConsumerState<ServiceModeRow> {
  bool _busy = false;

  Future<void> _install() async {
    if (_busy) return;
    final s = S.of(context);
    setState(() => _busy = true);
    try {
      final warning = await ServiceModeActions(ref).install();
      if (!mounted) return;
      AppNotifier.success(s.serviceModeInstallOk);
      if (warning != null) AppNotifier.warning(warning);
    } catch (e) {
      if (!mounted) return;
      AppNotifier.error(
        s.serviceModeInstallFailed(e.toString().split('\n').first),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _uninstall(CoreStatus status) async {
    if (_busy) return;
    final s = S.of(context);
    setState(() => _busy = true);
    try {
      await ServiceModeActions(ref).uninstall(status);
      if (!mounted) return;
      AppNotifier.success(s.serviceModeUninstallOk);
    } catch (e) {
      if (!mounted) return;
      AppNotifier.error(
        s.serviceModeUninstallFailed(e.toString().split('\n').first),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _update() async {
    if (_busy) return;
    final s = S.of(context);
    setState(() => _busy = true);
    try {
      final warning = await ServiceModeActions(ref).update();
      if (!mounted) return;
      AppNotifier.success(s.serviceModeUpdateOk);
      if (warning != null) AppNotifier.warning(warning);
    } catch (e) {
      if (!mounted) return;
      AppNotifier.error(
        s.serviceModeUpdateFailed(e.toString().split('\n').first),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final serviceInfo = ref.watch(desktopServiceInfoProvider);
    final status = ref.watch(coreStatusProvider);

    return YLSettingsRow(
      title: s.serviceModeLabel,
      description: ServiceModeActions.describe(s, serviceInfo),
      trailing: _busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              runSpacing: 4,
              children: [
                TextButton(
                  onPressed: () => ServiceModeActions(ref).refresh(),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: Text(
                    s.serviceModeRefresh,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                if (serviceInfo.value?.installed == true) ...[
                  if (serviceInfo.value?.needsReinstall == true)
                    FilledButton(
                      onPressed: _update,
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      child: Text(
                        s.serviceModeUpdate,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  TextButton(
                    onPressed: () => _uninstall(status),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: Text(
                      s.serviceModeUninstall,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ] else
                  FilledButton(
                    onPressed: _install,
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    child: Text(
                      s.serviceModeInstall,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
    );
  }
}
