import 'package:flutter_test/flutter_test.dart';
import 'package:parti_motoru/src/data/cards.dart';
import 'package:parti_motoru/src/data/spectra.dart';
import 'package:parti_motoru/src/party.dart';
import 'package:studio_core/core/strings.dart';

void _all33(List<String> l, String what) {
  expect(l.length, 33, reason: what);
  for (var k = 0; k < l.length; k++) {
    expect(l[k].trim().isNotEmpty, isTrue, reason: '$what [${Strings.languages[k]}]');
  }
}

void main() {
  test('dil sırası studio-core ile aynı (33 dil)', () {
    expect(Strings.languages.length, 33);
  });

  test('emoji kartları: her kart 33 dilde dolu', () {
    for (final c in kCards) {
      _all33(c.names, 'kart ${c.emoji}');
    }
    expect(cardLabel('de', kCards.first), kCards.first.names[2]);
  });

  test('mekânlar, İsim Şehir sütunları ve harfler 33 dilde', () {
    for (final p in kPlaces) {
      _all33(p.names, 'mekân ${p.emoji}');
    }
    for (final c in kIsimCats) {
      _all33(c, 'sütun ${c[1]}');
    }
    _all33(kAlphabets, 'harfler');
  });

  test('Yasaklı Kelime: 33 deste, her kartta kelime ve 4 yasak', () {
    expect(kTabu.length, 33);
    for (var k = 0; k < kTabu.length; k++) {
      final deck = kTabu[k];
      expect(deck.length, kTabuTr.length, reason: Strings.languages[k]);
      for (var i = 0; i < deck.length; i++) {
        final c = deck[i];
        final where = '${Strings.languages[k]} #$i';
        expect(c.word.trim().isNotEmpty, isTrue, reason: where);
        expect(c.no.length, 4, reason: where);
        expect(c.no.every((x) => x.trim().isNotEmpty), isTrue, reason: where);
        expect(c.no.contains(c.word), isFalse, reason: where);
        expect(c.tier, kTabuTr[i].tier, reason: where);
        expect(c.emoji, kTabuTr[i].emoji, reason: where);
      }
    }
  });

  test('Doğruluk ve görev kartları 33 dilde', () {
    for (final pair in [(kTruth, kTruthTr, 'doğruluk'), (kDare, kDareTr, 'görev')]) {
      expect(pair.$1.length, 33);
      for (var k = 0; k < 33; k++) {
        final l = pair.$1[k];
        expect(l.length, pair.$2.length, reason: '${pair.$3} ${Strings.languages[k]}');
        for (var i = 0; i < l.length; i++) {
          expect(l[i].text.trim().isNotEmpty, isTrue, reason: '${pair.$3} ${Strings.languages[k]} #$i');
          expect(l[i].tier, pair.$2[i].tier);
        }
      }
    }
    expect(langItem(kTruth, 'ja'), kTruth[23]);
    expect(langItem(kTruth, 'xx'), kTruthEn);
  });

  test('Isı Ölçer: her ölçeğin iki ucu 33 dilde dolu ve farklı', () {
    for (final s in kSpectra) {
      _all33(s.l, 'sol ${s.l[1]}');
      _all33(s.r, 'sağ ${s.r[1]}');
      for (var k = 0; k < 33; k++) {
        expect(s.l[k] == s.r[k], isFalse, reason: '${s.l[1]} ${Strings.languages[k]}');
      }
    }
    expect(kSpectra.first.left('fr'), kSpectra.first.l[4]);
  });
}
