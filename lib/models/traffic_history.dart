/// A fixed-size ring buffer that stores recent traffic data points for charting.
///
/// Capacity is 1800 samples (30 minutes at 1 sample/second).
/// The chart view downsamples to ~60 display points regardless of range,
/// so chart rendering cost stays constant across all time ranges.
class TrafficHistory {
  static const int capacity = 1800; // 30 minutes at 1s/sample

  final List<double> _up;
  final List<double> _down;
  int _index = 0;
  bool _full = false;

  TrafficHistory()
      : _up = List.filled(capacity, 0.0),
        _down = List.filled(capacity, 0.0);

  /// Add a new data point (bytes/s).
  void add(int upBps, int downBps) {
    _up[_index] = upBps.toDouble();
    _down[_index] = downBps.toDouble();
    _index = (_index + 1) % capacity;
    if (_index == 0) _full = true;
  }

  int get count => _full ? capacity : _index;

  /// Upload speed history for the last [seconds] seconds, oldest first.
  /// Returns at most [seconds] raw points (no downsampling).
  List<double> upHistory({int seconds = 60}) => _slice(_up, seconds);

  /// Download speed history for the last [seconds] seconds, oldest first.
  List<double> downHistory({int seconds = 60}) => _slice(_down, seconds);

  /// Downsampled history suitable for chart rendering (~60 display points).
  ///
  /// Groups raw samples into [targetPoints] buckets and averages each bucket.
  /// This keeps chart rendering cost constant regardless of [seconds].
  List<double> upSampled({int seconds = 60, int targetPoints = 60}) =>
      _downsample(_slice(_up, seconds), targetPoints);

  List<double> downSampled({int seconds = 60, int targetPoints = 60}) =>
      _downsample(_slice(_down, seconds), targetPoints);

  /// 90th-percentile of sampled up+down values for a given range.
  double p90({int seconds = 60}) {
    final all = [
      ...upSampled(seconds: seconds),
      ...downSampled(seconds: seconds),
    ]
      ..removeWhere((v) => v == 0)
      ..sort();
    if (all.isEmpty) return 0;
    final idx = ((all.length - 1) * 0.9).round();
    return all[idx];
  }

  /// Returns a new [TrafficHistory] with the same ring-buffer state.
  /// Required because Riverpod's StateProvider uses identical() to detect
  /// changes — mutating in place and setting the same reference never notifies.
  TrafficHistory copy() {
    final c = TrafficHistory();
    for (var i = 0; i < capacity; i++) {
      c._up[i] = _up[i];
      c._down[i] = _down[i];
    }
    c._index = _index;
    c._full = _full;
    return c;
  }

  /// Returns the last [seconds] raw samples in chronological order (oldest first).
  List<double> _slice(List<double> buf, int seconds) {
    final n = seconds.clamp(1, count);
    if (n == 0) return [];
    final result = <double>[];
    // Walk backwards from current write head to collect `n` samples,
    // then reverse to get oldest-first order.
    for (var i = 1; i <= n; i++) {
      final idx = (_index - i + capacity) % capacity;
      result.add(buf[idx]);
    }
    return result.reversed.toList();
  }

  /// Downsamples [data] to [targetPoints] by averaging consecutive buckets.
  List<double> _downsample(List<double> data, int targetPoints) {
    if (data.isEmpty) return [];
    if (data.length <= targetPoints) return data;
    final bucketSize = data.length / targetPoints;
    final result = <double>[];
    for (var i = 0; i < targetPoints; i++) {
      final start = (i * bucketSize).round();
      final end = ((i + 1) * bucketSize).round().clamp(0, data.length);
      if (start >= end) continue;
      final sum = data.sublist(start, end).fold(0.0, (a, b) => a + b);
      result.add(sum / (end - start));
    }
    return result;
  }
}
