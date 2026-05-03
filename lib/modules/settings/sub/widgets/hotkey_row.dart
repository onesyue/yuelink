import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/settings_service.dart';
import '../../../../i18n/app_strings.dart';
import '../../../../theme.dart';
import '../../hotkey_codec.dart';
import '../../providers/settings_providers.dart';
import '../../widgets/primitives.dart';

/// Desktop-only: inline hotkey display + "Edit" button that opens a
/// modal KeyboardListener to capture a new combo.
///
/// Extracted from `sub/general_settings_page.dart` (Batch ε). Owns its
/// own `_registering` state + FocusNode lifecycle; consumes
/// `toggleHotkeyProvider` directly. No page-level state closure.
class HotkeyRow extends ConsumerStatefulWidget {
  const HotkeyRow({super.key});

  @override
  ConsumerState<HotkeyRow> createState() => _HotkeyRowState();
}

class _HotkeyRowState extends ConsumerState<HotkeyRow> {
  bool _registering = false;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final stored = ref.watch(toggleHotkeyProvider);
    final display = displayHotkey(stored);

    return YLInfoRow(
      label: s.toggleConnectionHotkey,
      trailing: YLSettingsValueButton(
        label: _registering ? s.hotkeyListening : display,
      ),
      enabled: !_registering,
      onTap: _registering ? null : () => _startRecording(s),
    );
  }

  void _startRecording(S s) {
    setState(() => _registering = true);
    final focusNode = FocusNode();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(s.hotkeyListening),
        content: KeyboardListener(
          focusNode: focusNode..requestFocus(),
          autofocus: true,
          onKeyEvent: (event) {
            if (event is! KeyDownEvent) return;
            if (_isModifierOnly(event.logicalKey)) return;

            final parts = <String>[];
            if (HardwareKeyboard.instance.isControlPressed) parts.add('ctrl');
            if (HardwareKeyboard.instance.isAltPressed) parts.add('alt');
            if (HardwareKeyboard.instance.isShiftPressed) parts.add('shift');
            if (HardwareKeyboard.instance.isMetaPressed) parts.add('meta');

            final label = event.logicalKey.keyLabel.toLowerCase();
            if (label.isNotEmpty && !parts.contains(label)) parts.add(label);

            if (parts.length >= 2) {
              final combo = parts.join('+');
              ref.read(toggleHotkeyProvider.notifier).set(combo);
              SettingsService.setToggleHotkey(combo);
              Navigator.pop(ctx);
            }
          },
          child: SizedBox(
            height: 60,
            child: Center(
              child: Text(
                s.hotkeyPrompt,
                style: YLText.body.copyWith(color: YLColors.zinc500),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.cancel),
          ),
        ],
      ),
    ).whenComplete(() {
      setState(() => _registering = false);
      focusNode.dispose();
    });
  }

  bool _isModifierOnly(LogicalKeyboardKey key) {
    final modifiers = {
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.controlRight,
      LogicalKeyboardKey.shift,
      LogicalKeyboardKey.shiftLeft,
      LogicalKeyboardKey.shiftRight,
      LogicalKeyboardKey.alt,
      LogicalKeyboardKey.altLeft,
      LogicalKeyboardKey.altRight,
      LogicalKeyboardKey.meta,
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.metaRight,
      LogicalKeyboardKey.capsLock,
      LogicalKeyboardKey.fn,
    };
    return modifiers.contains(key);
  }
}
