import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/surge_modules/module_entity.dart';
import '../../../infrastructure/surge_modules/module_downloader.dart';
import '../../../infrastructure/surge_modules/module_repository.dart';

// ── State ─────────────────────────────────────────────────────────────────────

class ModuleState {
  final List<ModuleRecord> modules;
  final bool isLoading;
  final String? error;

  const ModuleState({
    this.modules = const [],
    this.isLoading = false,
    this.error,
  });

  ModuleState copyWith({
    List<ModuleRecord>? modules,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) =>
      ModuleState(
        modules: modules ?? this.modules,
        isLoading: isLoading ?? this.isLoading,
        error: clearError ? null : (error ?? this.error),
      );
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class ModuleNotifier extends StateNotifier<ModuleState> {
  ModuleNotifier() : super(const ModuleState()) {
    loadAll();
  }

  final _repo = const ModuleRepository();

  /// Load all modules from storage.
  Future<void> loadAll() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final modules = await _repo.loadAll();
      state = state.copyWith(modules: modules, isLoading: false);
    } catch (e) {
      debugPrint('[ModuleProvider] loadAll error: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Download a module from [url], parse it, and save it.
  ///
  /// Throws on failure so the UI can show a specific error message.
  Future<ModuleRecord> addModule(String url) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      // Check if URL already added
      final existing = state.modules
          .where((m) => m.sourceUrl == url)
          .firstOrNull;

      final record = await ModuleDownloader.fetchAndSave(url, existing: existing);

      await _refresh();
      return record;
    } catch (e) {
      debugPrint('[ModuleProvider] addModule error: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
      rethrow;
    }
  }

  /// Re-download and update an existing module by ID.
  Future<void> refreshModule(String id) async {
    final module = state.modules.firstWhere(
      (m) => m.id == id,
      orElse: () => throw Exception('Module $id not found'),
    );
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await ModuleDownloader.fetchAndSave(module.sourceUrl, existing: module);
      await _refresh();
    } catch (e) {
      debugPrint('[ModuleProvider] refreshModule error: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
      rethrow;
    }
  }

  /// Delete a module by ID.
  Future<void> deleteModule(String id) async {
    try {
      await _repo.delete(id);
      final updated = state.modules.where((m) => m.id != id).toList();
      state = state.copyWith(modules: updated, clearError: true);
    } catch (e) {
      debugPrint('[ModuleProvider] deleteModule error: $e');
      state = state.copyWith(error: e.toString());
    }
  }

  /// Toggle the enabled state of a module.
  Future<void> toggleEnabled(String id) async {
    final idx = state.modules.indexWhere((m) => m.id == id);
    if (idx < 0) return;

    final current = state.modules[idx];
    final updated = List<ModuleRecord>.from(state.modules);
    updated[idx] = current.copyWith(enabled: !current.enabled);

    // Optimistic update
    state = state.copyWith(modules: updated);

    try {
      await _repo.setEnabled(id, updated[idx].enabled);
    } catch (e) {
      debugPrint('[ModuleProvider] toggleEnabled error: $e');
      // Revert on error
      state = state.copyWith(modules: state.modules, error: e.toString());
      await _refresh();
    }
  }

  /// Refresh all enabled modules (re-download).
  Future<void> refreshAll() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      for (final module in state.modules) {
        if (!module.enabled) continue;
        try {
          await ModuleDownloader.fetchAndSave(module.sourceUrl, existing: module);
        } catch (e) {
          debugPrint('[ModuleProvider] refreshAll: failed for ${module.name}: $e');
        }
      }
      await _refresh();
    } catch (e) {
      debugPrint('[ModuleProvider] refreshAll error: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> _refresh() async {
    final modules = await _repo.loadAll();
    state = state.copyWith(modules: modules, isLoading: false);
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

final moduleProvider =
    StateNotifierProvider<ModuleNotifier, ModuleState>(
  (ref) => ModuleNotifier(),
);

/// Flat list of rule strings from all enabled modules.
/// Used by config injection only — no UI dependency.
final enabledModuleRulesProvider = FutureProvider<List<String>>((ref) async {
  return const ModuleRepository().getEnabledRules();
});
