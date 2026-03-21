/// Lightweight circuit breaker — temporarily disables an endpoint after
/// [threshold] consecutive failures.  Resets after [cooldown] elapses.
///
/// States: closed (normal) → open (blocking) → half-open (single probe).
class CircuitBreaker {
  final int threshold;
  final Duration cooldown;

  int _failures = 0;
  DateTime? _openedAt;

  CircuitBreaker({this.threshold = 5, this.cooldown = const Duration(seconds: 30)});

  bool get isOpen {
    if (_openedAt == null) return false;
    if (DateTime.now().difference(_openedAt!) >= cooldown) {
      // Transition to half-open — allow one probe
      return false;
    }
    return true;
  }

  /// Record a successful call — resets the breaker.
  void recordSuccess() {
    _failures = 0;
    _openedAt = null;
  }

  /// Record a failure. Returns true if the breaker just tripped open.
  bool recordFailure() {
    _failures++;
    if (_failures >= threshold) {
      _openedAt = DateTime.now();
      return true;
    }
    return false;
  }

  /// Reset the breaker manually.
  void reset() {
    _failures = 0;
    _openedAt = null;
  }
}
