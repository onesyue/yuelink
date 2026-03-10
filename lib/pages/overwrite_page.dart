import 'package:flutter/material.dart';

import '../services/overwrite_service.dart';

class OverwritePage extends StatefulWidget {
  const OverwritePage({super.key});

  @override
  State<OverwritePage> createState() => _OverwritePageState();
}

class _OverwritePageState extends State<OverwritePage> {
  final _controller = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final content = await OverwriteService.load();
    if (mounted) {
      _controller.text = content;
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await OverwriteService.save(_controller.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已保存，下次连接时生效')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('配置覆写'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child:
                  SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            TextButton(
              onPressed: _save,
              child: const Text('保存'),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Help banner
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('覆写规则',
                          style: Theme.of(context)
                              .textTheme
                              .labelMedium
                              ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context).colorScheme.primary)),
                      const SizedBox(height: 4),
                      Text(
                        '• 标量键（mode, log-level 等）会替换订阅中的对应值\n'
                        '• rules 列表会插入到订阅规则之前\n'
                        '• proxies / proxy-groups 列表会追加到订阅之后',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: TextField(
                      controller: _controller,
                      expands: true,
                      maxLines: null,
                      minLines: null,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 13),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: '# 示例:\n'
                            '# mode: rule\n'
                            '# rules:\n'
                            '#   - DOMAIN-SUFFIX,example.com,DIRECT',
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
