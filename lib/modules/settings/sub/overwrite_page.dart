import 'package:flutter/material.dart';

import '../../../core/kernel/overwrite_service.dart';
import '../../../i18n/app_strings.dart';
import '../../../shared/app_notifier.dart';
import '../../../shared/widgets/yl_scaffold.dart';
import '../../../theme.dart';

// ── Internal data model ────────────────────────────────────────────────────────

class _OverwriteData {
  String? mode; // null = no override
  String? mixedPort; // null = no override
  List<String> rules; // custom rules to prepend
  String extraYaml; // raw additional YAML for anything else

  _OverwriteData({
    this.mode,
    this.mixedPort,
    List<String>? rules,
    this.extraYaml = '',
  }) : rules = rules ?? [];

  factory _OverwriteData.parse(String yaml) {
    String? mode;
    String? mixedPort;
    final rules = <String>[];

    final modeMatch = RegExp(
      r'^mode:\s*(\S+)',
      multiLine: true,
    ).firstMatch(yaml);
    if (modeMatch != null) mode = modeMatch.group(1);

    final portMatch = RegExp(
      r'^mixed-port:\s*(\d+)',
      multiLine: true,
    ).firstMatch(yaml);
    if (portMatch != null) mixedPort = portMatch.group(1);

    final rulesMatch = RegExp(
      r'^rules:\n((?:[ \t]+-[^\n]*\n?)*)',
      multiLine: true,
    ).firstMatch(yaml);
    if (rulesMatch != null) {
      for (final line in rulesMatch.group(1)!.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.startsWith('- ')) {
          rules.add(trimmed.substring(2).trim());
        }
      }
    }

    final extra = yaml
        .replaceAll(RegExp(r'^mode:\s*\S+[ \t]*\n?', multiLine: true), '')
        .replaceAll(RegExp(r'^mixed-port:\s*\d+[ \t]*\n?', multiLine: true), '')
        .replaceAll(
          RegExp(r'^rules:\n(?:[ \t]+-[^\n]*\n?)*', multiLine: true),
          '',
        )
        .trim();

    return _OverwriteData(
      mode: mode,
      mixedPort: mixedPort,
      rules: rules,
      extraYaml: extra,
    );
  }

  String toYaml() {
    final buf = StringBuffer();
    if (mode != null && mode!.isNotEmpty) {
      buf.writeln('mode: $mode');
    }
    if (mixedPort != null && mixedPort!.isNotEmpty) {
      buf.writeln('mixed-port: $mixedPort');
    }
    if (rules.isNotEmpty) {
      buf.writeln('rules:');
      for (final r in rules) {
        buf.writeln('  - $r');
      }
    }
    if (extraYaml.isNotEmpty) {
      buf.writeln(extraYaml);
    }
    return buf.toString().trim();
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// OverwritePage — single-list IA (rules first, advanced collapsed)
// ══════════════════════════════════════════════════════════════════════════════

class OverwritePage extends StatefulWidget {
  const OverwritePage({super.key});

  @override
  State<OverwritePage> createState() => _OverwritePageState();
}

class _OverwritePageState extends State<OverwritePage> {
  final _portCtrl = TextEditingController();
  final _extraCtrl = TextEditingController();

  _OverwriteData _data = _OverwriteData();
  _OverwriteData? _savedData;
  bool _loading = true;
  bool _saving = false;

  static const _modes = ['', 'rule', 'global', 'direct'];

  bool get _isDirty {
    if (_loading || _savedData == null) return false;
    final sd = _savedData!;
    if (_data.mode != sd.mode) return true;
    if (_portCtrl.text.trim() != (sd.mixedPort ?? '')) return true;
    if (_extraCtrl.text.trim() != sd.extraYaml) return true;
    if (_data.rules.length != sd.rules.length) return true;
    for (var i = 0; i < _data.rules.length; i++) {
      if (_data.rules[i] != sd.rules[i]) return true;
    }
    return false;
  }

  _OverwriteData _snapshotCurrent() => _OverwriteData(
    mode: _data.mode,
    mixedPort: _portCtrl.text.trim().isEmpty ? null : _portCtrl.text.trim(),
    rules: List.from(_data.rules),
    extraYaml: _extraCtrl.text.trim(),
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final content = await OverwriteService.load();
    if (!mounted) return;
    final parsed = _OverwriteData.parse(content);
    setState(() {
      _data = parsed;
      _portCtrl.text = parsed.mixedPort ?? '';
      _extraCtrl.text = parsed.extraYaml;
      _loading = false;
      _savedData = _snapshotCurrent();
    });
  }

  @override
  void dispose() {
    _portCtrl.dispose();
    _extraCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = S.of(context);
    final portStr = _portCtrl.text.trim();
    if (portStr.isNotEmpty) {
      final port = int.tryParse(portStr);
      if (port == null || port < 1 || port > 65535) {
        AppNotifier.error(s.overwritePortInvalid);
        return;
      }
    }
    _data.mixedPort = portStr.isEmpty ? null : portStr;
    _data.extraYaml = _extraCtrl.text.trim();

    setState(() => _saving = true);
    try {
      await OverwriteService.save(_data.toYaml());
      if (mounted) setState(() => _savedData = _snapshotCurrent());
      AppNotifier.success(s.savedNextConnect);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addRule(S s) async {
    final rule = await _showRuleDialog(s, '');
    if (!mounted) return;
    if (rule != null && rule.trim().isNotEmpty) {
      setState(() => _data.rules.add(rule.trim()));
    }
  }

  Future<void> _editRule(S s, int index) async {
    final rule = await _showRuleDialog(s, _data.rules[index]);
    if (!mounted) return;
    if (rule != null) setState(() => _data.rules[index] = rule.trim());
  }

  Future<String?> _showRuleDialog(S s, String initialValue) {
    final ctrl = TextEditingController(text: initialValue);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.overwriteAddRule),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: s.overwriteRuleHint,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (_) => Navigator.of(ctx).pop(ctrl.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text),
            child: Text(s.confirm),
          ),
        ],
      ),
    ).whenComplete(ctrl.dispose);
  }

  Future<bool> _showDiscardDialog(S s) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.unsavedChanges),
        content: Text(s.unsavedChangesBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.stayOnPage),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.discardAndLeave),
          ),
        ],
      ),
    );
    return result == true;
  }

  // ── Body ──────────────────────────────────────────────────────────────────

  Widget _sectionHeader(String text, {bool first = false}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        YLSpacing.md,
        first ? YLSpacing.sm : YLSpacing.lg,
        YLSpacing.md,
        YLSpacing.sm,
      ),
      child: Text(
        text.toUpperCase(),
        style: YLText.caption.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          letterSpacing: 0,
          color: YLColors.zinc500,
        ),
      ),
    );
  }

  BoxDecoration _cardDecoration(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      color: isDark ? YLColors.zinc900 : Colors.white,
      borderRadius: BorderRadius.circular(YLRadius.lg),
      border: Border.all(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.06),
        width: 0.5,
      ),
    );
  }

  Widget _buildRulesCard(S s, BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: _cardDecoration(context),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Header with add button
          Padding(
            padding: const EdgeInsets.fromLTRB(
              YLSpacing.lg,
              YLSpacing.sm,
              YLSpacing.sm,
              YLSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    s.overwriteCustomRulesLabel,
                    style: YLText.caption.copyWith(
                      color: isDark ? YLColors.zinc400 : YLColors.zinc500,
                    ),
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(s.overwriteAddRule),
                  onPressed: () => _addRule(s),
                ),
              ],
            ),
          ),
          if (_data.rules.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: YLSpacing.xxl),
              child: Text(
                s.noData,
                style: YLText.body.copyWith(
                  color: isDark ? YLColors.zinc500 : YLColors.zinc400,
                ),
              ),
            )
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              buildDefaultDragHandles: false,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: _data.rules.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex--;
                  final item = _data.rules.removeAt(oldIndex);
                  _data.rules.insert(newIndex, item);
                });
              },
              itemBuilder: (context, i) {
                return _RuleRow(
                  key: ValueKey(_data.rules[i] + i.toString()),
                  index: i,
                  text: _data.rules[i],
                  isDark: isDark,
                  onTap: () => _editRule(s, i),
                  onDelete: () => setState(() => _data.rules.removeAt(i)),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildExtraYamlCard(S s, BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: _cardDecoration(context),
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.all(YLSpacing.md),
      child: TextField(
        controller: _extraCtrl,
        minLines: 6,
        maxLines: 18,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          color: isDark ? YLColors.zinc200 : YLColors.zinc800,
        ),
        decoration: InputDecoration(
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          fillColor: Colors.transparent,
          filled: false,
          hintText: s.overwriteHintText,
          hintStyle: YLText.body.copyWith(
            fontSize: 13,
            color: YLColors.zinc500,
          ),
          isCollapsed: true,
        ),
      ),
    );
  }

  Widget _buildAdvancedCard(S s, BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: _cardDecoration(context),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Text(
            s.overwriteTabAdvanced,
            style: YLText.body.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : YLColors.zinc900,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              Localizations.localeOf(context).languageCode == 'en'
                  ? 'Override routing mode and mixed port'
                  : '覆盖路由模式与 Mixed 端口（覆盖偏好设置）',
              style: YLText.caption.copyWith(
                color: isDark ? YLColors.zinc400 : YLColors.zinc500,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          tilePadding: const EdgeInsets.symmetric(horizontal: YLSpacing.lg),
          childrenPadding: const EdgeInsets.fromLTRB(
            YLSpacing.lg,
            0,
            YLSpacing.lg,
            YLSpacing.lg,
          ),
          children: [
            // Mode override
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                s.overwriteModeLabel,
                style: YLText.label.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : YLColors.zinc900,
                ),
              ),
            ),
            const SizedBox(height: YLSpacing.sm),
            Wrap(
              spacing: YLSpacing.sm,
              children: [
                for (final mode in _modes)
                  ChoiceChip(
                    label: Text(mode.isEmpty ? s.overwriteModeNone : mode),
                    selected: _data.mode == (mode.isEmpty ? null : mode),
                    onSelected: (_) => setState(() {
                      _data.mode = mode.isEmpty ? null : mode;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: YLSpacing.xl),
            // Mixed-port override
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                s.overwritePortLabel,
                style: YLText.label.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : YLColors.zinc900,
                ),
              ),
            ),
            const SizedBox(height: YLSpacing.sm),
            TextField(
              controller: _portCtrl,
              keyboardType: TextInputType.number,
              style: YLText.monoSmall.copyWith(
                color: isDark ? YLColors.zinc200 : YLColors.zinc800,
              ),
              decoration: InputDecoration(
                hintText: s.overwritePortHint,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        final confirmed = await _showDiscardDialog(s);
        if (confirmed && mounted) nav.pop();
      },
      child: YLLargeTitleScaffold(
        title: s.overwriteTitle,
        maxContentWidth: kYLSecondaryContentWidth,
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(YLSpacing.lg),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton(onPressed: _save, child: Text(s.save)),
        ],
        slivers: [
          if (_loading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                YLSpacing.lg,
                0,
                YLSpacing.lg,
                YLSpacing.xl,
              ),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _sectionHeader(s.overwriteTabRules, first: true),
                  _buildRulesCard(s, context),
                  _sectionHeader(s.overwriteExtraYamlLabel),
                  _buildExtraYamlCard(s, context),
                  const SizedBox(height: YLSpacing.lg),
                  _buildAdvancedCard(s, context),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({
    super.key,
    required this.index,
    required this.text,
    required this.isDark,
    required this.onTap,
    required this.onDelete,
  });

  final int index;
  final String text;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: YLSpacing.md,
            vertical: YLSpacing.sm,
          ),
          child: Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: Icon(
                  Icons.drag_handle,
                  size: 18,
                  color: isDark ? YLColors.zinc500 : YLColors.zinc400,
                ),
              ),
              const SizedBox(width: YLSpacing.sm),
              Expanded(
                child: Text(
                  text,
                  style: YLText.monoSmall.copyWith(
                    color: isDark ? YLColors.zinc200 : YLColors.zinc800,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: S.of(context).delete,
                icon: const Icon(
                  Icons.delete_rounded,
                  size: 18,
                  color: YLColors.error,
                ),
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
