import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../shared/app_notifier.dart';
import '../core/storage/settings_service.dart';
import '../services/webdav_service.dart';
import '../theme.dart';

class WebDavPage extends StatefulWidget {
  const WebDavPage({super.key});

  @override
  State<WebDavPage> createState() => _WebDavPageState();
}

class _WebDavPageState extends State<WebDavPage> {
  final _urlCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cfg = await SettingsService.getWebDavConfig();
    if (mounted) {
      _urlCtrl.text = cfg['url'] ?? '';
      _userCtrl.text = cfg['username'] ?? '';
      _passCtrl.text = cfg['password'] ?? '';
    }
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveConfig() async {
    await SettingsService.setWebDavConfig(
      url: _urlCtrl.text.trim(),
      username: _userCtrl.text.trim(),
      password: _passCtrl.text,
    );
  }

  Future<void> _testConnection() async {
    final s = S.of(context);
    await _saveConfig();
    setState(() => _loading = true);
    try {
      final ok = await WebDavService.instance.testConnection();
      if (ok) {
        AppNotifier.success(s.connectionSuccess);
      } else {
        AppNotifier.error(s.connectionFailed);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _upload() async {
    final s = S.of(context);
    await _saveConfig();
    setState(() => _loading = true);
    try {
      await WebDavService.instance.upload();
      AppNotifier.success(s.uploadSuccess);
    } catch (e) {
      AppNotifier.error(s.uploadFailed(e.toString()));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _download() async {
    final s = S.of(context);
    await _saveConfig();
    setState(() => _loading = true);
    try {
      await WebDavService.instance.download();
      AppNotifier.success(s.downloadSuccess);
    } catch (e) {
      AppNotifier.error(s.downloadFailed(e.toString()));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(s.sectionWebDav),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            children: [
              Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: isDark ? YLColors.zinc800 : Colors.white,
                  borderRadius: BorderRadius.circular(YLRadius.xl),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.08),
                    width: 0.5,
                  ),
                  boxShadow: YLShadow.card(context),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _urlCtrl,
                        decoration: InputDecoration(
                          labelText: s.webdavUrl,
                          hintText: 'https://example.com/dav',
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _userCtrl,
                        decoration: InputDecoration(
                          labelText: s.username,
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _passCtrl,
                        obscureText: _obscure,
                        decoration: InputDecoration(
                          labelText: s.password,
                          isDense: true,
                          suffixIcon: IconButton(
                            icon: Icon(
                                _obscure
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                size: 18),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.check_circle_outline,
                                  size: 16),
                              label: Text(s.testConnection),
                              onPressed: _loading ? null : _testConnection,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.cloud_upload_outlined,
                                  size: 16),
                              label: Text(s.upload),
                              onPressed: _loading ? null : _upload,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.icon(
                              icon: const Icon(Icons.cloud_download_outlined,
                                  size: 16),
                              label: Text(s.download),
                              onPressed: _loading ? null : _download,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
