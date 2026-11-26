import 'package:flutter_test/flutter_test.dart';
import 'package:parti_motoru/parti_motoru.dart';
import 'package:parti_motoru/src/data/cards.dart';
import 'package:parti_motoru/src/kinds/ek4.dart';
import 'package:parti_motoru/src/kinds/pen.dart' show dialPoints;
import 'package:studio_core/core/level_plan.dart';

void main() {
  test('Köşe Kapışması: 20 mini oyunun her biri 2-4 kişide kurallı plan üretir', () {
    for (var g = 0; g < kMgCount; g++) {
      for (var players = 2; players <= 4; players++) {
        for (var seed = 0; seed < 60; seed++) {
          final plan = mgPlan(g, players, 1 + seed % 10, seed * 7919 + g);
          expect(mgPlanOk(plan, players), isTrue, reason: 'mg$g $players $seed');
        }
      }
      expect(pt('tr', 'mg$g').isNotEmpty && pt('tr', 'mg$g') != 'mg$g', isTrue);
    }
    final kinds = {...kMgReact, ...kMgScore, ...kMgMash, ...kMgTiming, 8};
    expect(kinds.length, kMgCount);
    expect(cornerDirs(2).length, 2);
    expect(cornerDirs(4).length, 4);
  });

  test('Köşe Kapışması: ortak tetikte tam bir doğru an var ve önce gelmez', () {
    for (var seed = 0; seed < 200; seed++) {
      final plan = mgPlan(0, 3, 5, seed);
      final go = plan.steps.indexWhere((s) => s.go);
      expect(go, greaterThanOrEqualTo(3));
    }
  });

  test('Hangisini Seçerdin?: iki kart aynı kategoride, çocuk paketine uygun, tekrar yok', () {
    final rules = partiRulesFor('oyun-hangisini', 'hangisini');
    final planner = LevelPlanner(gameId: rules.gameId, optionalMechanics: const []);
    for (var s = 1; s < 300; s += 37) {
      final lv = rules.build(planner.spec(s)).puzzle;
      final pairs = wyrPairs(lv.deck.a, lv.deck.b, 0, lv.deck.n);
      expect(pairs.length, lv.deck.n);
      final seen = <int>{};
      for (final (a, b, cat) in pairs) {
        expect(kCards[a].cat, cat);
        expect(kCards[b].cat, cat);
        expect(kCards[a].tier, 0);
        expect(seen.add(a) && seen.add(b), isTrue);
      }
    }
    for (final c in kWyrCats) {
      expect(pt('de', 'wyrQ_$c') != 'wyrQ_$c', isTrue);
    }
  });

  test('Tek İpucu: aynı ve kelimeyi içeren ipuçları elenir', () {
    expect(autoCancel(['Süt', 'süt!', 'Boynuz', 'Çiftlik'], 'İnek'), [2, 3]);
    expect(autoCancel(['Kedicik', 'Miyav'], 'Kedi'), [1]);
    expect(autoCancel(['', 'Uzay'], 'Roket'), [1]);
  });

  test('Ayar Tuttur: puanlar Isı Ölçer ile aynı ölçekte', () {
    expect(dialPoints(50, 52), 3);
    expect(dialPoints(50, 58), 2);
    expect(dialPoints(50, 64), 1);
    expect(dialPoints(50, 90), 0);
    expect(pt('tr', 'dialModeAll').startsWith('Ayar Tuttur'), isTrue);
  });
}
