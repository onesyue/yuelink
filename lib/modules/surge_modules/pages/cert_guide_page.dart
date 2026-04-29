import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/app_strings.dart';
import '../../../shared/widgets/yl_scaffold.dart';
import '../../../theme.dart';
import '../providers/mitm_provider.dart';

/// CA certificate generation + platform-specific installation guide.
class CertGuidePage extends ConsumerWidget {
  const CertGuidePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mitm = ref.watch(mitmProvider);
    final ca = mitm.ca;

    return YLLargeTitleScaffold(
      title: s.mitmCertGuideTitle,
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          tooltip: 'Refresh',
          onPressed: () => ref.read(mitmProvider.notifier).refresh(),
        ),
      ],
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            YLSpacing.lg,
            0,
            YLSpacing.lg,
            YLSpacing.xl,
          ),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              // ── CA Status card ──────────────────────────────────────────
              _SectionCard(
                isDark: isDark,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          ca.exists
                              ? Icons.verified_user
                              : Icons.security_rounded,
                          size: 18,
                          color: ca.exists
                              ? YLColors.connected
                              : YLColors.zinc400,
                        ),
                        const SizedBox(width: YLSpacing.sm),
                        Text(
                          s.mitmCertTitle,
                          style: YLText.label.copyWith(
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : YLColors.zinc900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: YLSpacing.md),
                    if (!ca.exists) ...[
                      Text(
                        s.mitmCertNotFound,
                        style: YLText.body.copyWith(color: YLColors.zinc500),
                      ),
                      const SizedBox(height: YLSpacing.md),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: mitm.isLoading
                              ? null
                              : () => ref
                                    .read(mitmProvider.notifier)
                                    .generateCa(),
                          icon: mitm.isLoading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.add_circle_rounded, size: 18),
                          label: Text(s.mitmCertGenerate),
                        ),
                      ),
                    ] else ...[
                      // Fingerprint
                      _InfoRow(
                        label: s.mitmCertFingerprint,
                        value: _formatFingerprint(ca.fingerprint),
                        monospace: true,
                        isDark: isDark,
                      ),
                      const SizedBox(height: YLSpacing.xs + 2),
                      // Expiry
                      if (ca.expiresAt != null)
                        _InfoRow(
                          label: s.mitmCertExpiry,
                          value:
                              '${ca.expiresAt!.year}-${_twoDigits(ca.expiresAt!.month)}-${_twoDigits(ca.expiresAt!.day)}',
                          isDark: isDark,
                        ),
                      const SizedBox(height: YLSpacing.md),
                      // Export PEM button
                      if (ca.exportPath.isNotEmpty)
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                _copyPathToClipboard(context, ca.exportPath),
                            icon: const Icon(Icons.copy_rounded, size: 16),
                            label: Text(s.mitmCertExport),
                          ),
                        ),
                    ],

                    // Error
                    if (mitm.error != null) ...[
                      const SizedBox(height: YLSpacing.sm),
                      Text(
                        mitm.error!,
                        style: YLText.caption.copyWith(color: YLColors.error),
                      ),
                    ],
                  ],
                ),
              ),

              // ── Install guide ───────────────────────────────────────────
              if (ca.exists) ...[
                const SizedBox(height: YLSpacing.lg),
                Padding(
                  padding: const EdgeInsets.only(left: YLSpacing.xs),
                  child: Text(
                    s.mitmCertInstall,
                    style: YLText.label.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : YLColors.zinc900,
                    ),
                  ),
                ),
                const SizedBox(height: YLSpacing.sm),
                _InstallGuide(isDark: isDark, exportPath: ca.exportPath),
              ],
            ]),
          ),
        ),
      ],
    );
  }

  static String _formatFingerprint(String hex) {
    if (hex.length < 8) return hex;
    // Show first 8 chars + … + last 8 chars for readability
    return '${hex.substring(0, 8)}…${hex.substring(hex.length - 8)}';
  }

  static String _twoDigits(int n) => n.toString().padLeft(2, '0');

  void _copyPathToClipboard(BuildContext context, String path) {
    Clipboard.setData(ClipboardData(text: path));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Path copied: $path'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

// ── Install guide ─────────────────────────────────────────────────────────────

class _InstallGuide extends StatelessWidget {
  final bool isDark;
  final String exportPath;

  const _InstallGuide({required this.isDark, required this.exportPath});

  @override
  Widget build(BuildContext context) {
    if (Platform.isIOS) return _IOSGuide(isDark: isDark);
    if (Platform.isAndroid) return _AndroidGuide(isDark: isDark);
    if (Platform.isMacOS) return _MacOSGuide(isDark: isDark, path: exportPath);
    if (Platform.isWindows) {
      return _WindowsGuide(isDark: isDark, path: exportPath);
    }
    return _GenericGuide(isDark: isDark, path: exportPath);
  }
}

class _IOSGuide extends StatelessWidget {
  final bool isDark;
  const _IOSGuide({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return _StepList(
      isDark: isDark,
      steps: const [
        'Open the exported CA file with Files or share it to Safari.',
        'A prompt will appear — tap Allow to download the profile.',
        'Go to Settings → General → VPN & Device Management.',
        'Tap the "YueLink Module Runtime CA" profile → Install.',
        'Enter your device passcode when prompted.',
        'Go to Settings → General → About → Certificate Trust Settings.',
        'Enable full trust for "YueLink Module Runtime CA".',
      ],
    );
  }
}

class _AndroidGuide extends StatelessWidget {
  final bool isDark;
  const _AndroidGuide({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return _StepList(
      isDark: isDark,
      steps: const [
        'Copy the CA file (ca.crt) to your device storage.',
        'Open Settings → Security (or Biometrics & Security).',
        'Tap "Install from storage" or "Install a certificate".',
        'Select the ca.crt file and confirm.',
        'Choose "VPN and apps" as the certificate type.',
        'Enter your screen lock PIN/password if prompted.',
      ],
    );
  }
}

class _MacOSGuide extends StatelessWidget {
  final bool isDark;
  final String path;
  const _MacOSGuide({required this.isDark, required this.path});

  @override
  Widget build(BuildContext context) {
    return _StepList(
      isDark: isDark,
      steps: [
        'Open Keychain Access (Applications → Utilities).',
        'Select the System keychain in the left panel.',
        if (path.isNotEmpty)
          'Drag and drop the file at:\n$path\ninto Keychain Access.',
        if (path.isEmpty) 'Import the ca.crt file via File → Import Items.',
        'Double-click "YueLink Module Runtime CA" in the certificate list.',
        'Expand the Trust section and set "When using this certificate" to Always Trust.',
        'Close the window and authenticate with your macOS password.',
      ],
    );
  }
}

class _WindowsGuide extends StatelessWidget {
  final bool isDark;
  final String path;
  const _WindowsGuide({required this.isDark, required this.path});

  @override
  Widget build(BuildContext context) {
    return _StepList(
      isDark: isDark,
      steps: [
        if (path.isNotEmpty) 'The CA file is at:\n$path',
        'Double-click the ca.crt file → "Install Certificate".',
        'Select "Local Machine" → Next.',
        'Choose "Place all certificates in the following store".',
        'Click Browse and select "Trusted Root Certification Authorities".',
        'Click Next → Finish → Yes to confirm the security warning.',
      ],
    );
  }
}

class _GenericGuide extends StatelessWidget {
  final bool isDark;
  final String path;
  const _GenericGuide({required this.isDark, required this.path});

  @override
  Widget build(BuildContext context) {
    return _StepList(
      isDark: isDark,
      steps: [
        if (path.isNotEmpty) 'CA file path: $path',
        'Import ca.crt into your system or browser certificate store.',
        'Trust it as a Root CA.',
      ],
    );
  }
}

// ── Shared components ─────────────────────────────────────────────────────────

class _StepList extends StatelessWidget {
  final bool isDark;
  final List<String> steps;

  const _StepList({required this.isDark, required this.steps});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.1)
                        : Colors.black.withValues(alpha: 0.06),
                  ),
                  child: Text(
                    '${i + 1}',
                    style: YLText.caption.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : YLColors.zinc700,
                    ),
                  ),
                ),
                const SizedBox(width: YLSpacing.md),
                Expanded(
                  child: Text(
                    steps[i],
                    style: YLText.body.copyWith(
                      color: isDark ? YLColors.zinc300 : YLColors.zinc700,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
            if (i < steps.length - 1) const SizedBox(height: YLSpacing.md),
          ],
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final bool isDark;
  final Widget child;

  const _SectionCard({required this.isDark, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(YLSpacing.lg),
      decoration: BoxDecoration(
        color: isDark ? YLColors.zinc900 : Colors.white,
        borderRadius: BorderRadius.circular(YLRadius.lg),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.06),
          width: 0.5,
        ),
      ),
      child: child,
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool monospace;
  final bool isDark;

  const _InfoRow({
    required this.label,
    required this.value,
    this.monospace = false,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label: ',
          style: YLText.caption.copyWith(color: YLColors.zinc500),
        ),
        Expanded(
          child: Text(
            value,
            style:
                (monospace
                        ? YLText.caption.copyWith(fontFamily: 'monospace')
                        : YLText.caption)
                    .copyWith(
                      color: isDark ? YLColors.zinc300 : YLColors.zinc700,
                    ),
          ),
        ),
      ],
    );
  }
}
