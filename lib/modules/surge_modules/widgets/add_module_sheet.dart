import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_strings.dart';
import '../../../theme.dart';
import '../domain/module_entity.dart';
import '../providers/module_provider.dart';

/// Bottom sheet for adding a new module by URL.
class AddModuleSheet extends ConsumerStatefulWidget {
  const AddModuleSheet({super.key});

  @override
  ConsumerState<AddModuleSheet> createState() => _AddModuleSheetState();
}

class _AddModuleSheetState extends ConsumerState<AddModuleSheet> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  bool _loading = false;
  String? _error;
  ModuleRecord? _addedModule;

  @override
  void initState() {
    super.initState();
    // Auto-focus the text field when sheet opens
    Future.microtask(() => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool _isValidUrl(String url) {
    try {
      final uri = Uri.parse(url.trim());
      return uri.isAbsolute && (uri.scheme == 'http' || uri.scheme == 'https');
    } catch (_) {
      return false;
    }
  }

  Future<void> _add() async {
    final url = _controller.text.trim();
    if (!_isValidUrl(url)) {
      setState(() {
        _error = 'Please enter a valid http/https URL';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _addedModule = null;
    });

    try {
      final record = await ref.read(moduleProvider.notifier).addModule(url);
      if (mounted) {
        setState(() {
          _loading = false;
          _addedModule = record;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark ? YLColors.primaryDark : YLColors.primary;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? YLColors.zinc700 : YLColors.zinc300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Title
          Text(
            s.modulesLabel,
            style: YLText.titleLarge.copyWith(
              color: primaryColor,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),

          // URL input
          TextField(
            controller: _controller,
            focusNode: _focusNode,
            enabled: !_loading && _addedModule == null,
            decoration: InputDecoration(
              hintText: s.moduleAddUrl,
              prefixIcon: const Icon(Icons.link, size: 20),
              errorText: _error,
            ),
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _add(),
            autofocus: true,
          ),
          const SizedBox(height: 12),

          // Success state
          if (_addedModule != null) ...[
            _SuccessPanel(module: _addedModule!),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(_addedModule),
              child: const Text('Done'),
            ),
          ] else ...[
            // Add button
            FilledButton(
              onPressed: _loading ? null : _add,
              child: _loading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(s.moduleAdding.isEmpty ? 'Add' : 'Add'),
            ),
          ],
        ],
      ),
    );
  }
}

class _SuccessPanel extends StatelessWidget {
  final ModuleRecord module;

  const _SuccessPanel({required this.module});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final s = S.of(context);

    final ruleCount = module.rules.length;
    final unsupported = module.unsupportedCounts.total;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark
            ? YLColors.connected.withValues(alpha: 0.12)
            : YLColors.connected.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(YLRadius.lg),
        border: Border.all(
          color: YLColors.connected.withValues(alpha: 0.3),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_outline,
                  size: 16, color: YLColors.connected),
              const SizedBox(width: 6),
              Text(
                s.moduleAddSuccess,
                style: YLText.body.copyWith(
                  color: YLColors.connected,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            module.name,
            style: YLText.body.copyWith(
              color: isDark ? YLColors.zinc100 : YLColors.zinc800,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            unsupported > 0
                ? '\u2713 $ruleCount ${s.moduleRuleCount.toLowerCase()}, '
                    '\u26a0 $unsupported items not active'
                : '\u2713 $ruleCount ${s.moduleRuleCount.toLowerCase()}',
            style: YLText.caption.copyWith(color: YLColors.zinc500),
          ),
        ],
      ),
    );
  }
}
