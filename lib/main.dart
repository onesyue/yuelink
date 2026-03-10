import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pages/home_page.dart';
import 'pages/log_page.dart';
import 'pages/profile_page.dart';
import 'pages/proxy_page.dart';
import 'pages/settings_page.dart';
import 'providers/profile_provider.dart';
import 'services/core_manager.dart';
import 'services/settings_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Restore persisted settings before first frame
  final savedTheme = await SettingsService.getThemeMode();
  final savedProfileId = await SettingsService.getActiveProfileId();

  // Initialize core manager (auto-detects FFI or mock)
  CoreManager.instance;

  runApp(ProviderScope(
    overrides: [
      // Seed providers with saved values
      themeProvider.overrideWith((ref) => savedTheme),
      activeProfileIdProvider.overrideWith((ref) => ActiveProfileNotifier(savedProfileId)),
    ],
    child: const YueLinkApp(),
  ));
}

class YueLinkApp extends ConsumerWidget {
  const YueLinkApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);

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
    // Check if first launch (no profiles) and jump to profile page
    Future.microtask(() {
      final profiles = ref.read(profilesProvider);
      profiles.whenData((list) {
        if (list.isEmpty && mounted) {
          setState(() => _currentIndex = 2); // Profile page
        }
      });
    });
  }

  /// Navigate to a specific tab programmatically.
  void navigateTo(int index) {
    if (mounted) setState(() => _currentIndex = index);
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
