import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../constants.dart';
import '../../../i18n/app_strings.dart';
import '../../../theme.dart';
import '../providers/yue_auth_providers.dart';

/// Login page for YueLink — the entry point for 悦通 account authentication.
///
/// After successful login, automatically syncs subscription and navigates
/// to the main shell.
class YueAuthPage extends ConsumerStatefulWidget {
  const YueAuthPage({super.key});

  @override
  ConsumerState<YueAuthPage> createState() => _YueAuthPageState();
}

class _YueAuthPageState extends ConsumerState<YueAuthPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) return;

    HapticFeedback.lightImpact();

    await ref.read(authProvider.notifier).login(email, password);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final authState = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: isDark ? YLColors.bgDark : YLColors.bgLight,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 48),

                // ── Brand ────────────────────────────────────────
                Center(
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: YLColors.primary,
                      borderRadius: BorderRadius.circular(YLRadius.xl),
                    ),
                    child: const Icon(
                      Icons.link_rounded,
                      size: 32,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'YueLink',
                  textAlign: TextAlign.center,
                  style: YLText.titleLarge.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : YLColors.zinc900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  S.of(context).authLoginSubtitle,
                  textAlign: TextAlign.center,
                  style: YLText.body.copyWith(color: YLColors.zinc500),
                ),

                const SizedBox(height: 40),

                // ── Email field ──────────────────────────────────
                _buildTextField(
                  controller: _emailController,
                  focusNode: _emailFocus,
                  label: _e(context) ? 'Email' : '邮箱',
                  hint: _e(context) ? 'your@email.com' : '请输入邮箱',
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => _passwordFocus.requestFocus(),
                  isDark: isDark,
                ),

                const SizedBox(height: 14),

                // ── Password field ───────────────────────────────
                _buildTextField(
                  controller: _passwordController,
                  focusNode: _passwordFocus,
                  label: _e(context) ? 'Password' : '密码',
                  hint: _e(context) ? 'Enter password' : '请输入密码',
                  obscure: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _handleLogin(),
                  isDark: isDark,
                  suffix: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      size: 18,
                      color: YLColors.zinc400,
                    ),
                    onPressed: () {
                      setState(() => _obscurePassword = !_obscurePassword);
                    },
                  ),
                ),

                // ── Error message ────────────────────────────────
                if (authState.error != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: YLColors.errorLight,
                      borderRadius: BorderRadius.circular(YLRadius.sm),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_rounded,
                            size: 16, color: YLColors.error),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            authState.error!,
                            style: YLText.caption
                                .copyWith(color: YLColors.error),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // ── Login button ─────────────────────────────────
                SizedBox(
                  height: 46,
                  child: FilledButton(
                    onPressed: authState.isLoading ? null : _handleLogin,
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          isDark ? Colors.white : YLColors.primary,
                      foregroundColor:
                          isDark ? YLColors.primary : Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(YLRadius.md),
                      ),
                      disabledBackgroundColor: isDark
                          ? Colors.white.withValues(alpha: 0.3)
                          : YLColors.zinc300,
                    ),
                    child: authState.isLoading
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: isDark
                                  ? YLColors.primary
                                  : Colors.white,
                            ),
                          )
                        : Text(
                            _e(context) ? 'Sign In' : '登录',
                            style: YLText.label.copyWith(
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? YLColors.primary
                                  : Colors.white,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 14),

                // ── Skip login (guest mode) ──────────────────────
                Center(
                  child: TextButton(
                    onPressed: authState.isLoading
                        ? null
                        : () => ref.read(authProvider.notifier).skipLogin(),
                    child: Text(
                      _e(context) ? 'Skip Login' : '跳过登录',
                      style: YLText.body.copyWith(color: YLColors.zinc500),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // ── Footer ───────────────────────────────────────
                Text(
                  'Powered by ${AppConstants.appBrand}',
                  textAlign: TextAlign.center,
                  style: YLText.caption.copyWith(color: YLColors.zinc400),
                ),

                const SizedBox(height: 48),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    required String hint,
    required bool isDark,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    ValueChanged<String>? onSubmitted,
    bool obscure = false,
    Widget? suffix,
  }) {
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.1)
        : Colors.black.withValues(alpha: 0.08);
    final fillColor = isDark ? YLColors.zinc900 : Colors.white;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: YLText.label.copyWith(
            color: isDark ? YLColors.zinc300 : YLColors.zinc700,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          onSubmitted: onSubmitted,
          obscureText: obscure,
          style: YLText.body.copyWith(
            color: isDark ? Colors.white : YLColors.zinc900,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: YLText.body.copyWith(color: YLColors.zinc400),
            filled: true,
            fillColor: fillColor,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            suffixIcon: suffix,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(YLRadius.md),
              borderSide: BorderSide(color: borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(YLRadius.md),
              borderSide: BorderSide(color: borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(YLRadius.md),
              borderSide: BorderSide(
                color: isDark ? Colors.white.withValues(alpha: 0.3) : YLColors.zinc900,
                width: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }

  bool _e(BuildContext context) => Localizations.localeOf(context).languageCode == 'en';
}
