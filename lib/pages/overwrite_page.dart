import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../shared/app_notifier.dart';
import '../services/overwrite_service.dart';

// ── Internal data model ────────────────────────────────────────────────────────

class _OverwriteData {
  String? mode;       // null = no override
  String? mixedPort;  // null = no override
  List<String> rules; // custom rules to prepend
  String extraYaml;   // raw additional YAML for anything else

  _OverwriteData({
    this.mode,
    this.mixedPort,
    List<String>? rules,
    this.extraYaml = '',
  }) : rules = rules ?? [];

  // ── Parse from YAML ────────────────────────────────────────────────────────

  factory _OverwriteData.parse(String yaml) {
    String? mode;
    String? mixedPort;
    final rules = <String>[];

    final modeMatch =
        RegExp(r'^mode:\s*(\S+)', multiLine: true).firstMatch(yaml);
    if (modeMatch != null) mode = modeMatch.group(1);

    final portMatch =
        RegExp(r'^mixed-port:\s*(\d+)', multiLine: true).firstMatch(yaml);
    if (portMatch != null) mixedPort = portMatch.group(1);

    final rulesMatch =
        RegExp(r'^rules:\n((?:[ \t]+-[^\n]*\n?)*)', multiLine: true)
            .firstMatch(yaml);
    if (rulesMatch != null) {
      for (final line in rulesMatch.group(1)!.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.startsWith('- ')) {
          rules.add(trimmed.substring(2).trim());
        }
      }
    }

    // Extra YAML: remove the known keys we structured
    var extra = yaml
        .replaceAll(RegExp(r'^mode:\s*\S+[ \t]*\n?', multiLine: true), '')
        .replaceAll(
            RegExp(r'^mixed-port:\s*\d+[ \t]*\n?', multiLine: true), '')
        .replaceAll(
            RegExp(r'^rules:\n(?:[ \t]+-[^\n]*\n?)*', multiLine: true), '')
        .trim();

    return _OverwriteData(
        mode: mode, mixedPort: mixedPort, rules: rules, extraYaml: extra);
  }

  // ── Serialize to YAML ──────────────────────────────────────────────────────

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
// OverwritePage
// ══════════════════════════════════════════════════════════════════════════════

class OverwritePage extends StatefulWidget {
  const OverwritePage({super.key});

  @override
  State<OverwritePage> createState() => _OverwritePageState();
}

class _OverwritePageState extends State<OverwritePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  final _portCtrl = TextEditingController();
  final _extraCtrl = TextEditingController();

  _OverwriteData _data = _OverwriteData();
  _OverwriteData? _savedData; // snapshot of last saved/loaded state
  bool _loading = true;
  bool _saving = false;

  static const _modes = ['', 'rule', 'global', 'direct'];

  // True when current state differs from last saved state.
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
    _tabCtrl = TabController(length: 3, vsync: this);
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
    _tabCtrl.dispose();
    _portCtrl.dispose();
    _extraCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = S.of(context);

    // Validate port
    final portStr = _portCtrl.text.trim();
    if (portStr.isNotEmpty) {
      final port = int.tryParse(portStr);
      if (port == null || port < 1 || port > 65535) {
        AppNotifier.error(s.overwritePortInvalid);
        return;
      }
    }

    // Sync text field values into data model before saving
    _data.mixedPort = portStr.isEmpty ? null : portStr;
    _data.extraYaml = _extraCtrl.text.trim();

    setState(() => _saving = true);
    try {
      await OverwriteService.save(_data.toYaml());
      if (mounted) {
        setState(() => _savedData = _snapshotCurrent());
      }
      AppNotifier.success(s.savedNextConnect);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Tab 0: Basic ────────────────────────────────────────────────────────────

  Widget _buildBasicTab(S s) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Mode override
        Text(s.overwriteModeLabel,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
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
        const SizedBox(height: 24),

        // Mixed-port override
        Text(s.overwritePortLabel,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextField(
          controller: _portCtrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: s.overwritePortHint,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ],
    );
  }

  // ── Tab 1: Rules ────────────────────────────────────────────────────────────

  Widget _buildRulesTab(S s) {
    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Row(
            children: [
              Expanded(
                child: Text(s.overwriteCustomRulesLabel,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
              TextButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: Text(s.overwriteAddRule),
                onPressed: () => _addRule(s),
              ),
            ],
          ),
        ),

        // Rules list
        Expanded(
          child: _data.rules.isEmpty
              ? Center(
                  child: Text(s.noData,
                      style: const TextStyle(color: Colors.grey)))
              : ReorderableListView.builder(
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
                    return ListTile(
                      key: ValueKey(_data.rules[i] + i.toString()),
                      dense: true,
                      leading: const Icon(Icons.drag_handle, size: 18),
                      title: Text(
                        _data.rules[i],
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 12),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline,
                            size: 18, color: Colors.red),
                        onPressed: () =>
                            setState(() => _data.rules.removeAt(i)),
                      ),
                      onTap: () => _editRule(s, i),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _addRule(S s) async {
    final rule = await _showRuleDialog(s, '');
    if (rule != null && rule.trim().isNotEmpty) {
      setState(() => _data.rules.add(rule.trim()));
    }
  }

  Future<void> _editRule(S s, int index) async {
    final rule = await _showRuleDialog(s, _data.rules[index]);
    if (rule != null) {
      setState(() => _data.rules[index] = rule.trim());
    }
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
              child: Text(s.cancel)),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(ctrl.text),
              child: Text(s.confirm)),
        ],
      ),
    ).whenComplete(ctrl.dispose);
  }

  // ── Tab 2: Advanced ─────────────────────────────────────────────────────────

  Widget _buildAdvancedTab(S s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Text(s.overwriteExtraYamlLabel,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              controller: _extraCtrl,
              expands: true,
              maxLines: null,
              minLines: null,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: s.overwriteHintText,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Discard confirmation ─────────────────────────────────────────────────────

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

  // ── Build ────────────────────────────────────────────────────────────────────

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
      child: Scaffold(
        appBar: AppBar(
          leading: const BackButton(),
          title: Text(s.overwriteTitle),
          actions: [
            if (_saving)
              const Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else
              TextButton(
                onPressed: _save,
                child: Text(s.save),
              ),
          ],
          bottom: TabBar(
            controller: _tabCtrl,
            tabs: [
              Tab(text: s.overwriteTabBasic),
              Tab(text: s.overwriteTabRules),
              Tab(text: s.overwriteTabAdvanced),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                controller: _tabCtrl,
                children: [
                  _buildBasicTab(s),
                  _buildRulesTab(s),
                  _buildAdvancedTab(s),
                ],
              ),
      ),
    );
  }
}
