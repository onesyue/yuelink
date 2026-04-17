import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/modules/onboarding/persona_prompt_page.dart';

void main() {
  group('PersonaPromptPage', () {
    testWidgets('tapping "我是新手" saves persona=newcomer', (tester) async {
      String? saved;
      await tester.pumpWidget(MaterialApp(
        home: PersonaPromptPage(
          onChosen: (persona) async {
            saved = persona;
          },
        ),
      ));

      expect(find.text('你用过类似的网络工具吗？'), findsOneWidget);
      expect(find.text('我是新手'), findsOneWidget);

      await tester.tap(find.text('我是新手'));
      await tester.pumpAndSettle();

      expect(saved, 'newcomer');
    });

    testWidgets('tapping the experienced button saves persona=experienced',
        (tester) async {
      String? saved;
      await tester.pumpWidget(MaterialApp(
        home: PersonaPromptPage(
          onChosen: (persona) async {
            saved = persona;
          },
        ),
      ));

      await tester.tap(find.text('我用过 Clash/V2Ray 等工具'));
      await tester.pumpAndSettle();

      expect(saved, 'experienced');
    });

    testWidgets('tapping "跳过" saves persona=unknown', (tester) async {
      String? saved;
      await tester.pumpWidget(MaterialApp(
        home: PersonaPromptPage(
          onChosen: (persona) async {
            saved = persona;
          },
        ),
      ));

      await tester.tap(find.text('跳过'));
      await tester.pumpAndSettle();

      expect(saved, 'unknown');
    });
  });
}
