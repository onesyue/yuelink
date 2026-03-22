/// Pure data class for announcements.
/// No Flutter or network dependencies — domain layer only.
class Announcement {
  final int? id;
  final String title;
  final String content;
  final int? createdAt;

  Announcement({
    this.id,
    required this.title,
    required this.content,
    this.createdAt,
  });

  DateTime? get createdDate {
    if (createdAt == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(createdAt! * 1000);
  }

  factory Announcement.fromJson(Map<String, dynamic> json) {
    return Announcement(
      id: _toInt(json['id']),
      title: json['title'] as String? ?? '',
      content: json['content'] as String? ?? '',
      createdAt: _toInt(json['created_at']),
    );
  }

  /// XBoard may return numeric fields as int, double, or bool (tinyint).
  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is bool) return v ? 1 : 0;
    return null;
  }
}
