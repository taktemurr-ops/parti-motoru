import 'package:flutter_test/flutter_test.dart';
import 'package:parti_motoru/parti_motoru.dart';
import 'package:studio_core/core/level_plan.dart';

void main() {
  for (final e in kPartiKinds.entries) {
    test('${e.key}: desteler kurulur ve doğrulanır', () {
      final rules = partiRulesFor('oyun-test-${e.key}', e.key);
      final planner = LevelPlanner(gameId: rules.gameId, optionalMechanics: const []);
      for (final n in const [1, 7, 40, 300, 5000, 99999]) {
        expect(rules.build(planner.spec(n)).validation.ok, isTrue, reason: '${e.key} $n');
      }
    });
  }

  test('33 dilde bütün metinler dolu', () {
    for (final e in kPartiTexts.entries) {
      expect(e.value.length, 33, reason: e.key);
      for (final s in e.value) {
        expect(s.trim().isNotEmpty, isTrue, reason: e.key);
      }
    }
    expect(pt('tr', 'wins', {'n': 'Ayşe'}), 'Ayşe kazandı!');
    expect(pt('en', 'round', {'n': 2, 'm': 5}), 'Round 2/5');
  });
}
