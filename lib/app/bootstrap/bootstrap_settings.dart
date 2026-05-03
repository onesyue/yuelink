import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/storage/auth_token_service.dart';
import '../../core/storage/settings_service.dart';
import '../../infrastructure/datasources/xboard/models.dart';

class BootstrapSettingsSnapshot {
  const BootstrapSettingsSnapshot({
    required this.authBootstrapUncertain,
    required this.savedToken,
    required this.savedAccentColor,
    required this.savedSubSyncInterval,
    required this.savedTheme,
    required this.savedProfileId,
    required this.savedRoutingMode,
    required this.savedConnectionMode,
    required this.savedQuicPolicy,
    required this.savedDesktopTunStack,
    required this.savedLogLevel,
    required this.savedAutoConnect,
    required this.savedManualStopped,
    required this.savedSystemProxy,
    required this.savedLanguage,
    required this.savedTestUrl,
    required this.savedCloseBehavior,
    required this.savedToggleHotkey,
    required this.savedDelayResults,
    required this.savedTabIndex,
    required this.savedBuiltTabs,
    required this.savedOnboarding,
    required this.savedPersona,
    required this.savedTileShowNodeInfo,
    required this.savedProfile,
  });

  final bool authBootstrapUncertain;
  final String? savedToken;
  final String savedAccentColor;
  final int savedSubSyncInterval;
  final ThemeMode savedTheme;
  final String? savedProfileId;
  final String savedRoutingMode;
  final String savedConnectionMode;
  final String savedQuicPolicy;
  final String savedDesktopTunStack;
  final String savedLogLevel;
  final bool savedAutoConnect;
  final bool savedManualStopped;
  final bool savedSystemProxy;
  final String savedLanguage;
  final String savedTestUrl;
  final String savedCloseBehavior;
  final String savedToggleHotkey;
  final Map<String, int> savedDelayResults;
  final int savedTabIndex;
  final List<int> savedBuiltTabs;
  final bool savedOnboarding;
  final String? savedPersona;
  final bool savedTileShowNodeInfo;
  final UserProfile? savedProfile;
}

Future<BootstrapSettingsSnapshot> loadBootstrapSettingsSnapshot() async {
  final bootstrapStorageTimeout = Platform.isAndroid
      ? const Duration(milliseconds: 1200)
      : const Duration(seconds: 4);
  final authService = AuthTokenService.instance;

  await SettingsService.loadWithTimeout(bootstrapStorageTimeout);

  bool authBootstrapUncertain = false;
  String? savedToken;
  String savedAccentColor = '3B82F6';
  int savedSubSyncInterval = 6;
  ThemeMode savedTheme = ThemeMode.system;
  String? savedProfileId;
  String savedRoutingMode = 'rule';
  String savedConnectionMode = 'systemProxy';
  String savedQuicPolicy = SettingsService.defaultQuicPolicy;
  String savedDesktopTunStack = 'mixed';
  String savedLogLevel = 'error';
  bool savedAutoConnect = false;
  bool savedManualStopped = false;
  bool savedSystemProxy = true;
  String savedLanguage = 'zh';
  String savedTestUrl = 'https://www.gstatic.com/generate_204';
  String savedCloseBehavior = 'tray';
  String savedToggleHotkey = 'ctrl+alt+c';
  Map<String, int> savedDelayResults = const {};
  int savedTabIndex = 0;
  List<int> savedBuiltTabs = const [0];
  bool savedOnboarding = false;
  String? savedPersona;
  bool savedTileShowNodeInfo = false;
  UserProfile? savedProfile;

  try {
    try {
      savedToken = await authService.getToken().timeout(
        bootstrapStorageTimeout,
      );
    } on TimeoutException {
      authBootstrapUncertain = true;
      debugPrint('[Bootstrap] getToken timed out — auth marked uncertain');
    } catch (e) {
      authBootstrapUncertain = true;
      debugPrint('[Bootstrap] getToken threw, auth marked uncertain: $e');
    }

    await SettingsService.migrateAccentToBlueIfNeeded();
    savedAccentColor = await SettingsService.getAccentColor();
    savedSubSyncInterval = await SettingsService.getSubSyncInterval();
    savedTheme = await SettingsService.getThemeMode();
    savedProfileId = await SettingsService.getActiveProfileId();
    savedRoutingMode = await SettingsService.getRoutingMode();
    savedConnectionMode = await SettingsService.getConnectionMode();
    savedQuicPolicy = await SettingsService.getQuicPolicy();
    savedDesktopTunStack = await SettingsService.getDesktopTunStack();
    savedLogLevel = await SettingsService.getLogLevel();
    savedAutoConnect = await SettingsService.getAutoConnect();
    savedManualStopped = await SettingsService.getManualStopped();
    savedSystemProxy = await SettingsService.getSystemProxyOnConnect();
    savedLanguage = await SettingsService.getLanguage();
    savedTestUrl = await SettingsService.getTestUrl();
    savedCloseBehavior = await SettingsService.getCloseBehavior();
    savedToggleHotkey = await SettingsService.getToggleHotkey();
    savedDelayResults = await SettingsService.getDelayResults();
    savedTabIndex = await SettingsService.getLastTabIndex();
    savedBuiltTabs = await SettingsService.getBuiltTabs();
    savedOnboarding = await SettingsService.getHasSeenOnboarding();
    savedPersona = await SettingsService.get<String>('onboardingPersona');
    savedTileShowNodeInfo = await SettingsService.getTileShowNodeInfo();

    if (savedToken != null && savedToken.isNotEmpty) {
      savedProfile = await authService.getCachedProfile().timeout(
        bootstrapStorageTimeout,
        onTimeout: () => null,
      );
    }
  } catch (e, st) {
    debugPrint(
      '[Bootstrap] data gather threw — runApp will use safe defaults: $e\n$st',
    );
    authBootstrapUncertain = true;
  }

  return BootstrapSettingsSnapshot(
    authBootstrapUncertain: authBootstrapUncertain,
    savedToken: savedToken,
    savedAccentColor: savedAccentColor,
    savedSubSyncInterval: savedSubSyncInterval,
    savedTheme: savedTheme,
    savedProfileId: savedProfileId,
    savedRoutingMode: savedRoutingMode,
    savedConnectionMode: savedConnectionMode,
    savedQuicPolicy: savedQuicPolicy,
    savedDesktopTunStack: savedDesktopTunStack,
    savedLogLevel: savedLogLevel,
    savedAutoConnect: savedAutoConnect,
    savedManualStopped: savedManualStopped,
    savedSystemProxy: savedSystemProxy,
    savedLanguage: savedLanguage,
    savedTestUrl: savedTestUrl,
    savedCloseBehavior: savedCloseBehavior,
    savedToggleHotkey: savedToggleHotkey,
    savedDelayResults: savedDelayResults,
    savedTabIndex: savedTabIndex,
    savedBuiltTabs: savedBuiltTabs,
    savedOnboarding: savedOnboarding,
    savedPersona: savedPersona,
    savedTileShowNodeInfo: savedTileShowNodeInfo,
    savedProfile: savedProfile,
  );
}
