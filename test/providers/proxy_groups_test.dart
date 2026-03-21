import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/domain/models/proxy.dart';

void main() {
  group('ProxyGroup', () {
    test('basic construction', () {
      final g = ProxyGroup(
        name: 'PROXIES',
        type: 'Selector',
        all: ['HK-01', 'JP-01', 'US-01'],
        now: 'HK-01',
      );

      expect(g.name, 'PROXIES');
      expect(g.type, 'Selector');
      expect(g.all.length, 3);
      expect(g.now, 'HK-01');
    });

    test('empty group', () {
      final g = ProxyGroup(
        name: 'Empty',
        type: 'URLTest',
        all: [],
        now: '',
      );

      expect(g.all, isEmpty);
      expect(g.now, '');
    });
  });

  group('Proxy groups data parsing', () {
    // Tests the core logic that ProxyGroupsNotifier.refresh() uses
    // to transform the mihomo /proxies API response into ordered groups.

    test('parses proxies map into groups ordered by GLOBAL all', () {
      final proxiesMap = <String, dynamic>{
        'GLOBAL': {
          'type': 'Selector',
          'name': 'GLOBAL',
          'now': 'PROXIES',
          'all': ['PROXIES', 'Auto', 'DIRECT'],
        },
        'PROXIES': {
          'type': 'Selector',
          'name': 'PROXIES',
          'now': 'HK-01',
          'all': ['HK-01', 'JP-01'],
        },
        'Auto': {
          'type': 'URLTest',
          'name': 'Auto',
          'now': 'JP-01',
          'all': ['HK-01', 'JP-01'],
        },
        'DIRECT': {
          'type': 'Direct',
          'name': 'DIRECT',
        },
        'HK-01': {'type': 'ss', 'name': 'HK-01'},
        'JP-01': {'type': 'vmess', 'name': 'JP-01'},
      };

      // Extract groups (same logic as ProxyGroupsNotifier.refresh)
      final groupsMap = <String, ProxyGroup>{};
      final nodeTypes = <String, String>{};
      for (final entry in proxiesMap.entries) {
        final info = entry.value as Map<String, dynamic>;
        final type = info['type'] as String? ?? '';
        if (info.containsKey('all')) {
          groupsMap[entry.key] = ProxyGroup(
            name: entry.key,
            type: type,
            all: (info['all'] as List?)?.cast<String>() ?? [],
            now: info['now'] as String? ?? '',
          );
        } else if (type.isNotEmpty) {
          nodeTypes[entry.key] = type;
        }
      }

      // Order by GLOBAL's all, excluding GLOBAL itself
      final globalAll =
          (proxiesMap['GLOBAL']?['all'] as List?)?.cast<String>();
      final groups = <ProxyGroup>[];
      if (globalAll != null) {
        for (final name in globalAll) {
          final g = groupsMap.remove(name);
          if (g != null) groups.add(g);
        }
      }
      groups.addAll(groupsMap.values.where((g) => g.name != 'GLOBAL'));

      // Verify ordering matches GLOBAL's all
      expect(groups.length, 2); // PROXIES, Auto (DIRECT has no 'all')
      expect(groups[0].name, 'PROXIES');
      expect(groups[1].name, 'Auto');

      // Verify node types extracted
      expect(nodeTypes['HK-01'], 'ss');
      expect(nodeTypes['JP-01'], 'vmess');
    });

    test('groups not in GLOBAL are appended at end', () {
      final proxiesMap = <String, dynamic>{
        'GLOBAL': {
          'type': 'Selector',
          'name': 'GLOBAL',
          'now': 'Main',
          'all': ['Main', 'DIRECT'],
        },
        'Main': {
          'type': 'Selector',
          'name': 'Main',
          'now': 'Node1',
          'all': ['Node1'],
        },
        'Extra': {
          'type': 'Selector',
          'name': 'Extra',
          'now': 'Node2',
          'all': ['Node2'],
        },
      };

      final groupsMap = <String, ProxyGroup>{};
      for (final entry in proxiesMap.entries) {
        final info = entry.value as Map<String, dynamic>;
        if (info.containsKey('all')) {
          groupsMap[entry.key] = ProxyGroup(
            name: entry.key,
            type: info['type'] as String? ?? '',
            all: (info['all'] as List?)?.cast<String>() ?? [],
            now: info['now'] as String? ?? '',
          );
        }
      }

      final globalAll =
          (proxiesMap['GLOBAL']?['all'] as List?)?.cast<String>();
      final groups = <ProxyGroup>[];
      if (globalAll != null) {
        for (final name in globalAll) {
          final g = groupsMap.remove(name);
          if (g != null) groups.add(g);
        }
      }
      groups.addAll(groupsMap.values.where((g) => g.name != 'GLOBAL'));

      expect(groups.length, 2);
      expect(groups[0].name, 'Main'); // from GLOBAL order
      expect(groups[1].name, 'Extra'); // appended (not in GLOBAL)
    });

    test('handles missing GLOBAL gracefully', () {
      final proxiesMap = <String, dynamic>{
        'MyGroup': {
          'type': 'Selector',
          'name': 'MyGroup',
          'now': 'Node1',
          'all': ['Node1'],
        },
      };

      final groupsMap = <String, ProxyGroup>{};
      for (final entry in proxiesMap.entries) {
        final info = entry.value as Map<String, dynamic>;
        if (info.containsKey('all')) {
          groupsMap[entry.key] = ProxyGroup(
            name: entry.key,
            type: info['type'] as String? ?? '',
            all: (info['all'] as List?)?.cast<String>() ?? [],
            now: info['now'] as String? ?? '',
          );
        }
      }

      final globalAll =
          (proxiesMap['GLOBAL']?['all'] as List?)?.cast<String>();
      final groups = <ProxyGroup>[];
      if (globalAll != null) {
        for (final name in globalAll) {
          final g = groupsMap.remove(name);
          if (g != null) groups.add(g);
        }
      }
      groups.addAll(groupsMap.values.where((g) => g.name != 'GLOBAL'));

      expect(groups.length, 1);
      expect(groups[0].name, 'MyGroup');
    });

    test('empty proxies map returns empty groups', () {
      final groupsMap = <String, ProxyGroup>{};
      final groups = <ProxyGroup>[];
      groups.addAll(groupsMap.values);
      expect(groups, isEmpty);
    });
  });

  group('Delay results provider logic', () {
    test('delay results merge correctly', () {
      // Simulates how delay test results accumulate
      var results = <String, int>{};

      // First batch
      results = Map.from(results);
      results['HK-01'] = 120;
      results['JP-01'] = 85;

      expect(results['HK-01'], 120);
      expect(results['JP-01'], 85);

      // Update single node
      results = Map.from(results);
      results['HK-01'] = 95;

      expect(results['HK-01'], 95);
      expect(results['JP-01'], 85);
    });

    test('delay -1 indicates timeout/failure', () {
      final results = <String, int>{'Node1': -1, 'Node2': 100};
      expect(results['Node1'], -1);
      expect(results['Node2']! > 0, isTrue);
    });
  });
}
