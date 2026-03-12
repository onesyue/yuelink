import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants.dart';
import '../../l10n/app_strings.dart';
import '../../providers/core_provider.dart';
import '../../providers/split_tunnel_provider.dart';
import '../../shared/app_notifier.dart';
import '../../core/kernel/core_manager.dart';
import '../../core/kernel/geodata_service.dart';
import '../../core/storage/settings_service.dart';
import '../../core/platform/vpn_service.dart';
import '../../modules/nodes/providers/nodes_providers.dart';
import 'startup_report_page.dart';
import '../../services/update_checker.dart';
import '../../theme.dart';
import 'sub/connections_sub_page.dart';
import 'sub/logs_sub_page.dart';
import 'sub/overwrite_sub_page.dart';
import 'sub/proxy_providers_sub_page.dart';
import 'sub/webdav_sub_page.dart';

// ── Settings-level providers ─────────────────────────────────────────────────

final themeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);
final languageProvider = StateProvider<String>((ref) => 'zh');

/// Desktop: close window behavior. Values: 'tray' (default) | 'exit'.
final closeBehaviorProvider = StateProvider<String>((ref) => 'tray');

/// Desktop: toggle connection hotkey stored as "ctrl+alt+c" lowercase.
final toggleHotkeyProvider = StateProvider<String>((ref) => 'ctrl+alt+c');

// ── Hotkey utilities ──────────────────────────────────────────────────────────

/// Parse stored hotkey string to a [HotKey].
HotKey parseStoredHotkey(String stored) {
  final parts = stored.toLowerCase().split('+');
  final modifiers = <HotKeyModifier>[];
  LogicalKeyboardKey key = LogicalKeyboardKey.keyC;
  for (final p in parts) {
    switch (p) {
      case 'ctrl':
      case 'control':
        modifiers.add(HotKeyModifier.control);
      case 'shift':
        modifiers.add(HotKeyModifier.shift);
      case 'alt':
        modifiers.add(HotKeyModifier.alt);
      case 'meta':
      case 'cmd':
      case 'win':
        modifiers.add(HotKeyModifier.meta);
      default:
        key = _logicalKeyFromLabel(p);
    }
  }
  return HotKey(key: key, modifiers: modifiers, scope: HotKeyScope.system);
}

/// Format stored hotkey string to display label, e.g. "ctrl+alt+c" → "Ctrl+Alt+C".
String displayHotkey(String stored) {
  return stored.split('+').map((p) {
    switch (p.toLowerCase()) {
      case 'ctrl':
      case 'control':
        return 'Ctrl';
      case 'shift':
        return 'Shift';
      case 'alt':
        return 'Alt';
      case 'meta':
      case 'cmd':
      case 'win':
        return Platform.isMacOS ? '⌘' : 'Win';
      default:
        return p.toUpperCase();
    }
  }).join('+');
}

bool _isModifierKey(LogicalKeyboardKey key) {
  final modifiers = {
    LogicalKeyboardKey.control,
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.shift,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.alt,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.meta,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
    LogicalKeyboardKey.capsLock,
    LogicalKeyboardKey.fn,
  };
  return modifiers.contains(key);
}

LogicalKeyboardKey _logicalKeyFromLabel(String label) {
  const map = {
    'a': LogicalKeyboardKey.keyA, 'b': LogicalKeyboardKey.keyB,
    'c': LogicalKeyboardKey.keyC, 'd': LogicalKeyboardKey.keyD,
    'e': LogicalKeyboardKey.keyE, 'f': LogicalKeyboardKey.keyF,
    'g': LogicalKeyboardKey.keyG, 'h': LogicalKeyboardKey.keyH,
    'i': LogicalKeyboardKey.keyI, 'j': LogicalKeyboardKey.keyJ,
    'k': LogicalKeyboardKey.keyK, 'l': LogicalKeyboardKey.keyL,
    'm': LogicalKeyboardKey.keyM, 'n': LogicalKeyboardKey.keyN,
    'o': LogicalKeyboardKey.keyO, 'p': LogicalKeyboardKey.keyP,
    'q': LogicalKeyboardKey.keyQ, 'r': LogicalKeyboardKey.keyR,
    's': LogicalKeyboardKey.keyS, 't': LogicalKeyboardKey.keyT,
    'u': LogicalKeyboardKey.keyU, 'v': LogicalKeyboardKey.keyV,
    'w': LogicalKeyboardKey.keyW, 'x': LogicalKeyboardKey.keyX,
    'y': LogicalKeyboardKey.keyY, 'z': LogicalKeyboardKey.keyZ,
    '0': LogicalKeyboardKey.digit0, '1': LogicalKeyboardKey.digit1,
    '2': LogicalKeyboardKey.digit2, '3': LogicalKeyboardKey.digit3,
    '4': LogicalKeyboardKey.digit4, '5': LogicalKeyboardKey.digit5,
    '6': LogicalKeyboardKey.digit6, '7': LogicalKeyboardKey.digit7,
    '8': LogicalKeyboardKey.digit8, '9': LogicalKeyboardKey.digit9,
  };
  return map[label.toLowerCase()] ?? LogicalKeyboardKey.keyC;
}

// ─────────────────────────────────────────────────────────────────────────────

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _launchAtStartup = false;
  UpdateInfo? _pendingUpdate;
  bool _checkingUpdate = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final startup = await SettingsService.getLaunchAtStartup();
    if (mounted) {
      setState(() {
        _launchAtStartup = startup;
      });
    }
    _checkForUpdate();
  }

  Future<void> _checkForUpdate() async {
    final info = await UpdateChecker.instance.check();
    if (mounted && info != null) {
      setState(() => _pendingUpdate = info);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = ref.watch(themeProvider);
    final language = ref.watch(languageProvider);
    final autoConnect = ref.watch(autoConnectProvider);
    final connectionMode = ref.watch(connectionModeProvider);
    final logLevel = ref.watch(logLevelProvider);
    final systemProxyOnConnect = ref.watch(systemProxyOnConnectProvider);
    final status = ref.watch(coreStatusProvider);
    final routingMode = ref.watch(routingModeProvider);
    final isDesktop = Platform.isMacOS || Platform.isWindows || Platform.isLinux;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dividerColor = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.06);

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Top bar ──────────────────────────────────────────────
          Padding(
            padding: EdgeInsets.fromLTRB(32, MediaQuery.of(context).padding.top + 16, 32, 20),
            child: Text(
              s.navSettings,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.5,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
          ),
          Container(
            height: 0.5,
            color: dividerColor,
          ),

          // ── Content ──────────────────────────────────────────────
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                  children: [

              // ══ 1. General ════════════════════════════════════════
              _SectionTitle(s.sectionAppearance),
              _SettingsCard(
                child: Column(
                  children: [
                    // Theme
                    YLInfoRow(
                      label: s.themeLabel,
                      trailing: SizedBox(
                        width: 240,
                        child: SegmentedButton<ThemeMode>(
                          showSelectedIcon: false,
                          style: SegmentedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            textStyle: const TextStyle(fontSize: 12),
                          ),
                          segments: [
                            ButtonSegment(
                                value: ThemeMode.system,
                                label: Text(s.themeSystem)),
                            ButtonSegment(
                                value: ThemeMode.light,
                                label: Text(s.themeLight)),
                            ButtonSegment(
                                value: ThemeMode.dark,
                                label: Text(s.themeDark)),
                          ],
                          selected: {theme},
                          onSelectionChanged: (v) {
                            ref.read(themeProvider.notifier).state = v.first;
                            SettingsService.setThemeMode(v.first);
                          },
                        ),
                      ),
                    ),
                    Divider(height: 1, thickness: 0.5, color: dividerColor),
                    // Language
                    YLInfoRow(
                      label: s.sectionLanguage,
                      trailing: SizedBox(
                        width: 160,
                        child: SegmentedButton<String>(
                          showSelectedIcon: false,
                          style: SegmentedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            textStyle: const TextStyle(fontSize: 12),
                          ),
                          segments: [
                            ButtonSegment(
                                value: 'zh', label: Text(s.languageChinese)),
                            ButtonSegment(
                                value: 'en', label: Text(s.languageEnglish)),
                          ],
                          selected: {language},
                          onSelectionChanged: (v) async {
                            ref.read(languageProvider.notifier).state = v.first;
                            await SettingsService.setLanguage(v.first);
                          },
                        ),
                      ),
                    ),
                    Divider(height: 1, thickness: 0.5, color: dividerColor),
                    // Auto connect
                    YLSettingsRow(
                      title: s.autoConnect,
                      trailing: Switch(
                        value: autoConnect,
                        onChanged: (v) async {
                          ref.read(autoConnectProvider.notifier).state = v;
                          await SettingsService.setAutoConnect(v);
                        },
                      ),
                    ),
                    if (isDesktop) ...[
                      Divider(height: 1, thickness: 0.5, color: dividerColor),
                      YLSettingsRow(
                        title: s.launchAtStartupLabel,
                        description: s.launchAtStartupSub,
                        trailing: Switch(
                          value: _launchAtStartup,
                          onChanged: (v) async {
                            setState(() => _launchAtStartup = v);
                            await SettingsService.setLaunchAtStartup(v);
                            if (v) {
                              await launchAtStartup.enable();
                            } else {
                              await launchAtStartup.disable();
                            }
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // ══ 1b. Desktop (desktop-only) ════════════════════════
              if (isDesktop) ...[
                _SectionTitle(s.sectionDesktop),
                _SettingsCard(
                  child: Column(
                    children: [
                      // Close behavior: tray mode only meaningful on macOS/Windows
                      if (!Platform.isLinux) ...[
                        _CloseBehaviorRow(),
                        Divider(height: 1, thickness: 0.5, color: dividerColor),
                      ],
                      _HotkeyRow(),
                    ],
                  ),
                ),
              ],

              // ══ 2. Connection ═════════════════════════════════════
              _SectionTitle(s.sectionConnection),
              _SettingsCard(
                child: Column(
                  children: [
                    // Routing mode — all platforms
                    YLInfoRow(
                      label: s.routingModeSetting,
                      trailing: SizedBox(
                        width: 200,
                        child: SegmentedButton<String>(
                          showSelectedIcon: false,
                          style: SegmentedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            textStyle: const TextStyle(fontSize: 12),
                          ),
                          segments: [
                            ButtonSegment(
                                value: 'rule',
                                label: Text(s.routeModeRule)),
                            ButtonSegment(
                                value: 'global',
                                label: Text(s.routeModeGlobal)),
                            ButtonSegment(
                                value: 'direct',
                                label: Text(s.routeModeDirect)),
                          ],
                          selected: {routingMode},
                          onSelectionChanged: (v) async {
                            final mode = v.first;
                            ref.read(routingModeProvider.notifier).state = mode;
                            await SettingsService.setRoutingMode(mode);
                            if (status == CoreStatus.running) {
                              try {
                                await CoreManager.instance.api.setRoutingMode(mode);
                              } catch (_) {}
                            }
                          },
                        ),
                      ),
                    ),
                    if (isDesktop) ...[
                      Divider(height: 1, thickness: 0.5, color: dividerColor),
                      YLInfoRow(
                        label: s.connectionMode,
                        trailing: DropdownButton<String>(
                          value: connectionMode,
                          underline: const SizedBox.shrink(),
                          style: YLText.body.copyWith(
                            color: isDark ? YLColors.zinc200 : YLColors.zinc700,
                          ),
                          dropdownColor: isDark ? YLColors.zinc800 : Colors.white,
                          items: [
                            DropdownMenuItem(
                                value: 'tun', child: Text(s.modeTun)),
                            DropdownMenuItem(
                                value: 'systemProxy',
                                child: Text(s.modeSystemProxy)),
                          ],
                          onChanged: (v) async {
                            if (v == null) return;
                            ref.read(connectionModeProvider.notifier).state = v;
                            await SettingsService.setConnectionMode(v);
                          },
                        ),
                      ),
                      Divider(height: 1, thickness: 0.5, color: dividerColor),
                      if (Platform.isLinux)
                        const _LinuxProxyNoticeRow()
                      else
                        YLSettingsRow(
                          title: s.setSystemProxyOnConnect,
                          description: s.setSystemProxyOnConnectSub,
                          trailing: Switch(
                            value: systemProxyOnConnect,
                            onChanged: (v) async {
                              ref
                                  .read(systemProxyOnConnectProvider.notifier)
                                  .state = v;
                              await SettingsService.setSystemProxyOnConnect(v);
                            },
                          ),
                        ),
                    ],
                    // Test URL — all platforms
                    Divider(height: 1, thickness: 0.5, color: dividerColor),
                    _TestUrlRow(),
                  ],
                ),
              ),

              // ══ 3. Subscription & Config ══════════════════════════
              _SectionTitle(s.sectionSubscription),
              _SettingsCard(
                child: Column(
                  children: [
                    YLInfoRow(
                      label: s.configOverwrite,
                      trailing: const Icon(Icons.chevron_right, size: 18,
                          color: YLColors.zinc400),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const OverwriteSubPage()),
                      ),
                    ),
                    Divider(height: 1, thickness: 0.5, color: dividerColor),
                    YLInfoRow(
                      label: s.proxyProviderTitle,
                      trailing: const Icon(Icons.chevron_right, size: 18,
                          color: YLColors.zinc400),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ProxyProvidersSubPage()),
                      ),
                    ),
                    Divider(height: 1, thickness: 0.5, color: dividerColor),
                    YLInfoRow(
                      label: 'WebDAV',
                      trailing: const Icon(Icons.chevron_right,
                          size: 18, color: YLColors.zinc400),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const WebDavSubPage()),
                      ),
                    ),
                  ],
                ),
              ),

              // ══ 3b. Network ═══════════════════════════════════════
              _SectionTitle(s.sectionNetwork),
              _SettingsCard(child: _GeoDataRow()),

              // ══ 4. Core ═══════════════════════════════════════════
              _SectionTitle(s.sectionCore),
              _SettingsCard(
                child: Column(
                  children: [
                    YLInfoRow(
                      label: s.coreStatus,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          YLStatusDot(
                            color: status == CoreStatus.running
                                ? YLColors.connected
                                : YLColors.disconnected,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            status == CoreStatus.running
                                ? s.coreRunning
                                : s.coreStopped,
                            style: YLText.body.copyWith(
                              color: status == CoreStatus.running
                                  ? YLColors.connected
                                  : YLColors.zinc500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, thickness: 0.5, color: dividerColor),
                    YLInfoRow(
                      label: s.logLevelSetting,
                      trailing: DropdownButton<String>(
                        value: logLevel,
                        underline: const SizedBox.shrink(),
                        style: YLText.body.copyWith(
                          color: isDark ? YLColors.zinc200 : YLColors.zinc700,
                        ),
                        dropdownColor: isDark ? YLColors.zinc800 : Colors.white,
                        items: const [
                          DropdownMenuItem(
                              value: 'debug', child: Text('Debug')),
                          DropdownMenuItem(
                              value: 'info', child: Text('Info')),
                          DropdownMenuItem(
                              value: 'warning', child: Text('Warning')),
                          DropdownMenuItem(
                              value: 'error', child: Text('Error')),
                          DropdownMenuItem(
                              value: 'silent', child: Text('Silent')),
                        ],
                        onChanged: (v) async {
                          if (v == null) return;
                          ref.read(logLevelProvider.notifier).state = v;
                          await SettingsService.setLogLevel(v);
                          if (status == CoreStatus.running) {
                            try {
                              await CoreManager.instance.api.setLogLevel(v);
                            } catch (_) {}
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),

              // ══ 5. Diagnostics ════════════════════════════════════
              _SectionTitle(s.sectionTools),
              _SettingsCard(
                child: Column(
                  children: [
                    YLInfoRow(
                      label: s.navConnections,
                      trailing: const Icon(Icons.chevron_right, size: 18,
                          color: YLColors.zinc400),
                      enabled: status == CoreStatus.running,
                      onTap: status == CoreStatus.running
                          ? () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const ConnectionsSubPage()),
                              )
                          : null,
                    ),
                    Divider(height: 1, thickness: 0.5, color: dividerColor),
                    YLInfoRow(
                      label: s.tabLogs,
                      trailing: const Icon(Icons.chevron_right, size: 18,
                          color: YLColors.zinc400),
                      enabled: status == CoreStatus.running,
                      onTap: status == CoreStatus.running
                          ? () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const LogsSubPage()),
                              )
                          : null,
                    ),
                    Divider(height: 1, thickness: 0.5, color: dividerColor),
                    YLInfoRow(
                      label: s.diagnostics,
                      trailing: const Icon(Icons.chevron_right, size: 18,
                          color: YLColors.zinc400),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const StartupReportPage()),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Split tunnel (Android only)
              if (Platform.isAndroid) ...[
                const _SplitTunnelSection(),
                const SizedBox(height: 8),
              ],

              // ══ About ═════════════════════════════════════════════
              _SectionTitle(s.sectionAbout),
              _SettingsCard(
                child: Column(
                  children: [
                    YLInfoRow(
                      label: s.versionLabel,
                      value: AppConstants.appVersion,
                    ),
                    Divider(height: 1, thickness: 0.5, color: dividerColor),
                    YLInfoRow(
                      label: s.coreLabel,
                      value: 'mihomo',
                    ),
                    Divider(height: 1, thickness: 0.5, color: dividerColor),
                    YLInfoRow(
                      label: s.projectHome,
                      trailing: const Icon(Icons.open_in_new,
                          size: 14, color: YLColors.zinc400),
                      onTap: () =>
                          _launchUrl('https://github.com/onesyue/yuelink'),
                    ),
                    Divider(height: 1, thickness: 0.5, color: dividerColor),
                    YLInfoRow(
                      label: s.checkUpdate,
                      trailing: _checkingUpdate
                          ? const SizedBox(
                              width: 14, height: 14,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))
                          : _pendingUpdate != null
                              ? YLChip(
                                  s.updateAvailableV(
                                      _pendingUpdate!.latestVersion),
                                  color: isDark ? Colors.white : YLColors.primary)
                              : const Icon(Icons.chevron_right,
                                  size: 18, color: YLColors.zinc400),
                      onTap: _checkingUpdate
                          ? null
                          : _pendingUpdate != null
                              ? () async {
                                  final uri = Uri.parse(
                                      _pendingUpdate!.releaseUrl);
                                  if (await canLaunchUrl(uri)) {
                                    await launchUrl(uri,
                                        mode: LaunchMode.externalApplication);
                                  }
                                }
                              : () async {
                                  setState(() => _checkingUpdate = true);
                                  final info =
                                      await UpdateChecker.instance.check();
                                  if (mounted) {
                                    setState(() {
                                      _pendingUpdate = info;
                                      _checkingUpdate = false;
                                    });
                                    if (info == null) {
                                      AppNotifier.info(s.alreadyLatest);
                                    }
                                  }
                                },
                    ),
                    Divider(height: 1, thickness: 0.5, color: dividerColor),
                    YLInfoRow(
                      label: s.openSourceLicense,
                      trailing: const Icon(Icons.chevron_right,
                          size: 18, color: YLColors.zinc400),
                      onTap: () => showLicensePage(
                        context: context,
                        applicationName: AppConstants.appName,
                        applicationVersion: AppConstants.appVersion,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

// ── Settings page helper widgets ─────────────────────────────────────────────

/// Section title — matches the dashboard top bar label style.
class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
      child: Text(
        text.toUpperCase(),
        style: YLText.caption.copyWith(
          letterSpacing: 1.5,
          fontWeight: FontWeight.w600,
          color: YLColors.zinc400,
        ),
      ),
    );
  }
}

/// Card container matching the dashboard card style.
class _SettingsCard extends StatelessWidget {
  final Widget child;
  const _SettingsCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
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
      child: child,
    );
  }
}

// ── Split Tunnel Section (Android) ────────────────────────────────────────────

class _SplitTunnelSection extends ConsumerStatefulWidget {
  const _SplitTunnelSection();

  @override
  ConsumerState<_SplitTunnelSection> createState() =>
      _SplitTunnelSectionState();
}

class _SplitTunnelSectionState extends ConsumerState<_SplitTunnelSection> {
  List<Map<String, String>>? _apps;
  String _search = '';
  bool _loading = false;

  Future<void> _loadApps() async {
    setState(() => _loading = true);
    final apps = await VpnService.getInstalledApps(showSystem: false);
    if (mounted) setState(() { _apps = apps; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mode = ref.watch(splitTunnelModeProvider);
    final selectedPkgs = ref.watch(splitTunnelAppsProvider);
    final dividerColor = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.06);

    return _SettingsCard(
      child: Column(
        children: [
          // Mode selector
          YLInfoRow(
            label: s.splitTunnelMode,
            trailing: DropdownButton<SplitTunnelMode>(
              value: mode,
              underline: const SizedBox.shrink(),
              style: YLText.body.copyWith(
                color: isDark ? YLColors.zinc200 : YLColors.zinc700,
              ),
              dropdownColor: isDark ? YLColors.zinc800 : Colors.white,
              items: [
                DropdownMenuItem(
                    value: SplitTunnelMode.all,
                    child: Text(s.splitTunnelModeAll)),
                DropdownMenuItem(
                    value: SplitTunnelMode.whitelist,
                    child: Text(s.splitTunnelModeWhitelist)),
                DropdownMenuItem(
                    value: SplitTunnelMode.blacklist,
                    child: Text(s.splitTunnelModeBlacklist)),
              ],
              onChanged: (v) {
                if (v != null) ref.read(splitTunnelModeProvider.notifier).set(v);
              },
            ),
          ),
          if (mode != SplitTunnelMode.all) ...[
            Divider(height: 1, thickness: 0.5, color: dividerColor),
            YLSettingsRow(
              title: s.splitTunnelApps,
              description: s.splitTunnelEffectHint,
              trailing: TextButton.icon(
                icon: const Icon(Icons.apps, size: 14),
                label: Text(s.splitTunnelManage),
                onPressed: () {
                  if (_apps == null) _loadApps();
                  _showAppPicker(context, selectedPkgs);
                },
              ),
            ),
            if (selectedPkgs.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: selectedPkgs
                      .map((pkg) => Chip(
                            label: Text(pkg,
                                style: const TextStyle(fontSize: 11)),
                            deleteIcon:
                                const Icon(Icons.close, size: 14),
                            onDeleted: () => ref
                                .read(splitTunnelAppsProvider.notifier)
                                .remove(pkg),
                          ))
                      .toList(),
                ),
              ),
          ],
        ],
      ),
    );
  }

  void _showAppPicker(BuildContext context, List<String> selected) {
    final s = S.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          final apps = _apps ?? [];
          final filtered = _search.isEmpty
              ? apps
              : apps
                  .where((a) =>
                      (a['appName'] ?? '').toLowerCase().contains(_search) ||
                      (a['packageName'] ?? '').toLowerCase().contains(_search))
                  .toList();

          return DraggableScrollableSheet(
            initialChildSize: 0.85,
            expand: false,
            builder: (_, sc) => Column(
              children: [
                const SizedBox(height: 8),
                Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2))),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    autofocus: false,
                    decoration: InputDecoration(
                      hintText: s.splitTunnelSearchHint,
                      prefixIcon: const Icon(Icons.search, size: 18),
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (v) => setModal(() => _search = v.toLowerCase()),
                  ),
                ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : ListView.builder(
                          controller: sc,
                          itemCount: filtered.length,
                          itemBuilder: (_, i) {
                            final app = filtered[i];
                            final pkg = app['packageName'] ?? '';
                            final isSelected = selected.contains(pkg);
                            return CheckboxListTile(
                              dense: true,
                              title: Text(app['appName'] ?? pkg),
                              subtitle: Text(pkg,
                                  style: const TextStyle(fontSize: 11)),
                              value: isSelected,
                              onChanged: (_) {
                                ref
                                    .read(splitTunnelAppsProvider.notifier)
                                    .toggle(pkg);
                                setModal(() {});
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// A single settings row with a label on the left and a value or trailing widget on the right.
class YLInfoRow extends StatelessWidget {
  final String label;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool enabled;

  const YLInfoRow({
    super.key,
    required this.label,
    this.value,
    this.trailing,
    this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final labelColor = enabled
        ? (isDark ? YLColors.zinc200 : YLColors.zinc700)
        : YLColors.zinc400;
    final valueColor = enabled
        ? (isDark ? YLColors.zinc400 : YLColors.zinc500)
        : YLColors.zinc300;

    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: YLText.body.copyWith(color: labelColor)),
          ),
          if (value != null)
            Text(value!, style: YLText.body.copyWith(color: valueColor)),
          if (trailing != null) trailing!,
        ],
      ),
    );

    if (onTap != null && enabled) {
      return InkWell(onTap: onTap, child: content);
    }
    return Opacity(opacity: enabled ? 1.0 : 0.5, child: content);
  }
}

// ── Close behavior row (desktop) ─────────────────────────────────────────────

class _CloseBehaviorRow extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final behavior = ref.watch(closeBehaviorProvider);
    return YLInfoRow(
      label: s.closeWindowBehavior,
      trailing: SizedBox(
        width: 260,
        child: SegmentedButton<String>(
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            textStyle: const TextStyle(fontSize: 12),
          ),
          segments: [
            ButtonSegment(value: 'tray', label: Text(s.closeBehaviorTray)),
            ButtonSegment(value: 'exit', label: Text(s.closeBehaviorExit)),
          ],
          selected: {behavior},
          onSelectionChanged: (v) async {
            final val = v.first;
            ref.read(closeBehaviorProvider.notifier).state = val;
            await SettingsService.setCloseBehavior(val);
          },
        ),
      ),
    );
  }
}

// ── Hotkey row (desktop) ──────────────────────────────────────────────────────

class _HotkeyRow extends ConsumerStatefulWidget {
  @override
  ConsumerState<_HotkeyRow> createState() => _HotkeyRowState();
}

class _HotkeyRowState extends ConsumerState<_HotkeyRow> {
  bool _registering = false;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final stored = ref.watch(toggleHotkeyProvider);
    final display = displayHotkey(stored);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(s.toggleConnectionHotkey,
                    style: YLText.body.copyWith(
                        color: isDark ? YLColors.zinc200 : YLColors.zinc700)),
              ),
              Text(
                display,
                style: YLText.body.copyWith(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  color: isDark ? YLColors.zinc400 : YLColors.zinc500,
                ),
              ),
              const SizedBox(width: 8),
              if (_registering)
                const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
              else
                TextButton(
                  onPressed: _editHotkey,
                  style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8)),
                  child: Text(s.hotkeyEdit,
                      style: const TextStyle(fontSize: 12)),
                ),
            ],
          ),
          if (Platform.isLinux)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                s.hotkeyLinuxNotice,
                style: YLText.caption.copyWith(color: YLColors.zinc400),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _editHotkey() async {
    final s = S.of(context);
    final newKey = await _showHotkeyDialog(context, s);
    if (newKey == null || !mounted) return;
    setState(() => _registering = true);
    try {
      ref.read(toggleHotkeyProvider.notifier).state = newKey;
      await SettingsService.setToggleHotkey(newKey);
      // Re-registration is handled by ref.listen in _YueLinkAppState
      AppNotifier.success(s.hotkeySaved);
    } catch (_) {
      AppNotifier.error(s.hotkeyFailed);
    } finally {
      if (mounted) setState(() => _registering = false);
    }
  }

  Future<String?> _showHotkeyDialog(BuildContext context, S s) {
    final focusNode = FocusNode();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.toggleConnectionHotkey),
        content: KeyboardListener(
          focusNode: focusNode,
          autofocus: true,
          onKeyEvent: (event) {
            if (event is! KeyDownEvent) return;
            if (_isModifierKey(event.logicalKey)) return;
            final parts = <String>[];
            if (HardwareKeyboard.instance.isControlPressed) {
              parts.add('ctrl');
            }
            if (HardwareKeyboard.instance.isShiftPressed) parts.add('shift');
            if (HardwareKeyboard.instance.isAltPressed) parts.add('alt');
            if (HardwareKeyboard.instance.isMetaPressed) parts.add('meta');
            final label = event.logicalKey.keyLabel.toLowerCase();
            if (label.isNotEmpty) parts.add(label);
            if (parts.length >= 2) Navigator.pop(ctx, parts.join('+'));
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              s.hotkeyListening,
              textAlign: TextAlign.center,
              style: YLText.body.copyWith(color: YLColors.zinc400),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: Text(s.cancel)),
        ],
      ),
    ).whenComplete(focusNode.dispose);
  }
}

// ── GeoData row ───────────────────────────────────────────────────────────────

// ── Linux proxy notice row ────────────────────────────────────────────────────

class _LinuxProxyNoticeRow extends StatelessWidget {
  const _LinuxProxyNoticeRow();

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 16, color: YLColors.zinc400),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.linuxProxyNotice,
                    style: YLText.body.copyWith(
                        color: isDark ? YLColors.zinc200 : YLColors.zinc700)),
                const SizedBox(height: 2),
                Text(s.linuxProxyManual,
                    style: YLText.caption.copyWith(
                        fontFamily: 'monospace', color: YLColors.zinc400)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── GeoData row ───────────────────────────────────────────────────────────────

class _GeoDataRow extends StatefulWidget {
  @override
  State<_GeoDataRow> createState() => _GeoDataRowState();
}

class _GeoDataRowState extends State<_GeoDataRow> {
  DateTime? _lastUpdated;
  bool _loading = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadLastUpdated();
  }

  Future<void> _loadLastUpdated() async {
    final dt = await GeoDataService.lastUpdated();
    if (mounted) setState(() { _lastUpdated = dt; _loaded = true; });
  }

  Future<void> _update() async {
    if (_loading) return;
    final s = S.of(context);
    setState(() => _loading = true);
    try {
      final ok = await GeoDataService.forceUpdate();
      if (!mounted) return;
      if (ok) {
        await _loadLastUpdated();
        AppNotifier.success(s.geoUpdated);
      } else {
        AppNotifier.error(s.geoUpdateFailed);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    String subtitle;
    if (!_loaded) {
      subtitle = '...';
    } else if (_lastUpdated != null) {
      final d = _lastUpdated!;
      subtitle = s.geoLastUpdated(
          '${d.year}-${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}');
    } else {
      subtitle = s.noData;
    }
    return YLSettingsRow(
      title: s.geoDatabase,
      description: subtitle,
      trailing: _loading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2))
          : TextButton(
              onPressed: _update,
              style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8)),
              child: Text(s.geoUpdateNow,
                  style: const TextStyle(fontSize: 12)),
            ),
    );
  }
}

// ── Test URL row ──────────────────────────────────────────────────────────────

class _TestUrlRow extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final url = ref.watch(testUrlProvider);
    const defaultUrl = 'https://www.gstatic.com/generate_204';

    // Shorten the URL for display: strip https:// and truncate if long
    final display = url
        .replaceFirst('https://', '')
        .replaceFirst('http://', '');
    final truncated =
        display.length > 32 ? '${display.substring(0, 30)}…' : display;

    return InkWell(
      onTap: () => _showEditDialog(context, ref, s, url, defaultUrl),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(s.testUrlSettings,
                  style: YLText.body.copyWith(
                      color: isDark ? YLColors.zinc200 : YLColors.zinc700)),
            ),
            Text(
              truncated,
              style: YLText.body.copyWith(
                  color: isDark ? YLColors.zinc400 : YLColors.zinc500,
                  fontFamily: 'monospace',
                  fontSize: 12),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.edit_outlined, size: 14, color: YLColors.zinc400),
          ],
        ),
      ),
    );
  }

  Future<void> _showEditDialog(BuildContext context, WidgetRef ref, S s,
      String currentUrl, String defaultUrl) async {
    final ctrl = TextEditingController(text: currentUrl);
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => AlertDialog(
          title: Text(s.testUrlDialogTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: InputDecoration(
                  hintText: defaultUrl,
                  border: const OutlineInputBorder(),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () {
                  ctrl.text = defaultUrl;
                  setModal(() {});
                },
                icon: const Icon(Icons.restore, size: 14),
                label: Text(s.resetDefault,
                    style: const TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(s.cancel)),
            FilledButton(
              onPressed: () async {
                final url = ctrl.text.trim();
                if (url.isEmpty) return;
                Navigator.pop(ctx);
                ref.read(testUrlProvider.notifier).state = url;
                await SettingsService.setTestUrl(url);
              },
              child: Text(s.save),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
  }
}

/// A settings row with a title, optional description, and a trailing widget.
class YLSettingsRow extends StatelessWidget {
  final String title;
  final String? description;
  final Widget trailing;

  const YLSettingsRow({
    super.key,
    required this.title,
    this.description,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? YLColors.zinc200 : YLColors.zinc700;
    final descColor = isDark ? YLColors.zinc500 : YLColors.zinc400;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: YLText.body.copyWith(color: titleColor)),
                if (description != null) ...[
                  const SizedBox(height: 2),
                  Text(description!,
                      style: YLText.caption.copyWith(color: descColor)),
                ],
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}
