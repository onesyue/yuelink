import 'dart:convert';

import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../core/kernel/core_manager.dart';

class RunningConfigPage extends StatefulWidget {
  const RunningConfigPage({super.key});

  @override
  State<RunningConfigPage> createState() => _RunningConfigPageState();
}

class _RunningConfigPageState extends State<RunningConfigPage> {
  Map<String, dynamic>? _config;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final config = await CoreManager.instance.api.getConfig();
      if (mounted) setState(() => _config = config);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(s.runningConfig),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Text(_error!,
                      style: const TextStyle(color: Colors.red)))
              : _config == null
                  ? Center(child: Text(s.noData))
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: _config!.entries.map((e) {
                        final value = e.value;
                        final display = value is Map || value is List
                            ? const JsonEncoder.withIndent('  ').convert(value)
                            : '$value';
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(e.key,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary,
                                  )),
                              const SizedBox(height: 4),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: SelectableText(display,
                                    style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 12)),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
    );
  }
}
