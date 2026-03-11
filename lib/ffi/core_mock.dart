import 'dart:math';

/// Mock implementation of the core controller for UI development.
///
/// Used when the Go native library is not available (e.g. no Go installed).
/// Simulates core behavior with fake data.
class CoreMock {
  CoreMock._();

  static CoreMock? _instance;
  static CoreMock get instance => _instance ??= CoreMock._();

  bool _isInit = false;
  bool _isRunning = false;
  final _random = Random();

  // ------------------------------------------------------------------
  // Lifecycle
  // ------------------------------------------------------------------

  bool init(String homeDir) {
    _isInit = true;
    return true;
  }

  bool start(String configYaml) {
    if (!_isInit) return false;
    _isRunning = true;
    return true;
  }

  void stop() => _isRunning = false;
  void shutdown() {
    _isRunning = false;
    _isInit = false;
  }

  bool get isRunning => _isRunning;

  // ------------------------------------------------------------------
  // Configuration
  // ------------------------------------------------------------------

  bool validateConfig(String configYaml) => true;
  bool updateConfig(String configYaml) => _isRunning;

  // ------------------------------------------------------------------
  // Proxies
  // ------------------------------------------------------------------

  static const _mockNodes = [
    '🇭🇰 香港 01',
    '🇭🇰 香港 02',
    '🇭🇰 香港 03',
    '🇯🇵 日本 01',
    '🇯🇵 日本 02',
    '🇸🇬 新加坡 01',
    '🇺🇸 美国 01',
    '🇺🇸 美国 02',
    '🇬🇧 英国 01',
    '🇩🇪 德国 01',
    '🇰🇷 韩国 01',
    '🇹🇼 台湾 01',
  ];

  String _selectedProxy = '🇭🇰 香港 01';
  String _selectedFallback = '🇯🇵 日本 01';

  Map<String, dynamic> getProxies() {
    if (!_isRunning) return {'proxies': {}};

    return {
      'proxies': {
        'GLOBAL': {
          'type': 'Selector',
          'now': '节点选择',
          'all': ['节点选择', '自动选择', '故障转移', 'DIRECT'],
        },
        '节点选择': {
          'type': 'Selector',
          'now': _selectedProxy,
          'all': _mockNodes,
        },
        '自动选择': {
          'type': 'URLTest',
          'now': '🇭🇰 香港 01',
          'all': _mockNodes,
        },
        '故障转移': {
          'type': 'Fallback',
          'now': _selectedFallback,
          'all': _mockNodes.take(5).toList(),
        },
        '流媒体': {
          'type': 'Selector',
          'now': '🇸🇬 新加坡 01',
          'all': ['🇭🇰 香港 01', '🇯🇵 日本 01', '🇸🇬 新加坡 01', '🇺🇸 美国 01'],
        },
        'AI 服务': {
          'type': 'Selector',
          'now': '🇺🇸 美国 01',
          'all': ['🇺🇸 美国 01', '🇺🇸 美国 02', '🇯🇵 日本 01', '🇸🇬 新加坡 01'],
        },
      },
    };
  }

  bool changeProxy(String groupName, String proxyName) {
    if (!_isRunning) return false;
    if (groupName == '节点选择') _selectedProxy = proxyName;
    if (groupName == '故障转移') _selectedFallback = proxyName;
    return true;
  }

  int testDelay(String proxyName, {String url = '', int timeoutMs = 5000}) {
    if (!_isRunning) return -1;
    // Simulate realistic delays
    if (proxyName.contains('香港')) return 30 + _random.nextInt(80);
    if (proxyName.contains('日本')) return 50 + _random.nextInt(100);
    if (proxyName.contains('新加坡')) return 60 + _random.nextInt(90);
    if (proxyName.contains('台湾')) return 40 + _random.nextInt(70);
    if (proxyName.contains('韩国')) return 55 + _random.nextInt(85);
    if (proxyName.contains('美国')) return 150 + _random.nextInt(200);
    if (proxyName.contains('英国')) return 200 + _random.nextInt(150);
    if (proxyName.contains('德国')) return 220 + _random.nextInt(130);
    return 100 + _random.nextInt(300);
  }

  // ------------------------------------------------------------------
  // Traffic & Connections
  // ------------------------------------------------------------------

  ({int up, int down}) getTraffic() {
    if (!_isRunning) return (up: 0, down: 0);
    return (
      up: _random.nextInt(500 * 1024),
      down: _random.nextInt(2 * 1024 * 1024),
    );
  }

  Map<String, dynamic> getConnections() {
    if (!_isRunning) {
      return {'connections': [], 'uploadTotal': 0, 'downloadTotal': 0};
    }

    return {
      'connections': [
        _mockConn('google.com', 443, 'tcp', '🇭🇰 香港 01', 'MATCH'),
        _mockConn('github.com', 443, 'tcp', '🇯🇵 日本 01', 'GeoIP'),
        _mockConn('api.openai.com', 443, 'tcp', '🇺🇸 美国 01', 'Domain'),
        _mockConn('cdn.jsdelivr.net', 443, 'tcp', 'DIRECT', 'Domain'),
        _mockConn('dns.google', 53, 'udp', '🇭🇰 香港 01', 'DomainKeyword'),
      ],
      'uploadTotal': 15 * 1024 * 1024 + _random.nextInt(5 * 1024 * 1024),
      'downloadTotal': 128 * 1024 * 1024 + _random.nextInt(50 * 1024 * 1024),
    };
  }

  Map<String, dynamic> _mockConn(
      String host, int port, String network, String chain, String rule) {
    return {
      'id': '${host.hashCode}',
      'metadata': {
        'host': host,
        'destinationPort': '$port',
        'network': network,
        'type': 'HTTPS',
      },
      'rule': rule,
      'chains': [chain],
      'upload': _random.nextInt(100000),
      'download': _random.nextInt(500000),
      'start': DateTime.now()
          .subtract(Duration(minutes: _random.nextInt(30)))
          .toIso8601String(),
    };
  }

  bool closeConnection(String connId) => true;
  void closeAllConnections() {}

  // ------------------------------------------------------------------
  // Rules
  // ------------------------------------------------------------------

  Map<String, dynamic> getRules() {
    if (!_isRunning) return {'rules': []};

    return {
      'rules': [
        {'type': 'DOMAIN-SUFFIX', 'payload': 'google.com', 'proxy': '节点选择'},
        {'type': 'DOMAIN-SUFFIX', 'payload': 'github.com', 'proxy': '节点选择'},
        {'type': 'DOMAIN-SUFFIX', 'payload': 'openai.com', 'proxy': 'AI 服务'},
        {'type': 'DOMAIN-SUFFIX', 'payload': 'gemini.google.com', 'proxy': 'AI 服务'},
        {'type': 'DOMAIN-SUFFIX', 'payload': 'youtube.com', 'proxy': '流媒体'},
        {'type': 'DOMAIN-SUFFIX', 'payload': 'netflix.com', 'proxy': '流媒体'},
        {'type': 'DOMAIN-SUFFIX', 'payload': 'spotify.com', 'proxy': '流媒体'},
        {'type': 'DOMAIN-KEYWORD', 'payload': 'twitter', 'proxy': '节点选择'},
        {'type': 'DOMAIN-KEYWORD', 'payload': 'telegram', 'proxy': '节点选择'},
        {'type': 'GEOIP', 'payload': 'CN', 'proxy': 'DIRECT'},
        {'type': 'GEOIP', 'payload': 'LAN', 'proxy': 'DIRECT'},
        {
          'type': 'RULE-SET',
          'payload': 'cncidr',
          'proxy': 'DIRECT',
          'size': 8520
        },
        {
          'type': 'RULE-SET',
          'payload': 'proxy-domain',
          'proxy': '节点选择',
          'size': 3200
        },
        {'type': 'MATCH', 'payload': '', 'proxy': '节点选择'},
      ],
    };
  }

  // ------------------------------------------------------------------
  // Logs
  // ------------------------------------------------------------------

  List<Map<String, String>> getLogs() {
    if (!_isRunning) return [];

    return [
      {'type': 'info', 'payload': '[TCP] google.com:443 → 🇭🇰 香港 01 match Domain'},
      {'type': 'info', 'payload': '[TCP] github.com:443 → 🇯🇵 日本 01 match Domain'},
      {
        'type': 'info',
        'payload': '[TCP] api.openai.com:443 → 🇺🇸 美国 01 match Domain'
      },
      {'type': 'warning', 'payload': '[UDP] dns query timeout: 8.8.8.8'},
      {'type': 'info', 'payload': '[TCP] cdn.jsdelivr.net:443 → DIRECT match Domain'},
      {
        'type': 'info',
        'payload': '[TCP] registry.npmjs.org:443 → 🇭🇰 香港 02 match Domain'
      },
      {
        'type': 'debug',
        'payload': '[DNS] resolved google.com to 142.250.80.14 (6ms)'
      },
      {'type': 'info', 'payload': '[TCP] 114.114.114.114:443 → DIRECT match GeoIP'},
    ];
  }
}
