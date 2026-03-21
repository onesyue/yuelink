import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/domain/models/traffic_history.dart';

void main() {
  group('TrafficHistory', () {
    test('starts empty with count 0', () {
      final h = TrafficHistory();
      expect(h.count, 0);
      expect(h.version, 0);
      expect(h.upHistory(), isEmpty);
      expect(h.downHistory(), isEmpty);
    });

    test('add increments version and count', () {
      final h = TrafficHistory();
      h.add(100, 200);
      expect(h.count, 1);
      expect(h.version, 1);
      h.add(300, 400);
      expect(h.count, 2);
      expect(h.version, 2);
    });

    test('upHistory returns correct values oldest-first', () {
      final h = TrafficHistory();
      h.add(10, 100);
      h.add(20, 200);
      h.add(30, 300);

      final up = h.upHistory(seconds: 3);
      expect(up, [10.0, 20.0, 30.0]);

      final down = h.downHistory(seconds: 3);
      expect(down, [100.0, 200.0, 300.0]);
    });

    test('history clamps to available count', () {
      final h = TrafficHistory();
      h.add(10, 100);
      h.add(20, 200);

      // Requesting more than available returns only what exists
      final up = h.upHistory(seconds: 100);
      expect(up.length, 2);
      expect(up, [10.0, 20.0]);
    });

    test('history returns last N seconds', () {
      final h = TrafficHistory();
      for (var i = 1; i <= 10; i++) {
        h.add(i, i * 10);
      }

      final last3 = h.upHistory(seconds: 3);
      expect(last3, [8.0, 9.0, 10.0]);
    });

    test('ring buffer wraps correctly at capacity', () {
      final h = TrafficHistory();
      // Fill to capacity
      for (var i = 0; i < TrafficHistory.capacity; i++) {
        h.add(i, i);
      }
      expect(h.count, TrafficHistory.capacity);

      // Add one more — wraps around
      h.add(9999, 9999);
      expect(h.count, TrafficHistory.capacity);

      final last = h.upHistory(seconds: 1);
      expect(last, [9999.0]);

      // First element should now be index 1 (index 0 was overwritten)
      final first = h.upHistory(seconds: TrafficHistory.capacity);
      expect(first.first, 1.0);
      expect(first.last, 9999.0);
    });

    test('downSampled returns cached result on same version+range', () {
      final h = TrafficHistory();
      for (var i = 0; i < 120; i++) {
        h.add(i, i * 2);
      }

      final first = h.downSampled(seconds: 120, targetPoints: 60);
      final second = h.downSampled(seconds: 120, targetPoints: 60);
      expect(identical(first, second), isTrue);
    });

    test('upSampled returns cached result on same version+range', () {
      final h = TrafficHistory();
      for (var i = 0; i < 120; i++) {
        h.add(i, i);
      }

      final first = h.upSampled(seconds: 120, targetPoints: 60);
      final second = h.upSampled(seconds: 120, targetPoints: 60);
      expect(identical(first, second), isTrue);
    });

    test('downSampled cache invalidates on new data', () {
      final h = TrafficHistory();
      for (var i = 0; i < 120; i++) {
        h.add(i, i);
      }

      final first = h.downSampled(seconds: 120);
      h.add(999, 999);
      final second = h.downSampled(seconds: 120);
      expect(identical(first, second), isFalse);
    });

    test('downsample averages buckets correctly', () {
      final h = TrafficHistory();
      // 4 points downsampled to 2 → each bucket averages 2 values
      h.add(10, 10);
      h.add(20, 20);
      h.add(30, 30);
      h.add(40, 40);

      final sampled = h.downSampled(seconds: 4, targetPoints: 2);
      expect(sampled.length, 2);
      // Bucket 0: avg(10, 20) = 15
      // Bucket 1: avg(30, 40) = 35
      expect(sampled[0], 15.0);
      expect(sampled[1], 35.0);
    });

    test('downsample returns raw data when <= targetPoints', () {
      final h = TrafficHistory();
      h.add(10, 10);
      h.add(20, 20);

      final sampled = h.downSampled(seconds: 2, targetPoints: 60);
      expect(sampled, [10.0, 20.0]);
    });

    test('p90 calculates 90th percentile', () {
      final h = TrafficHistory();
      // Add 10 values: 1-10 for both up and down
      for (var i = 1; i <= 10; i++) {
        h.add(i, i);
      }

      final p = h.p90(seconds: 10);
      // Combined non-zero sorted: [1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10]
      // 90th percentile index: ((20-1) * 0.9).round() = 17 → value = 9
      expect(p, 9.0);
    });

    test('p90 returns 0 for empty history', () {
      final h = TrafficHistory();
      expect(h.p90(), 0);
    });

    test('copy creates independent snapshot', () {
      final h = TrafficHistory();
      h.add(100, 200);
      h.add(300, 400);

      final c = h.copy();
      expect(c.count, h.count);
      expect(c.version, h.version);
      expect(c.upHistory(seconds: 2), h.upHistory(seconds: 2));

      // Modifying original doesn't affect copy
      h.add(999, 999);
      expect(h.version, isNot(c.version));
      expect(c.upHistory(seconds: 2), [100.0, 300.0]);
    });
  });
}
