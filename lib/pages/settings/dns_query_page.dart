import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../core/kernel/core_manager.dart';

class DnsQueryPage extends StatefulWidget {
  const DnsQueryPage({super.key});

  @override
  State<DnsQueryPage> createState() => _DnsQueryPageState();
}

class _DnsQueryPageState extends State<DnsQueryPage> {
  final _controller = TextEditingController();
  String _queryType = 'A';
  Map<String, dynamic>? _result;
  bool _loading = false;
  String? _error;

  static const _queryTypes = [
    'A', 'AAAA', 'CNAME', 'MX', 'TXT', 'NS', 'SOA'
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _query() async {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      final result =
          await CoreManager.instance.api.queryDns(name, type: _queryType);
      if (mounted) setState(() => _result = result);
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
      appBar: AppBar(leading: const BackButton(), title: Text(s.dnsQuery)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: s.domainHint,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                    onSubmitted: (_) => _query(),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _queryType,
                  items: _queryTypes
                      .map((t) =>
                          DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _queryType = v);
                  },
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _loading ? null : _query,
                  child: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text(s.query),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_error!,
                    style:
                        const TextStyle(color: Colors.red, fontSize: 13)),
              ),
            if (_result != null)
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: _buildResult(s),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildResult(S s) {
    final status = _result!['Status'] as int? ?? -1;
    final answers = _result!['Answer'] as List? ?? [];

    return ListView(
      children: [
        Row(
          children: [
            Icon(
              status == 0 ? Icons.check_circle : Icons.error,
              size: 18,
              color: status == 0 ? Colors.green : Colors.red,
            ),
            const SizedBox(width: 8),
            Text(
              status == 0 ? 'NOERROR' : 'Status: $status',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: status == 0 ? Colors.green : Colors.red,
              ),
            ),
          ],
        ),
        const Divider(height: 24),
        if (answers.isEmpty)
          Text(s.noRecords, style: const TextStyle(color: Colors.grey))
        else
          ...answers.map((a) {
            final answer = a as Map<String, dynamic>;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color:
                          Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${answer['type'] ?? _queryType}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SelectableText('${answer['data'] ?? ''}',
                            style: const TextStyle(
                                fontFamily: 'monospace', fontSize: 13)),
                        if (answer['TTL'] != null)
                          Text('TTL: ${answer['TTL']}',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant)),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }
}
