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

  /// Pre-computed process basename (cached in fromJson, never recomputed).
  /// Was a getter that ran RegExp.split on every row render — moving to
  /// a final field eliminates ~hundreds of regex allocs per frame under load.
  final String processName;

  /// Pre-computed display target (host or "ip:port"). Cached for the same
  /// reason as [processName].
  final String target;

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
    required this.processName,
    required this.target,
  });

  factory ActiveConnection.fromJson(Map<String, dynamic> json) {
    final meta = json['metadata'] as Map<String, dynamic>? ?? {};
    final host = meta['host'] as String? ??
        meta['destinationIP'] as String? ??
        '';
    final destinationIp = meta['destinationIP'] as String? ?? '';
    final destinationPort = meta['destinationPort'] as String? ?? '';
    final processPath = meta['processPath'] as String? ??
        meta['process'] as String? ??
        '';
    return ActiveConnection(
      id: json['id'] as String? ?? '',
      network: meta['network'] as String? ?? '',
      type: meta['type'] as String? ?? '',
      host: host,
      destinationIp: destinationIp,
      destinationPort: destinationPort,
      sourceIp: meta['sourceIP'] as String? ?? '',
      sourcePort: meta['sourcePort'] as String? ?? '',
      processPath: processPath,
      rule: json['rule'] as String? ?? '',
      rulePayload: json['rulePayload'] as String? ?? '',
      chains: (json['chains'] as List?)?.cast<String>() ?? const [],
      upload: (json['upload'] as num?)?.toInt() ?? 0,
      download: (json['download'] as num?)?.toInt() ?? 0,
      curUploadSpeed: (json['curUploadSpeed'] as num?)?.toInt() ?? 0,
      curDownloadSpeed: (json['curDownloadSpeed'] as num?)?.toInt() ?? 0,
      start: json['start'] != null
          ? DateTime.tryParse(json['start'] as String) ?? DateTime.now()
          : DateTime.now(),
      processName: _computeProcessName(processPath),
      target: _computeTarget(host, destinationIp, destinationPort),
    );
  }

  /// Manual basename — avoids `split(RegExp(r'[/\\]')).last` which allocates
  /// a regex match list every call. Hot path under connection list rendering.
  static String _computeProcessName(String path) {
    if (path.isEmpty) return '';
    var i = path.lastIndexOf('/');
    final j = path.lastIndexOf('\\');
    if (j > i) i = j;
    return i < 0 ? path : path.substring(i + 1);
  }

  static String _computeTarget(String host, String ip, String port) {
    if (host.isNotEmpty) return host;
    if (ip.isNotEmpty) return '$ip:$port';
    return '';
  }

  /// Reuse this instance with new traffic counters. All immutable string
  /// fields are passed by reference — no re-parsing, no regex, no string
  /// allocation. Used by [ConnectionRepository] to avoid re-parsing 500
  /// connections every 500 ms when only the byte counts have changed.
  ActiveConnection copyWithCounters({
    required int upload,
    required int download,
    required int curUploadSpeed,
    required int curDownloadSpeed,
  }) {
    return ActiveConnection(
      id: id,
      network: network,
      type: type,
      host: host,
      destinationIp: destinationIp,
      destinationPort: destinationPort,
      sourceIp: sourceIp,
      sourcePort: sourcePort,
      processPath: processPath,
      rule: rule,
      rulePayload: rulePayload,
      chains: chains,
      upload: upload,
      download: download,
      curUploadSpeed: curUploadSpeed,
      curDownloadSpeed: curDownloadSpeed,
      start: start,
      processName: processName,
      target: target,
    );
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

  /// Parse a /connections payload, optionally reusing previously-parsed
  /// [ActiveConnection] instances from [cache] (keyed by connection id).
  ///
  /// When an entry exists in [cache] AND its byte counters are unchanged,
  /// the exact same instance is reused (reference equality). When only
  /// counters changed, [ActiveConnection.copyWithCounters] is used to
  /// share all string fields. Brand-new connections are parsed normally.
  ///
  /// This eliminates ~99% of allocations on the steady-state path: a
  /// 500-connection BitTorrent burst that previously allocated 1000
  /// ActiveConnection objects per second now allocates only the deltas.
  factory ConnectionsSnapshot.fromJson(
    Map<String, dynamic> json, {
    Map<String, ActiveConnection>? cache,
  }) {
    // Cap at 500 to prevent memory spikes from BT/P2P with thousands of peers.
    final raw =
        (json['connections'] as List? ?? []).cast<Map<String, dynamic>>();
    final capped = raw.length > 500 ? raw.sublist(0, 500) : raw;

    final list = <ActiveConnection>[];
    for (final item in capped) {
      if (cache != null) {
        final id = item['id'] as String? ?? '';
        final cached = cache[id];
        if (cached != null) {
          final upload = (item['upload'] as num?)?.toInt() ?? 0;
          final download = (item['download'] as num?)?.toInt() ?? 0;
          if (cached.upload == upload && cached.download == download) {
            // Counters unchanged → reuse exact instance.
            list.add(cached);
            continue;
          }
          // Only counters changed → reuse string fields, swap counters.
          list.add(cached.copyWithCounters(
            upload: upload,
            download: download,
            curUploadSpeed: (item['curUploadSpeed'] as num?)?.toInt() ?? 0,
            curDownloadSpeed: (item['curDownloadSpeed'] as num?)?.toInt() ?? 0,
          ));
          continue;
        }
      }
      list.add(ActiveConnection.fromJson(item));
    }

    return ConnectionsSnapshot(
      connections: list,
      downloadTotal: (json['downloadTotal'] as num?)?.toInt() ?? 0,
      uploadTotal: (json['uploadTotal'] as num?)?.toInt() ?? 0,
    );
  }
}
