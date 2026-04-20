import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/kernel/config_template.dart';
import '../../infrastructure/repositories/profile_repository.dart';
import '../profiles/providers/profiles_providers.dart';

/// A single non-active subscription profile and its proxy node names.
class CrossProfileEntry {
  final String profileId;
  final String profileName;
  final List<String> nodeNames;

  const CrossProfileEntry({
    required this.profileId,
    required this.profileName,
    required this.nodeNames,
  });
}

/// All non-active profiles with their proxy node names.
///
/// Used by the chain picker sheet to show nodes from other subscriptions.
final crossProfileNodesProvider =
    FutureProvider<List<CrossProfileEntry>>((ref) async {
  final profilesAsync = ref.watch(profilesProvider);
  final activeId = ref.watch(activeProfileIdProvider);

  final profiles = profilesAsync.value;
  if (profiles == null || profiles.isEmpty) return [];

  final repo = ref.read(profileRepositoryProvider);
  final result = <CrossProfileEntry>[];

  for (final profile in profiles) {
    if (profile.id == activeId) continue;
    try {
      final configYaml = await repo.loadConfig(profile.id);
      if (configYaml == null || configYaml.isEmpty) continue;
      final names = ConfigTemplate.extractProxyNames(configYaml);
      if (names.isNotEmpty) {
        result.add(CrossProfileEntry(
          profileId: profile.id,
          profileName: profile.name,
          nodeNames: names,
        ));
      }
    } catch (e) {
      debugPrint('[CrossProfileNodes] failed to load profile ${profile.id}: $e');
    }
  }

  return result;
});
