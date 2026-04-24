// Barrel file for core providers — preserves the historical import path
// `core/providers/core_provider.dart` while the underlying declarations
// live in two cohesive files:
//
//   - core_runtime_providers.dart    — lifecycle state, traffic/memory,
//                                       CoreActions, heartbeat
//   - core_preferences_providers.dart — persisted user settings
//
// New code should import from the specific file it needs, but existing
// call sites that already use this barrel keep working unchanged.
//
// The previous `export '../../modules/dashboard/providers/traffic_providers.dart'`
// was intentionally dropped — `core/` must not re-export from `modules/`.
// Consumers that relied on it (dashboard_page, live_status_card, main,
// the stream-providers dispose-guard test) now import that file directly.

export 'core_preferences_providers.dart';
export 'core_runtime_providers.dart';
