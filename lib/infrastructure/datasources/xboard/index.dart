/// Public surface of the XBoard panel API client.
///
/// Callers should import this file (or `xboard/api.dart`) — never the
/// internal `client.dart` (transport) directly. The split is:
///
///   • api.dart    — XBoardApi facade (endpoint methods)
///   • models.dart — LoginResponse / UserProfile / SubscribeData / SubscribeResult
///   • errors.dart — XBoardApiException
///   • client.dart — internal HTTP transport (do not import directly)
library;

export 'api.dart';
export 'errors.dart';
export 'models.dart';
