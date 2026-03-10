/// A single active proxy connection from mihomo /connections API.
class ActiveConnection {
  final String id;
  final String network; // tcp / udp
  final String type; // HTTP / HTTPS / SOCKS5 / TUN
  final String host;
  final String destinationIp;
  final String destinationPort;
  final String sourceIp;
  final String sourcePort;
  final String processPath;
  final String rule;
  final String rulePayload;
  final List<String> chains;
  final int upload;
  final int download;
  final int curUploadSpeed; // bytes/s
  final int curDownloadSpeed; // bytes/s
  final DateTime start;

  const ActiveConnection({
    required this.id,
    required this.network,
    required this.type,
    required this.host,
    required this.destinationIp,
    required this.destinationPort,
    required this.sourceIp,
    required this.sourcePort,
    required this.processPath,
    required this.rule,
    required this.rulePayload,
    required this.chains,
    required this.upload,
    required this.download,
    required this.curUploadSpeed,
    required this.curDownloadSpeed,
    required this.start,
  });

  factory ActiveConnection.fromJson(Map<String, dynamic> json) {
    final meta = json['metadata'] as Map<String, dynamic>? ?? {};
    return ActiveConnection(
      id: json['id'] as String? ?? '',
      network: meta['network'] as String? ?? '',
      type: meta['type'] as String? ?? '',
      host: meta['host'] as String? ??
          meta['destinationIP'] as String? ?? '',
      destinationIp: meta['destinationIP'] as String? ?? '',
      destinationPort: meta['destinationPort'] as String? ?? '',
      sourceIp: meta['sourceIP'] as String? ?? '',
      sourcePort: meta['sourcePort'] as String? ?? '',
      processPath: meta['processPath'] as String? ??
          meta['process'] as String? ?? '',
      rule: json['rule'] as String? ?? '',
      rulePayload: json['rulePayload'] as String? ?? '',
      chains: (json['chains'] as List?)?.cast<String>() ?? [],
      upload: (json['upload'] as num?)?.toInt() ?? 0,
      download: (json['download'] as num?)?.toInt() ?? 0,
      curUploadSpeed: (json['curUploadSpeed'] as num?)?.toInt() ?? 0,
      curDownloadSpeed: (json['curDownloadSpeed'] as num?)?.toInt() ?? 0,
      start: json['start'] != null
          ? DateTime.tryParse(json['start'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  /// Display target: host if available, otherwise destinationIp:port
  String get target {
    if (host.isNotEmpty) return host;
    if (destinationIp.isNotEmpty) return '$destinationIp:$destinationPort';
    return '';
  }

  /// Process name (basename of processPath)
  String get processName {
    if (processPath.isEmpty) return '';
    return processPath.split(RegExp(r'[/\\]')).last;
  }

  /// Duration since connection started
  Duration get duration => DateTime.now().difference(start);

  String get durationText {
    final d = duration;
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
    if (d.inMinutes > 0) return '${d.inMinutes}m ${d.inSeconds % 60}s';
    return '${d.inSeconds}s';
  }
}

/// Snapshot from /connections endpoint
class ConnectionsSnapshot {
  final List<ActiveConnection> connections;
  final int downloadTotal;
  final int uploadTotal;

  const ConnectionsSnapshot({
    required this.connections,
    required this.downloadTotal,
    required this.uploadTotal,
  });

  factory ConnectionsSnapshot.fromJson(Map<String, dynamic> json) {
    final list = (json['connections'] as List? ?? [])
        .cast<Map<String, dynamic>>()
        .map(ActiveConnection.fromJson)
        .toList();
    return ConnectionsSnapshot(
      connections: list,
      downloadTotal: (json['downloadTotal'] as num?)?.toInt() ?? 0,
      uploadTotal: (json['uploadTotal'] as num?)?.toInt() ?? 0,
    );
  }
}
