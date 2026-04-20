import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dashboard/home_content_provider.dart';
import 'scene_mode.dart';
import 'scene_mode_service.dart';

// ── Notifier ──────────────────────────────────────────────────────────────────

class SceneModeNotifier extends AsyncNotifier<SceneMode> {
  @override
  Future<SceneMode> build() => SceneModeService.load();

  /// Switch to [mode] and persist immediately.
  Future<void> setMode(SceneMode mode) async {
    state = const AsyncLoading();
    await SceneModeService.save(mode);
    if (!ref.mounted) return;
    state = AsyncData(mode);
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

/// The currently active [SceneMode]. Loads from disk on first access.
final sceneModeProvider =
    AsyncNotifierProvider<SceneModeNotifier, SceneMode>(SceneModeNotifier.new);

/// Convenience derived provider — current [SceneModeConfig] (never null).
/// Reads from [sceneModeConfigsProvider] which merges local presets + remote overrides.
/// Falls back to [SceneMode.daily] config while loading.
final sceneModeConfigProvider = Provider<SceneModeConfig>((ref) {
  final mode = ref.watch(sceneModeProvider).value ?? SceneMode.daily;
  final configs = ref.watch(sceneModeConfigsProvider);
  return configs[mode] ?? kSceneModeDefaults[mode]!;
});
