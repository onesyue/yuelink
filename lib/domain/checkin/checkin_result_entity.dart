/// Result of a check-in operation.
///
/// Pure Dart — no Flutter or network dependencies.
class CheckinResult {
  /// "traffic" or "balance"
  final String type;

  /// Raw amount: bytes for traffic, 分 (cents) for balance
  final int amount;

  /// Human-readable amount text (e.g. "10GB", "0.6元")
  final String amountText;

  /// Whether the user has already checked in today
  final bool alreadyChecked;

  const CheckinResult({
    required this.type,
    required this.amount,
    required this.amountText,
    required this.alreadyChecked,
  });

  factory CheckinResult.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String? ?? 'traffic';
    final amount = _toInt(json['amount']) ?? 0;
    // Prefer server-provided text; fall back to local formatting so the UI
    // always shows a meaningful value even if the server omits amount_text.
    final serverText = json['amount_text'] as String?;
    final amountText = (serverText != null && serverText.isNotEmpty)
        ? serverText
        : _formatAmount(type, amount);

    return CheckinResult(
      type: type,
      amount: amount,
      amountText: amountText,
      alreadyChecked: json['already_checked'] == true,
    );
  }

  /// Format amount locally: traffic → human-readable bytes, balance → yuan.
  static String _formatAmount(String type, int amount) {
    if (type == 'balance') {
      // amount is in cents (分)
      final yuan = amount / 100.0;
      return '${yuan.toStringAsFixed(2)}元';
    }
    // traffic: amount is in bytes
    if (amount <= 0) return '0 MB';
    const kb = 1024;
    const mb = kb * 1024;
    const gb = mb * 1024;
    const tb = gb * 1024;
    if (amount >= tb) return '${(amount / tb).toStringAsFixed(2)} TB';
    if (amount >= gb) return '${(amount / gb).toStringAsFixed(2)} GB';
    if (amount >= mb) return '${(amount / mb).toStringAsFixed(2)} MB';
    return '${(amount / kb).toStringAsFixed(2)} KB';
  }

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is bool) return v ? 1 : 0;
    return null;
  }
}
