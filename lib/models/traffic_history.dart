/// A fixed-size ring buffer that stores recent traffic data points for charting.
class TrafficHistory {
  static const int capacity = 60; // 60 seconds of history

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

  /// Upload speed history, oldest first.
  List<double> get upHistory => _ordered(_up);

  /// Download speed history, oldest first.
  List<double> get downHistory => _ordered(_down);

  double get maxDown =>
      _down.reduce((a, b) => a > b ? a : b);

  List<double> _ordered(List<double> buf) {
    if (!_full) return buf.sublist(0, _index);
    final result = <double>[];
    for (var i = _index; i < capacity; i++) {
      result.add(buf[i]);
    }
    for (var i = 0; i < _index; i++) {
      result.add(buf[i]);
    }
    return result;
  }
}
