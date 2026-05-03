import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../i18n/app_strings.dart';
import '../../../../shared/widgets/setting_icon.dart';
import '../../../../shared/widgets/yl_list.dart';
import '../../../../theme.dart';
import '../connection_diagnostics_service.dart';

class NetworkDiagnostics extends StatefulWidget {
  final String header;
  final bool isDark;
  const NetworkDiagnostics({
    super.key,
    required this.header,
    required this.isDark,
  });

  @override
  State<NetworkDiagnostics> createState() => _NetworkDiagnosticsState();
}

class _NetworkDiagnosticsState extends State<NetworkDiagnostics> {
  List<EndpointResult> _results = List.filled(
    kDefaultDiagEndpoints.length,
    const EndpointResult(),
  );
  bool _testing = false;

  Future<void> _runDiagnostics() async {
    if (_testing) return;
    setState(() {
      _testing = true;
      _results = List.generate(
        kDefaultDiagEndpoints.length,
        (_) => const EndpointResult(status: EndpointStatus.testing),
      );
    });

    final results = await Future.wait(kDefaultDiagEndpoints.map(_testEndpoint));
    if (mounted) {
      setState(() {
        _results = results;
        _testing = false;
      });
    }
  }

  Future<EndpointResult> _testEndpoint(EndpointSpec endpoint) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);
    try {
      final sw = Stopwatch()..start();
      final request = await client.getUrl(Uri.parse(endpoint.url));
      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      sw.stop();
      await response.drain<void>();
      return ConnectionDiagnosticsService.classifyHttpResponse(
        statusCode: response.statusCode,
        latencyMs: sw.elapsedMilliseconds,
        aiTarget: endpoint.aiTarget,
      );
    } catch (e) {
      return ConnectionDiagnosticsService.classifyHttpError(e);
    } finally {
      client.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    return YLSection(
      header: widget.header,
      children: [
        YLListTile(
          leading: const YLSettingIcon(
            icon: Icons.network_check_rounded,
            color: Color(0xFF0EA5E9),
          ),
          title: S.current.networkDiagnostics,
          trailing: _testing
              ? YLListTrailing.loading()
              : YLListTrailing.value(_testing ? '检测中...' : '开始检测'),
          onTap: _testing ? null : _runDiagnostics,
        ),
        for (var i = 0; i < kDefaultDiagEndpoints.length; i++)
          _DiagRow(endpoint: kDefaultDiagEndpoints[i], result: _results[i]),
      ],
    );
  }
}

class _DiagRow extends StatelessWidget {
  final EndpointSpec endpoint;
  final EndpointResult result;
  const _DiagRow({required this.endpoint, required this.result});

  @override
  Widget build(BuildContext context) {
    final IconData icon;
    final Color iconColor;
    switch (result.status) {
      case EndpointStatus.idle:
        icon = Icons.circle_outlined;
        iconColor = YLColors.zinc400;
        break;
      case EndpointStatus.testing:
        icon = Icons.sync_rounded;
        iconColor = YLColors.zinc400;
        break;
      case EndpointStatus.success:
        icon = Icons.check_circle_rounded;
        iconColor = YLColors.connected;
        break;
      case EndpointStatus.limited:
        icon = Icons.shield_rounded;
        iconColor = YLColors.connecting;
        break;
      case EndpointStatus.failed:
        icon = Icons.cancel_rounded;
        iconColor = YLColors.error;
        break;
    }

    final Widget? trailing;
    if (result.status == EndpointStatus.testing) {
      trailing = YLListTrailing.loading();
    } else if (result.latencyMs != null) {
      trailing = YLListTrailing.badge(
        text: '${result.latencyMs}ms',
        color: result.status == EndpointStatus.success
            ? YLColors.connected
            : result.status == EndpointStatus.limited
            ? YLColors.connecting
            : YLColors.error,
      );
    } else {
      trailing = null;
    }

    return YLListTile(
      leading: YLSettingIcon(icon: icon, color: iconColor),
      title: endpoint.label,
      subtitle: _subtitle(result),
      trailing: trailing,
    );
  }

  String _subtitle(EndpointResult result) {
    if (result.status == EndpointStatus.idle) return '等待检测';
    if (result.status == EndpointStatus.testing) return '正在检测...';
    if (result.status == EndpointStatus.success) {
      return result.statusCode == null
          ? '连接正常'
          : '连接正常 · HTTP ${result.statusCode}';
    }
    if (result.status == EndpointStatus.limited) {
      return result.error ?? 'AI 出口受限';
    }
    return result.error ?? '未知错误';
  }
}
