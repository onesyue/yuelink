/// Domain-layer error for all store operations. `StoreRepository` traps
/// every infrastructure exception (`XBoardApiException`, `SocketException`,
/// `TimeoutException`, etc.) and rethrows one of the subtypes below, so
/// modules/ and widgets never see raw datasource exceptions.
///
/// Subtypes are intentionally narrow — branching is by type, user-facing
/// text is the `message` field. Deeper categorisation (e.g. distinguishing
/// coupon-invalid from plan-not-found) stays string-level; add a new
/// sealed variant only when we actually branch on it.
sealed class StoreError implements Exception {
  const StoreError(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Transport failure — socket, timeout, or HTTP-level error before the
/// server produced a response. Retry is meaningful.
final class StoreErrorNetwork extends StoreError {
  const StoreErrorNetwork(super.message);
}

/// 401 / 403 from XBoard. AuthNotifier already auto-logs-out on these
/// upstream; UI should display the message but not prompt retry on the
/// same call.
final class StoreErrorUnauthorized extends StoreError {
  const StoreErrorUnauthorized(super.message, {required this.statusCode});

  final int statusCode;
}

/// Any other XBoard-originated failure — HTTP 200 with `status:"fail"`,
/// or HTTP 4xx/5xx that isn't 401/403. `statusCode` is XBoard's raw HTTP
/// code; 200 signals business-level rejection.
final class StoreErrorApi extends StoreError {
  const StoreErrorApi(super.message, {required this.statusCode});

  final int statusCode;
}

/// Anything not categorised above — rare, indicates an exception type
/// we didn't anticipate. Telemetry treats these as higher-priority than
/// the typed variants.
final class StoreErrorUnknown extends StoreError {
  const StoreErrorUnknown(super.message);
}
