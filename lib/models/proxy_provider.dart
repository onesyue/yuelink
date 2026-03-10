/// A proxy provider from mihomo.
class ProxyProviderInfo {
  final String name;
  final String type; // HTTP, File, etc.
  final String vehicleType;
  final int count; // number of proxies
  final String? updatedAt;
  final List<String> proxies;

  const ProxyProviderInfo({
    required this.name,
    required this.type,
    required this.vehicleType,
    required this.count,
    this.updatedAt,
    this.proxies = const [],
  });

  factory ProxyProviderInfo.fromJson(
      String name, Map<String, dynamic> json) {
    final proxiesList = (json['proxies'] as List?)
            ?.map((p) => (p as Map<String, dynamic>)['name'] as String? ?? '')
            .where((n) => n.isNotEmpty)
            .toList() ??
        [];

    return ProxyProviderInfo(
      name: name,
      type: json['type'] as String? ?? '',
      vehicleType: json['vehicleType'] as String? ?? '',
      count: proxiesList.length,
      updatedAt: json['updatedAt'] as String?,
      proxies: proxiesList,
    );
  }
}
