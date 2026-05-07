import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/kernel/core_manager.dart';
import '../core/managers/system_proxy_manager.dart';
import '../core/providers/core_preferences_providers.dart';
import '../core/providers/core_runtime_providers.dart';
import '../core/service/service_manager.dart';
import '../core/storage/settings_service.dart';
import '../core/system/private_dns_state.dart';

/// D-③ P4-1: 一键诊断报告。
///
/// 用户在 yuelink 设置点"导出诊断报告"按钮 →
/// `DiagnosticReport.build(ref)` 收集 11 板块状态 → 返回 markdown 字符串
/// → 调用方用 `LogExportService.saveText` 写到用户选择位置。
///
/// 板块（与 governance/client-comparison-deep-dive-2026-05-07.md § 6.2 对齐）：
///   1. 应用版本 + 平台 + 时间戳
///   2. 模式 (connectionMode + 实际生效)
///   3. 端口 (mixedPort + apiPort + Quic policy + lan-compat)
///   4. mihomo runtime (运行状态)
///   5. 系统代理 (verify 结果)
///   6. Service Mode (helper isInstalled / isReady — Desktop only)
///   7. Private DNS (mode + specifier — Android only)
///   8. TUN bypass 配置 (transformer 视角)
///   9. 路由/桥接提示 (PowerShell 自助脚本指引 — Win only)
///   10. 失败步骤回溯 (lastReport.failedStep)
///   11. 注意事项 (用户上报时该附什么)
///
/// 不在范围内：
///   * 实时连接 dump （/connections）—— 隐私敏感，需用户主动；用 LogExportSources 单独走
///   * dnsleak.com 调用 —— 网络副作用，不在静默诊断里发起
///   * 流量统计 —— XBoard userProfile 已在 Mine 页可见
class DiagnosticReport {
  DiagnosticReport._();

  /// Builds the markdown report. Tolerates missing/failed sections —
  /// each block is wrapped so a single subsystem failure (e.g. core
  /// stopped) doesn't kill the whole report.
  ///
  /// Takes [WidgetRef] (call from a `ConsumerStatefulWidget` /
  /// `ConsumerWidget` build site). If you need to call from outside the
  /// widget tree, reach for `ProviderContainer.read` directly.
  static Future<String> build(WidgetRef ref) async {
    final buf = StringBuffer();
    buf.writeln('# YueLink 诊断报告');
    buf.writeln('生成时间：${DateTime.now().toIso8601String()}');
    buf.writeln();

    // 1. App + platform
    await _safe(buf, '1. 应用 / 平台', () async {
      final info = await PackageInfo.fromPlatform();
      return [
        '- App 版本：${info.version} (build ${info.buildNumber})',
        '- 包名：${info.packageName}',
        '- 平台：${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
        '- Dart：${Platform.version}',
      ].join('\n');
    });

    // 2. Connection mode (设置值 + 实际生效)
    await _safe(buf, '2. 连接模式', () async {
      final settingMode = ref.read(connectionModeProvider);
      final running = ref.read(coreStatusProvider) == CoreStatus.running;
      final stack = ref.read(desktopTunStackProvider);
      return [
        '- 设置：$settingMode',
        '- 核心状态：${running ? "running" : "stopped"}',
        '- 桌面 TUN stack：$stack',
        '- QUIC policy：${ref.read(quicPolicyProvider)}',
        '- 路由模式：${ref.read(routingModeProvider)}',
        if (Platform.isWindows)
          '- LAN 兼容模式：${ref.read(windowsLanCompatibilityModeProvider) ? "ON (strict-route off)" : "OFF (strict-route on)"}',
      ].join('\n');
    });

    // 3. Ports
    await _safe(buf, '3. 端口', () async {
      final manager = CoreManager.instance;
      return [
        '- mixed-port：${manager.mixedPort}',
        '  （HTTP + SOCKS5 共享，系统代理 / Verge / 工具走这一个）',
      ].join('\n');
    });

    // 4. mihomo runtime + last startup report
    await _safe(buf, '4. mihomo 运行时 / 启动诊断', () async {
      final manager = CoreManager.instance;
      final running = manager.isRunning;
      final report = manager.lastReport;
      final lines = <String>[
        '- isRunning：$running',
        '- isMockMode：${manager.isMockMode}',
      ];
      if (report != null) {
        lines.add('- 最后一次启动：${report.overallSuccess ? "成功" : "失败"}');
        if (!report.overallSuccess) {
          lines.add('- 失败步骤：${report.failedStep ?? "unknown"}');
          final summary = report.failureSummary;
          if (summary != null) {
            lines.add('- 失败原因摘要：${_redact(summary.split("\n").first)}');
          }
        }
        final totalMs = report.steps
            .fold<int>(0, (sum, s) => sum + s.durationMs);
        lines.add('- 启动总耗时：$totalMs ms');
        lines.add('- 步骤明细：');
        for (final step in report.steps) {
          final detail = step.detail;
          lines.add(
            '  - ${step.name}：${step.success ? "✓" : "✗"} '
            '${step.durationMs}ms'
            '${(detail != null && detail.isNotEmpty) ? "  // ${_redact(detail)}" : ""}',
          );
        }
      } else {
        lines.add('- （无启动记录 / mock 模式）');
      }
      return lines.join('\n');
    });

    // 5. System proxy state
    await _safe(buf, '5. 系统代理', () async {
      if (Platform.isAndroid || Platform.isIOS) {
        return '- 移动平台：系统代理由 VPN/PacketTunnel 接管，无独立 OS 代理设置';
      }
      final mixedPort = CoreManager.instance.mixedPort;
      final verified = await SystemProxyManager.verify(mixedPort, force: true);
      return [
        '- mixed-port：$mixedPort',
        '- verify(force=true)：${verified == null ? "indeterminate" : (verified ? "OK (代理已生效)" : "FAIL (代理未生效)")}',
        '- 进一步排查（Win）：复制"Windows 诊断脚本"按钮里的 PS 脚本',
      ].join('\n');
    });

    // 6. Service Mode (Desktop only)
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      await _safe(buf, '6. Service Mode helper（桌面 TUN 必须）', () async {
        final installed = await ServiceManager.isInstalled();
        final ready = installed
            ? await ServiceManager.isReady()
            : false;
        final expected = await ServiceManager.expectedVersion();
        return [
          '- isInstalled：$installed',
          '- isReady（installed + IPC ping）：$ready',
          '- 期待 helper 版本：$expected',
          if (installed && !ready)
            '- 异常：helper 注册了但 IPC 不响应。建议在设置 → 服务模式 → 重装。',
        ].join('\n');
      });
    }

    // 7. Private DNS (Android only)
    if (Platform.isAndroid) {
      await _safe(buf, '7. Android Private DNS', () async {
        // Force a fresh pull so the report reflects current state.
        await ref.read(privateDnsStateProvider.notifier).refresh();
        final dns = ref.read(privateDnsStateProvider);
        final lines = <String>[
          '- mode：${dns.mode}',
          '- specifier：${dns.specifier ?? "(none)"}',
        ];
        switch (dns.mode) {
          case 'hostname':
            lines.add('- ⚠️ hostname 模式会绕过 yuelink TUN 的 DNS 接管，'
                '建议改为 Off 或 Automatic');
            break;
          case 'opportunistic':
            lines.add('- ✓ opportunistic 模式下 yuelink TUN dns-hijack '
                '通常仍能拦下系统 DNS 查询');
            break;
          case 'off':
            lines.add('- ✓ off 模式无影响');
            break;
          case 'unknown':
          default:
            lines.add('- ⚠️ 无法读取（OEM ROM 可能限制 Settings.Global）');
        }
        return lines.join('\n');
      });
    }

    // 8. TUN bypass 配置（直接读 SettingsService — 没有 provider 包装）
    await _safe(buf, '8. TUN bypass 配置', () async {
      final addrs = await SettingsService.getTunBypassAddresses();
      final procs = await SettingsService.getTunBypassProcesses();
      final addrsBody = addrs.isEmpty ? '(空)' : addrs.join(', ');
      final procsBody = procs.isEmpty ? '(空)' : procs.join(', ');
      return [
        '- bypass IP/CIDR (route-exclude-address) ${addrs.length} 项：$addrsBody',
        '- bypass 进程名 (PROCESS-NAME DIRECT) ${procs.length} 项：$procsBody',
      ].join('\n');
    });

    // 9. Routing/bridge hints (Windows-only self-help)
    if (Platform.isWindows) {
      buf.writeln('## 9. Windows 路由 / 网卡 自助查询');
      buf.writeln();
      buf.writeln('系统级状态由 yuelink 暴露的"复制 Windows 诊断脚本"按钮提供：');
      buf.writeln('- 设置 → 高级（连接模式 = TUN）→ 复制 Windows 诊断脚本');
      buf.writeln('- 在 Windows PowerShell 粘贴执行即可生成 9 项检查报告');
      buf.writeln();
    }

    // 10. Note for support
    buf.writeln('## 10. 上报注意事项');
    buf.writeln();
    buf.writeln('- 本报告**不**包含：订阅 URL / token / 密码 / 节点服务器地址 / '
        '当前出口 IP / 历史连接列表');
    buf.writeln('- 上报到 issue / 客服时可直接整段粘贴');
    buf.writeln('- 如需进一步排错，请同步导出 core.log / event.log（设置 → 日志）');
    buf.writeln();

    return buf.toString();
  }

  static Future<void> _safe(
    StringBuffer buf,
    String title,
    Future<String> Function() body,
  ) async {
    buf.writeln('## $title');
    buf.writeln();
    try {
      final content = await body();
      buf.writeln(content);
    } catch (e, st) {
      debugPrint('[DiagnosticReport] $title threw: $e\n$st');
      buf.writeln('（采集失败：${_redact(e.toString())}）');
    }
    buf.writeln();
  }

  // ── PII redaction (test-visible — exported for shared/diagnostic_report_test.dart)
  /// Strip user-identifying paths and secrets from free-text fields
  /// before they enter the report. Applied to:
  ///   * `StartupStep.detail` — `homeDir=/Users/<name>/Library/...` shows up
  ///     verbatim from `core_manager.dart::initCore` & `desktop_service_mode
  ///     .dart::buildConfig` return values.
  ///   * `StartupReport.failureSummary` — embeds step.error which can carry
  ///     stack frames or paths from the Go core.
  ///   * Catch handlers in `_safe` — exception strings can include paths.
  ///
  /// Patterns redacted:
  ///   * `homeDir=<value>` → `homeDir=<redacted>` (yuelink-specific marker)
  ///   * `/Users/<name>/...` (macOS)         → `/Users/<redacted>/...`
  ///   * `/home/<name>/...` (Linux)          → `/home/<redacted>/...`
  ///   * `C:\Users\<name>\...` (Windows)     → `C:\Users\<redacted>\...`
  ///   * `/data/user/0/<pkg>/...` (Android)  → `/data/user/0/<redacted>/...`
  ///     (sometimes useful to keep raw; user wallpaper/Secure Folder leaks
  ///     the user index — drop it)
  ///   * `secret=<32-hex-chars>` (controller secret) → `secret=<redacted>`
  ///
  /// **Not** redacted:
  ///   * Numeric ports / lengths / counts (no PII)
  ///   * mihomo step/error codes (E002–E009)
  ///   * Public mihomo / Go version strings
  @visibleForTesting
  static String redactForTest(String input) => _redact(input);

  static String _redact(String input) {
    var s = input;
    // 1. yuelink's explicit homeDir= marker.
    //
    // Real-world detail strings:
    //   * core_manager.dart::initCore       → `homeDir=/Users/<n>/Library/Application Support/YueLink`
    //   * desktop_service_mode.dart::buildConfig → `output=…, apiPort=…, mixedPort=…, homeDir=…`
    //
    // macOS Application Support paths CONTAIN A SPACE — so a naive
    // `homeDir=\S+` pattern stops at the first space and leaves
    // "Support/YueLink" exposed. Lookahead instead matches lazily until
    // the next `, key=` separator, an end-of-line, or end-of-string.
    s = s.replaceAllMapped(
      RegExp(r'homeDir=.+?(?=,\s|\n|$)'),
      (_) => 'homeDir=<redacted>',
    );
    // 2. macOS user paths
    s = s.replaceAllMapped(
      RegExp(r'/Users/[^/\s]+'),
      (_) => '/Users/<redacted>',
    );
    // 3. Linux user paths
    s = s.replaceAllMapped(
      RegExp(r'/home/[^/\s]+'),
      (_) => '/home/<redacted>',
    );
    // 4. Windows user paths (covers C:\Users\… up to Z:\…)
    s = s.replaceAllMapped(
      RegExp(r'[A-Za-z]:\\Users\\[^\\\s]+', caseSensitive: false),
      (m) => '${m.group(0)!.substring(0, 3)}Users\\<redacted>',
    );
    // 5. Android per-user data dir (user index leaks Secure Folder presence)
    s = s.replaceAllMapped(
      RegExp(r'/data/user/\d+/[^/\s]+'),
      (_) => '/data/user/0/<redacted>',
    );
    // 6. Controller secret (32+ hex chars; mihomo default is 32-char hex)
    s = s.replaceAllMapped(
      RegExp(r'secret=[0-9a-fA-F]{16,}'),
      (_) => 'secret=<redacted>',
    );
    return s;
  }
}
