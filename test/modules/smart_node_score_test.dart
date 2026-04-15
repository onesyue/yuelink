import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/modules/nodes/smart_score.dart';

void main() {
  group('smartNodeScore', () {
    test('fresh node (no data) → score 0', () {
      expect(smartNodeScore('node-a', {}), 0);
      expect(smartNodeScore('node-a', {'other': 100}), 0);
    });

    test('perfect node (50ms) → score > 95', () {
      final score = smartNodeScore('fast', {'fast': 50});
      expect(score, greaterThan(95));
      expect(score, lessThanOrEqualTo(100));
    });

    test('mediocre node (500ms) → score in [50, 80]', () {
      final score = smartNodeScore('mid', {'mid': 500});
      expect(score, inInclusiveRange(50, 80));
    });

    test('failed node (delay = -1) → score 0', () {
      expect(smartNodeScore('dead', {'dead': -1}), 0);
      expect(smartNodeScore('dead', {'dead': 0}), 0);
    });

    test('very slow node (1500ms+) → score 0', () {
      expect(smartNodeScore('slow', {'slow': 1500}), 0);
      expect(smartNodeScore('slow', {'slow': 3000}), 0);
    });
  });

  group('sortBySmartScore', () {
    test('fast < medium < slow — picks fastest first', () {
      final nodes = ['slow', 'fast', 'medium'];
      final delays = {'fast': 50, 'medium': 400, 'slow': 1200};
      final sorted = sortBySmartScore(nodes, delays);
      expect(sorted, ['fast', 'medium', 'slow']);
    });

    test('nodes with data beat nodes without', () {
      final nodes = ['missing', 'ok', 'failed'];
      final delays = {'ok': 100, 'failed': -1};
      final sorted = sortBySmartScore(nodes, delays);
      expect(sorted.first, 'ok');
      // missing & failed both score 0 — stable order preserves input order
      expect(sorted.sublist(1), ['missing', 'failed']);
    });

    test('empty list → empty list', () {
      expect(sortBySmartScore(<String>[], {}), <String>[]);
    });

    test('stable for equal scores', () {
      final nodes = ['a', 'b', 'c'];
      final delays = {'a': 100, 'b': 100, 'c': 100};
      final sorted = sortBySmartScore(nodes, delays);
      expect(sorted, ['a', 'b', 'c']);
    });
  });
}
