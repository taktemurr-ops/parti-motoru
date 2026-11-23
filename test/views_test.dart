import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parti_motoru/parti_motoru.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:studio_core/app/game_api.dart';
import 'package:studio_core/core/game_rules.dart';
import 'package:studio_core/core/level_plan.dart';

PlayContext fakeCtx(GeneratedLevel gl, String lang, List<RoundResult> results) => PlayContext(
      spec: gl.spec,
      generated: gl,
      resume: const {},
      pieceColors: const [Color(0xFF3E6FB0), Color(0xFFC8553D), Color(0xFF4F9A6E)],
      background: const [Color(0xFF203040), Color(0xFF304050)],
      colorBlind: false,
      reducedMotion: false,
      leftHanded: false,
      lang: lang,
      t: (k, [p = const {}]) => p.isEmpty ? k : '$k ${p.values.join(' ')}',
      finish: results.add,
      saveResume: (_) {},
      requestHint: () async => true,
      requestBooster: () async => true,
      requestContinue: () async => false,
      sfx: (_) {},
    );

bool _isDialog(Widget w) => w is Dialog || w is AlertDialog || w is SimpleDialog;

void main() {
  for (final e in kPartiKinds.entries) {
    for (final lang in const ['tr', 'en', 'ar']) {
      testWidgets('${e.key} ($lang): lobi ve oyun açılır, dokunuşlara dayanır', (tester) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = const Size(1080, 2280);
        tester.view.devicePixelRatio = 2.75;
        addTearDown(tester.view.reset);
        final rules = partiRulesFor('oyun-test-${e.key}', e.key);
        final planner = LevelPlanner(gameId: rules.gameId, optionalMechanics: const []);
        final gl = rules.build(planner.spec(5));
        final results = <RoundResult>[];
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: SafeArea(child: PartiStage(ctx: fakeCtx(gl, lang, results), rules: rules))),
        ));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        // Lobiden oyuna geç.
        final start = find.byIcon(Icons.play_arrow);
        expect(start, findsOneWidget);
        await tester.ensureVisible(start);
        await tester.pump(const Duration(milliseconds: 200));
        await tester.tap(start);
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        expect(start, findsNothing);
        // Ekranın çeşitli yerlerine dokun (açılan pencereleri kapat).
        final size = tester.view.physicalSize / tester.view.devicePixelRatio;
        for (var round = 0; round < 2; round++) {
          for (var y = 60.0; y < size.height - 10; y += size.height / 9) {
            for (var x = 20.0; x < size.width; x += size.width / 5) {
              if (results.isNotEmpty) break;
              await tester.tapAt(Offset(x, y));
              await tester.pump(const Duration(milliseconds: 150));
              if (find.byWidgetPredicate(_isDialog).evaluate().isNotEmpty) {
                await tester.tapAt(const Offset(5, 5));
                await tester.pump(const Duration(milliseconds: 300));
              }
            }
          }
          await tester.pump(const Duration(seconds: 2));
        }
        await tester.dragFrom(Offset(size.width * 0.5, size.height * 0.5), Offset(size.width * 0.2, size.height * 0.1));
        await tester.pump(const Duration(seconds: 2));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 3));
      });
    }
  }
}
