import 'dart:io';

import '../constants.dart';

/// D-① P4-2: Windows 诊断 PowerShell 脚本生成器。
///
/// 用户在 yuelink 桌面端点"复制 Windows 诊断脚本"按钮 →
/// `WindowsDiagnosticScript.generate()` 返回一段 PowerShell 脚本 →
/// 用户在 Windows PowerShell 粘贴执行 → 输出 markdown 报告。
///
/// 9 项检查与 governance/client-comparison-deep-dive-2026-05-07.md
/// § 4.3 Windows 检查项一一对应（额外加了 underlying-transport metric）。
///
/// 不修改任何系统配置 — 全部只读。可安全粘贴到任意终端执行。
class WindowsDiagnosticScript {
  WindowsDiagnosticScript._();

  /// Generates a self-contained PowerShell script (paste-and-run).
  ///
  /// [mixedPort] / [apiPort] are baked in so the generated checks point
  /// at the user's *actual* mihomo runtime ports, not generic 7890/9090.
  static String generate({
    int mixedPort = AppConstants.defaultMixedPort,
    int apiPort = AppConstants.defaultApiPort,
  }) {
    return _template
        .replaceAll('__API_PORT__', apiPort.toString())
        .replaceAll('__MIXED_PORT__', mixedPort.toString());
  }

  /// `true` only on Windows; on other hosts the button should hide
  /// since the script's `Get-NetAdapter` / `pnputil` etc. are Windows-only.
  static bool isAvailableOnHost() => Platform.isWindows;

  static const _template = r'''
# ──────────────────────────────────────────────────────────────────
# YueLink Windows 诊断脚本 (D-① P4-2)
# 复制到 Windows PowerShell 执行,将输出 markdown 报告。
# 不修改任何系统配置 — 全部只读。
# ──────────────────────────────────────────────────────────────────
$ErrorActionPreference = "Continue"
$out = New-Object System.Text.StringBuilder

function Section($title, $body) {
  [void]$out.AppendLine("## $title")
  [void]$out.AppendLine('```')
  [void]$out.AppendLine($body)
  [void]$out.AppendLine('```')
  [void]$out.AppendLine()
}

[void]$out.AppendLine("# YueLink Windows 诊断报告")
[void]$out.AppendLine("生成时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')")
[void]$out.AppendLine("操作系统: $([Environment]::OSVersion.VersionString)")
[void]$out.AppendLine("PowerShell: $($PSVersionTable.PSVersion)")
[void]$out.AppendLine("yuelink mixedPort: __MIXED_PORT__  apiPort: __API_PORT__")
[void]$out.AppendLine()

# 1. Wintun driver
try {
  $wintun = pnputil /enum-drivers 2>$null | Select-String -Pattern "wintun" -Context 0,1
  if (-not $wintun) { $wintun = "Wintun driver NOT installed (or pnputil unavailable)" }
  Section "1. Wintun 驱动" ($wintun -join "`n")
} catch { Section "1. Wintun 驱动" "ERROR: $_" }

# 2. Meta / YueLink network adapter
try {
  $nic = Get-NetAdapter -ErrorAction SilentlyContinue |
         Where-Object { $_.Name -match "Meta|YueLink" -or $_.InterfaceDescription -match "Wintun" } |
         Format-Table Name,Status,InterfaceDescription,MacAddress,LinkSpeed -AutoSize | Out-String
  if (-not $nic.Trim()) { $nic = "No Meta/YueLink/Wintun adapter found" }
  Section "2. TUN 网卡" $nic
} catch { Section "2. TUN 网卡" "ERROR: $_" }

# 3. Default route
try {
  $route = route print 0.0.0.0 2>$null | Out-String
  Section "3. 默认路由 (是否指向 TUN)" $route
} catch { Section "3. 默认路由" "ERROR: $_" }

# 4. DNS client servers
try {
  $dns = Get-DnsClientServerAddress -ErrorAction SilentlyContinue |
         Where-Object { $_.AddressFamily -eq 2 -and $_.ServerAddresses } |
         Format-Table InterfaceAlias,ServerAddresses -AutoSize | Out-String
  Section "4. 系统 DNS (是否被 TUN 接管)" $dns
} catch { Section "4. 系统 DNS" "ERROR: $_" }

# 5. Firewall profile state
try {
  $fw = Get-NetFirewallProfile -ErrorAction SilentlyContinue |
        Format-Table Name,Enabled,DefaultInboundAction,DefaultOutboundAction -AutoSize | Out-String
  Section "5. Windows 防火墙" $fw
} catch { Section "5. Windows 防火墙" "ERROR: $_" }

# 6. HKCU system proxy
try {
  $proxyKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
  $proxy = Get-ItemProperty -Path $proxyKey -ErrorAction SilentlyContinue |
           Select-Object ProxyEnable,ProxyServer,AutoConfigURL,ProxyOverride |
           Format-List | Out-String
  Section "6. 系统代理 (HKCU)" $proxy
} catch { Section "6. 系统代理" "ERROR: $_" }

# 7. Service mode helper
try {
  $svc = sc.exe query YueLinkServiceHelper 2>&1 | Out-String
  Section "7. Service Mode helper" $svc
} catch { Section "7. Service Mode helper" "ERROR: $_" }

# 8. mihomo external-controller reachability
try {
  $resp = Invoke-WebRequest -Uri "http://127.0.0.1:__API_PORT__/configs" -UseBasicParsing -TimeoutSec 2 -ErrorAction SilentlyContinue
  if ($resp.StatusCode -eq 200 -or $resp.StatusCode -eq 401) {
    Section "8. mihomo external-controller (127.0.0.1:__API_PORT__)" "Reachable. HTTP $($resp.StatusCode)"
  } else {
    Section "8. mihomo external-controller" "Unexpected HTTP $($resp.StatusCode)"
  }
} catch { Section "8. mihomo external-controller" "Unreachable: $_" }

# 9. Underlying transport metric
try {
  $netroute = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
              Format-Table InterfaceAlias,NextHop,RouteMetric,InterfaceMetric -AutoSize |
              Out-String
  Section "9. Underlying transport metric" $netroute
} catch { Section "9. Underlying transport" "ERROR: $_" }

[void]$out.AppendLine("---")
[void]$out.AppendLine("生成完毕。请把上面整段 markdown 贴到 issue 或 yuelink 客服。")

Write-Output $out.ToString()
''';
}
