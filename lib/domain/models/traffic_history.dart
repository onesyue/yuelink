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

  /// Monotonically increasing version. Bumped on every [add] so that
  /// Riverpod StateProvider can detect changes without a full [copy].
  int version = 0;

  // ── Downsample cache ─────────────────────────────────────────────
  // Avoids recalculating O(n) downsampling on every frame.
  int _cachedUpVersion = -1;
  int _cachedUpRange = -1;
  List<double> _cachedUp = const [];
  int _cachedDownVersion = -1;
  int _cachedDownRange = -1;
  List<double> _cachedDown = const [];

  TrafficHistory()
      : _up = List.filled(capacity, 0.0),
        _down = List.filled(capacity, 0.0);

  /// Add a new data point (bytes/s).
  void add(int upBps, int downBps) {
    _up[_index] = upBps.toDouble();
    _down[_index] = downBps.toDouble();
    _index = (_index + 1) % capacity;
    if (_index == 0) _full = true;
    version++;
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
  ///
  /// Results are cached by (version, seconds) — calling with the same
  /// parameters returns the same list without recomputing.
  List<double> upSampled({int seconds = 60, int targetPoints = 60}) {
    if (_cachedUpVersion == version && _cachedUpRange == seconds) {
      return _cachedUp;
    }
    _cachedUp = _downsample(_slice(_up, seconds), targetPoints);
    _cachedUpVersion = version;
    _cachedUpRange = seconds;
    return _cachedUp;
  }

  List<double> downSampled({int seconds = 60, int targetPoints = 60}) {
    if (_cachedDownVersion == version && _cachedDownRange == seconds) {
      return _cachedDown;
    }
    _cachedDown = _downsample(_slice(_down, seconds), targetPoints);
    _cachedDownVersion = version;
    _cachedDownRange = seconds;
    return _cachedDown;
  }

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
  /// Used only for chart lock (frozen snapshot).
  TrafficHistory copy() {
    final c = TrafficHistory();
    for (var i = 0; i < capacity; i++) {
      c._up[i] = _up[i];
      c._down[i] = _down[i];
    }
    c._index = _index;
    c._full = _full;
    c.version = version;
    return c;
  }

  /// Returns the last [seconds] raw samples in chronological order (oldest first).
  ///
  /// Writes directly in forward order to avoid reversing the list.
  List<double> _slice(List<double> buf, int seconds) {
    final c = count;
    if (c == 0) return const [];
    final n = seconds.clamp(1, c);
    final result = List<double>.filled(n, 0.0);
    // Start index: the oldest sample we want
    final startOffset = _index - n;
    for (var i = 0; i < n; i++) {
      result[i] = buf[(startOffset + i + capacity) % capacity];
    }
    return result;
  }

  /// Downsamples [data] to [targetPoints] by averaging consecutive buckets.
  static List<double> _downsample(List<double> data, int targetPoints) {
    if (data.isEmpty) return const [];
    if (data.length <= targetPoints) return data;
    final bucketSize = data.length / targetPoints;
    final result = List<double>.filled(targetPoints, 0.0);
    for (var i = 0; i < targetPoints; i++) {
      final start = (i * bucketSize).round();
      final end = ((i + 1) * bucketSize).round().clamp(0, data.length);
      if (start >= end) continue;
      var sum = 0.0;
      for (var j = start; j < end; j++) {
        sum += data[j];
      }
      result[i] = sum / (end - start);
    }
    return result;
  }
}
