import 'package:flutter/material.dart';

import '../../shared/telemetry.dart';
import '../../theme.dart';

/// First-launch persona prompt (2026 Surfshark/Proton pattern).
///
/// Shown BEFORE the existing OnboardingPage when the `onboarding_split`
/// feature flag is on. Asks one question — "你用过 VPN/代理类工具吗？" — and
/// persists the answer so later screens can tailor UX (e.g. skip tooltips
/// for experienced users).
///
/// Routing choice: both personas are forwarded to the same next screen
/// (the existing OnboardingPage) because the product intro is only 4 steps
/// and has its own Skip button. Experienced users can skip there if they
/// want; we avoid branching the post-onboarding flow so this prompt stays
/// purely additive data capture. Callers supply [onChosen] to continue.
class PersonaPromptPage extends StatefulWidget {
  /// Called with the chosen persona: `'newcomer' | 'experienced' | 'unknown'`.
  /// Implementations are expected to persist the value (via SettingsService)
  /// and then advance to the next screen.
  final Future<void> Function(String persona) onChosen;

  const PersonaPromptPage({super.key, required this.onChosen});

  @override
  State<PersonaPromptPage> createState() => _PersonaPromptPageState();
}

class _PersonaPromptPageState extends State<PersonaPromptPage> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    Telemetry.event(TelemetryEvents.onboardingStart);
  }

  Future<void> _choose(String persona) async {
    if (_busy) return;
    setState(() => _busy = true);
    Telemetry.event(
      TelemetryEvents.onboardingAnswer,
      props: {'persona': persona},
    );
    try {
      await widget.onChosen(persona);
    } finally {
      Telemetry.event(TelemetryEvents.onboardingFinish);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? Colors.white : YLColors.zinc900;
    const subColor = YLColors.zinc500;

    return Scaffold(
      backgroundColor: isDark ? YLColors.zinc950 : null,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.topRight,
                    child: TextButton(
                      onPressed: _busy ? null : () => _choose('unknown'),
                      child: Text(
                        '跳过',
                        style: YLText.body.copyWith(color: YLColors.zinc400),
                      ),
                    ),
                  ),
                  const Spacer(flex: 2),
                  Text(
                    '你用过 VPN/代理类工具吗？',
                    style: YLText.titleLarge.copyWith(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: titleColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '我们会根据你的熟悉程度调整引导内容。',
                    style: YLText.body.copyWith(
                      color: subColor,
                      height: 1.5,
                      fontSize: 15,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const Spacer(flex: 3),
                  _PersonaButton(
                    label: '我是新手',
                    icon: Icons.auto_awesome_rounded,
                    filled: true,
                    isDark: isDark,
                    onTap: _busy ? null : () => _choose('newcomer'),
                  ),
                  const SizedBox(height: 12),
                  _PersonaButton(
                    label: '我用过 Clash/V2Ray 等工具',
                    icon: Icons.bolt_rounded,
                    filled: false,
                    isDark: isDark,
                    onTap: _busy ? null : () => _choose('experienced'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PersonaButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool filled;
  final bool isDark;
  final VoidCallback? onTap;

  const _PersonaButton({
    required this.label,
    required this.icon,
    required this.filled,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primaryBg = isDark ? Colors.white : YLColors.primary;
    final primaryFg = isDark ? YLColors.primary : Colors.white;
    final outlineFg = isDark ? Colors.white : YLColors.zinc900;
    final outlineBorder = isDark
        ? Colors.white.withValues(alpha: 0.16)
        : Colors.black.withValues(alpha: 0.12);

    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 10),
        Text(label,
            style: YLText.label.copyWith(fontWeight: FontWeight.w600)),
      ],
    );

    return SizedBox(
      width: double.infinity,
      height: 56,
      child: filled
          ? FilledButton(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                backgroundColor: primaryBg,
                foregroundColor: primaryFg,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(YLRadius.lg),
                ),
              ),
              child: child,
            )
          : OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                foregroundColor: outlineFg,
                side: BorderSide(color: outlineBorder, width: 1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(YLRadius.lg),
                ),
              ),
              child: child,
            ),
    );
  }
}
