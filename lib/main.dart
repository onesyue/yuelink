import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:tray_manager/tray_manager.dart';

import 'constants.dart';
import 'pages/connections_page.dart';
import 'pages/home_page.dart';
import 'pages/log_page.dart';
import 'pages/profile_page.dart';
import 'pages/proxy_page.dart';
import 'pages/settings_page.dart';
import 'providers/core_provider.dart';
import 'providers/profile_provider.dart';
import 'services/auto_update_service.dart';
import 'services/core_manager.dart';
import 'services/profile_service.dart';
import 'services/settings_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Restore persisted settings
  final savedTheme = await SettingsService.getThemeMode();
  final savedProfileId = await SettingsService.getActiveProfileId();
  final savedRoutingMode = await SettingsService.getRoutingMode();
  final savedConnectionMode = await SettingsService.getConnectionMode();
  final savedLogLevel = await SettingsService.getLogLevel();
  final savedAutoConnect = await SettingsService.getAutoConnect();
  final savedSystemProxy = await SettingsService.getSystemProxyOnConnect();

  // Configure launch at startup (desktop only)
  if (Platform.isMacOS || Platform.isWindows) {
    try {
      launchAtStartup.setup(
        appName: AppConstants.appName,
        appPath: Platform.resolvedExecutable,
      );
    } catch (_) {}
  }

  // Initialize core manager
  CoreManager.instance;

  // Start subscription auto-update service
  AutoUpdateService.instance.start();

  runApp(ProviderScope(
    overrides: [
      themeProvider.overrideWith((ref) => savedTheme),
      activeProfileIdProvider
          .overrideWith((ref) => ActiveProfileNotifier(savedProfileId)),
      routingModeProvider.overrideWith((ref) => savedRoutingMode),
      connectionModeProvider.overrideWith((ref) => savedConnectionMode),
      logLevelProvider.overrideWith((ref) => savedLogLevel),
      autoConnectProvider.overrideWith((ref) => savedAutoConnect),
      systemProxyOnConnectProvider.overrideWith((ref) => savedSystemProxy),
    ],
    child: const YueLinkApp(),
  ));
}

class YueLinkApp extends ConsumerStatefulWidget {
  const YueLinkApp({super.key});

  @override
  ConsumerState<YueLinkApp> createState() => _YueLinkAppState();
}

class _YueLinkAppState extends ConsumerState<YueLinkApp> with TrayListener {
  bool _trayInitialized = false;

  @override
  void initState() {
    super.initState();
    if (Platform.isMacOS || Platform.isWindows) {
      _initTray();
    }
    // Auto-connect after first frame is rendered
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoConnect());
  }

  @override
  void dispose() {
    if (_trayInitialized) trayManager.removeListener(this);
    AutoUpdateService.instance.stop();
    super.dispose();
  }

  Future<void> _initTray() async {
    try {
      await trayManager.setIcon('assets/tray_icon.png');
      await _updateTrayMenu(isRunning: false);
      trayManager.addListener(this);
      _trayInitialized = true;
    } catch (_) {}
  }

  Future<void> _updateTrayMenu({required bool isRunning}) async {
    try {
      await trayManager.setContextMenu(Menu(items: [
        MenuItem(key: 'toggle', label: isRunning ? '断开连接' : '连接'),
        MenuItem.separator(),
        MenuItem(key: 'quit', label: '退出'),
      ]));
    } catch (_) {}
  }

  Future<void> _maybeAutoConnect() async {
    final autoConnect = ref.read(autoConnectProvider);
    if (!autoConnect) return;

    final isMock = ref.read(isMockModeProvider);
    if (isMock) {
      await ref.read(coreActionsProvider).start('');
      return;
    }

    final activeId = ref.read(activeProfileIdProvider);
    if (activeId == null) return;

    final config = await ProfileService.loadConfig(activeId);
    if (config == null) return;

    await ref.read(coreActionsProvider).start(config);
  }

  @override
  void onTrayIconMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'toggle':
        _handleTrayToggle();
      case 'quit':
        _handleQuit();
    }
  }

  Future<void> _handleTrayToggle() async {
    final status = ref.read(coreStatusProvider);
    final actions = ref.read(coreActionsProvider);
    final isMock = ref.read(isMockModeProvider);

    if (status == CoreStatus.running) {
      await actions.stop();
    } else if (status == CoreStatus.stopped) {
      if (isMock) {
        await actions.start('');
      } else {
        final activeId = ref.read(activeProfileIdProvider);
        if (activeId == null) return;
        final config = await ProfileService.loadConfig(activeId);
        if (config == null) return;
        await actions.start(config);
      }
    }
  }

  Future<void> _handleQuit() async {
    final status = ref.read(coreStatusProvider);
    if (status == CoreStatus.running) {
      await ref.read(coreActionsProvider).stop();
    }
    exit(0);
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeProvider);

    // Sync tray menu with connection state
    ref.listen(coreStatusProvider, (_, next) {
      if (_trayInitialized) {
        if (next == CoreStatus.running) {
          _updateTrayMenu(isRunning: true);
        } else if (next == CoreStatus.stopped) {
          _updateTrayMenu(isRunning: false);
        }
      }
    });

    return MaterialApp(
      title: 'YueLink',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF6366F1),
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF6366F1),
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: const MainShell(),
    );
  }
}

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _currentIndex = 0;

  static const _pages = [
    HomePage(),
    ProxyPage(),
    ConnectionsPage(),
    ProfilePage(),
    LogPage(),
    SettingsPage(),
  ];

  static const _destinations = [
    NavigationDestination(
        icon: Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home),
        label: '首页'),
    NavigationDestination(
        icon: Icon(Icons.dns_outlined),
        selectedIcon: Icon(Icons.dns),
        label: '代理'),
    NavigationDestination(
        icon: Icon(Icons.cable_outlined),
        selectedIcon: Icon(Icons.cable),
        label: '连接'),
    NavigationDestination(
        icon: Icon(Icons.description_outlined),
        selectedIcon: Icon(Icons.description),
        label: '配置'),
    NavigationDestination(
        icon: Icon(Icons.list_alt_outlined),
        selectedIcon: Icon(Icons.list_alt),
        label: '日志'),
    NavigationDestination(
        icon: Icon(Icons.settings_outlined),
        selectedIcon: Icon(Icons.settings),
        label: '设置'),
  ];

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      final profiles = ref.read(profilesProvider);
      profiles.whenData((list) {
        if (list.isEmpty && mounted) {
          setState(() => _currentIndex = 2);
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width > 600;

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _currentIndex,
              onDestinationSelected: (i) => setState(() => _currentIndex = i),
              labelType: NavigationRailLabelType.all,
              leading: const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: _AppLogo(),
              ),
              destinations: _destinations
                  .map((d) => NavigationRailDestination(
                        icon: d.icon,
                        selectedIcon: d.selectedIcon,
                        label: Text(d.label),
                      ))
                  .toList(),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: _pages[_currentIndex]),
          ],
        ),
      );
    }

    return Scaffold(
      body: _pages[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: _destinations,
      ),
    );
  }
}

class _AppLogo extends StatelessWidget {
  const _AppLogo();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.link_rounded,
            size: 20,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 4),
        Text('YueLink',
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(fontWeight: FontWeight.bold)),
      ],
    );
  }
}
