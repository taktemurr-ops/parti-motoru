import 'package:flutter/material.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/strings.dart';

import '../core.dart';
import '../data/cards.dart';
import '../party.dart';

// ---------------------------------------------------------------- İsim Şehir

class NameCityKind extends PartiKind {
  @override
  String get id => 'isim-sehir';
  const NameCityKind();

  @override
  PDeck? make(int d, SeededRandom r) {
    final n = 3 + d ~/ 4;
    final m = d < 4 ? 5 : 6;
    final b = <int>[];
    for (var k = 0; k < n; k++) {
      // İlk iki sütun her turda klasik: isim ve şehir; kalanlar karışık.
      final rest = perm(kIsimCats.length - 2, r).take(m - 2).map((x) => x + 2);
      b.addAll([0, 1, ...rest]);
    }
    return PDeck(perm(64, r), b: b, n: n, m: m);
  }

  @override
  bool check(PDeck p) {
    if (p.n < 3 || p.n > 5 || (p.m != 5 && p.m != 6) || p.b.length != p.n * p.m) return false;
    if (p.a.length != 64 || !uniqIn(p.a, 64)) return false;
    for (var k = 0; k < p.n; k++) {
      if (!uniqIn(p.b.sublist(k * p.m, (k + 1) * p.m), kIsimCats.length)) return false;
    }
    if (kAlphabets.length != 33 || kIsimCats.any((c) => c.length != 33)) return false;
    return kAlphabets.every((a) => a.split(' ').length >= 8);
  }

  @override
  Widget build(PartiPlay play) => NameCityView(play: play);
}

class NameCityView extends StatefulWidget {
  final PartiPlay play;
  const NameCityView({super.key, required this.play});

  @override
  State<NameCityView> createState() => _NameCityViewState();
}

class _NameCityViewState extends State<NameCityView> with Clock {
  PSettings? s;
  List<String> letters = const [];
  int round = 0;

  /// 0 harf çek, 1 yaz, 2 puanla, 3 sonuç.
  int phase = 0;
  String shown = '?';
  bool rolling = false;
  List<int> totals = const [];
  List<int> now = const [];

  PartiPlay get p => widget.play;
  String t(String k, [Map<String, Object> a = const {}]) => p.t(k, a);

  void _start(PSettings v) {
    final alpha = Strings.pick(kAlphabets, p.lang).split(' ');
    // Harf sırası tohuma bağlı ama dile göre: destedeki sıralama anahtarıyla.
    final order = [for (var i = 0; i < alpha.length; i++) i]..sort((x, y) => p.deck.a[x % 64].compareTo(p.deck.a[y % 64]) != 0
        ? p.deck.a[x % 64].compareTo(p.deck.a[y % 64])
        : x.compareTo(y));
    setState(() {
      s = v;
      letters = [for (final i in order) alpha[i]];
      totals = List.filled(v.count, 0);
      now = List.filled(v.count, 0);
    });
  }

  String get letter => letters[round % letters.length];

  void _roll() {
    if (rolling) return;
    setState(() => rolling = true);
    for (var k = 0; k < 10; k++) {
      later(70 * k, () {
        p.sfx(Sfx.tap);
        setState(() => shown = letters[(round * 7 + k * 3) % letters.length]);
      });
    }
    later(760, () {
      p.sfx(Sfx.unlock);
      setState(() {
        shown = letter;
        rolling = false;
        phase = 1;
      });
    });
  }

  List<int> get cats => p.deck.b.sublist(round * p.deck.m, (round + 1) * p.deck.m);

  @override
  Widget build(BuildContext context) {
    final v = s;
    if (v == null) {
      return Lobby(
        play: p,
        spec: const LobbySpec(minP: 1, maxP: 12, defP: 4, times: [60, 90, 120, 180], defTime: 90),
        emoji: '📝',
        onStart: _start,
      );
    }
    final colors = [for (var i = 0; i < v.count; i++) PColors.player(i)];
    if (phase == 3) return FinalBoard(play: p, names: v.names, scores: totals, colors: colors);
    final bar = PBar(left: t('round', {'n': round + 1, 'm': p.deck.n}), status: '${t('letter')}: ${phase == 0 ? '?' : letter}');
    if (phase == 0) {
      return Column(children: [
        bar,
        Expanded(
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 170,
                height: 170,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: PColors.paper, borderRadius: BorderRadius.circular(32), border: Border.all(color: PColors.line, width: 4)),
                child: Text(shown, style: const TextStyle(fontSize: 96, fontWeight: FontWeight.w900, color: PColors.ink)),
              ),
              const SizedBox(height: 24),
              SizedBox(width: 260, child: BigBtn(label: t('drawLetter'), icon: Icons.casino, color: PColors.bad, onTap: rolling ? null : _roll)),
            ]),
          ),
        ),
      ]);
    }
    if (phase == 1) {
      return Column(children: [
        bar,
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Countdown(key: ValueKey('ns$round'), seconds: v.seconds, sfx: p.sfx, onEnd: () {
            if (mounted && phase == 1) setState(() => phase = 2);
          }),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Center(child: Text(letter, style: const TextStyle(fontSize: 88, fontWeight: FontWeight.w900))),
            Text(t('writeNote'), textAlign: TextAlign.center),
            const SizedBox(height: 10),
            for (final c in cats)
              Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(color: PColors.paper, borderRadius: BorderRadius.circular(14), border: Border.all(color: PColors.line)),
                child: Text(Strings.pick(kIsimCats[c], p.lang),
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: PColors.ink)),
              ),
            const SizedBox(height: 14),
            BigBtn(label: t('stopBtn'), icon: Icons.pan_tool, color: PColors.bad, onTap: () => setState(() => phase = 2)),
          ]),
        ),
      ]);
    }
    return Column(children: [
      bar,
      Expanded(
        child: ListView(padding: const EdgeInsets.all(14), children: [
          Text(t('scoreNote'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 15)),
          const SizedBox(height: 8),
          for (var i = 0; i < v.count; i++)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: colors[i].withValues(alpha: 0.14), borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                Expanded(child: Text(v.names[i], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17))),
                IconButton(
                  tooltip: '−5',
                  onPressed: now[i] >= 5 ? () => setState(() => now[i] -= 5) : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                SizedBox(
                  width: 46,
                  child: Text('${now[i]}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                ),
                for (final add in const [5, 10])
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: OutlinedButton(
                      onPressed: () {
                        p.sfx(Sfx.tap);
                        setState(() => now[i] += add);
                      },
                      child: Text('+$add'),
                    ),
                  ),
              ]),
            ),
          const SizedBox(height: 14),
          BigBtn(
            label: t('next'),
            icon: Icons.arrow_forward,
            color: PColors.good,
            onTap: () => setState(() {
              for (var i = 0; i < v.count; i++) {
                totals[i] += now[i];
                now[i] = 0;
              }
              round++;
              shown = '?';
              phase = round >= p.deck.n ? 3 : 0;
            }),
          ),
          const SizedBox(height: 14),
          ScoreList(names: v.names, scores: totals, colors: colors),
        ]),
      ),
    ]);
  }
}

// ---------------------------------------------------------------- oyuncu alanları (1-4 kişi aynı ekranda)

/// Üstteki alanlar karşıdaki oyuncu için ters çevrilir.
class Zones extends StatelessWidget {
  final int players;
  final Widget Function(int i) zone;
  final Widget center;
  const Zones({super.key, required this.players, required this.zone, required this.center});

  @override
  Widget build(BuildContext context) {
    Widget z(int i, {bool flip = false}) => Expanded(child: flip ? RotatedBox(quarterTurns: 2, child: zone(i)) : zone(i));
    switch (players) {
      case 1:
        return Column(children: [Expanded(flex: 3, child: center), Expanded(flex: 2, child: zone(0))]);
      case 2:
        return Column(children: [
          Expanded(flex: 2, child: RotatedBox(quarterTurns: 2, child: zone(1))),
          Expanded(flex: 3, child: center),
          Expanded(flex: 2, child: zone(0)),
        ]);
      default:
        return Column(children: [
          Expanded(flex: 2, child: Row(children: [z(2, flip: true), if (players > 3) z(3, flip: true)])),
          Expanded(flex: 3, child: center),
          Expanded(flex: 2, child: Row(children: [z(0), z(1)])),
        ]);
    }
  }
}

// ---------------------------------------------------------------- Aile Bilgi Yarışması (emoji soruları)

/// Soru: [tür, cevap, s0..s3, ızgara 16, hedef] = 23 sayı.
const kQLen = 23;
const _whichCats = ['a', 'f', 'v', 'n', 's'];

class FamilyQuizKind extends PartiKind {
  @override
  String get id => 'aile-bilgi';
  const FamilyQuizKind();

  List<int> _cat(String c) => [for (var i = 0; i < kCards.length; i++) if (kCards[i].cat == c) i];

  List<int> _q(int type, SeededRandom r) {
    final q = List.filled(kQLen, -1);
    q[0] = type;
    switch (type) {
      case 0: {
        // Hangisi farklı: üçü aynı kategoriden, biri başka.
        final cats = ['a', 'f', 'o', 'v', 'j', 's'];
        r.shuffle(cats);
        final same = _cat(cats[0]);
        r.shuffle(same);
        final other = _cat(cats[1]);
        final opts = [same[0], same[1], same[2], r.pick(other)];
        r.shuffle(opts);
        for (var k = 0; k < 4; k++) {
          q[2 + k] = opts[k];
        }
        q[1] = opts.indexWhere((x) => kCards[x].cat == cats[1]);
      }
      case 1: {
        // Kaç tane: ızgarada hedef emojiden 2-7 tane.
        final pool = _cat(r.pick(const ['a', 'f', 'n']));
        r.shuffle(pool);
        final target = pool[0];
        final cnt = r.range(2, 7);
        final cells = <int>[for (var k = 0; k < cnt; k++) target];
        while (cells.length < 12 + r.nextInt(5)) {
          cells.add(pool[1 + r.nextInt(3)]);
        }
        r.shuffle(cells);
        for (var k = 0; k < cells.length; k++) {
          q[6 + k] = cells[k];
        }
        q[22] = target;
        final opts = <int>{cnt};
        while (opts.length < 4) {
          final x = cnt + r.range(-3, 3);
          if (x >= 1 && x <= 9) opts.add(x);
        }
        final ol = opts.toList();
        r.shuffle(ol);
        for (var k = 0; k < 4; k++) {
          q[2 + k] = ol[k];
        }
        q[1] = ol.indexOf(cnt);
      }
      case 2: {
        // Hangisi bir hayvan / yiyecek / taşıt / doğa / spor?
        final ci = r.nextInt(_whichCats.length);
        final yes = _cat(_whichCats[ci]);
        final no = [for (var i = 0; i < kCards.length; i++) if (kCards[i].cat != _whichCats[ci] && kCards[i].cat != 'x') i];
        r.shuffle(no);
        final opts = [r.pick(yes), no[0], no[1], no[2]];
        r.shuffle(opts);
        for (var k = 0; k < 4; k++) {
          q[2 + k] = opts[k];
        }
        q[1] = opts.indexWhere((x) => kCards[x].cat == _whichCats[ci]);
        q[22] = ci;
      }
      default: {
        // Hangisinden en çok var: üç emoji, sayıları farklı.
        final pool = _cat(r.pick(const ['f', 'a', 'o']));
        r.shuffle(pool);
        final counts = [r.range(2, 3), r.range(4, 5), r.range(6, 7)];
        r.shuffle(counts);
        final cells = <int>[];
        for (var k = 0; k < 3; k++) {
          for (var c = 0; c < counts[k]; c++) {
            cells.add(pool[k]);
          }
          q[2 + k] = pool[k];
        }
        r.shuffle(cells);
        for (var k = 0; k < cells.length; k++) {
          q[6 + k] = cells[k];
        }
        var best = 0;
        for (var k = 1; k < 3; k++) {
          if (counts[k] > counts[best]) best = k;
        }
        q[1] = best;
      }
    }
    return q;
  }

  @override
  PDeck? make(int d, SeededRandom r) {
    final n = 10 + d;
    final a = <int>[];
    for (var k = 0; k < n; k++) {
      // Türler dengeli dağılır; zorlukla birlikte sayma soruları artar.
      final type = r.weighted([4, 2 + d ~/ 3, 4, 2 + d ~/ 4]);
      a.addAll(_q(type, r));
    }
    return PDeck(a, n: n);
  }

  @override
  bool check(PDeck p) {
    if (p.n < 11 || p.n > 20 || p.a.length != p.n * kQLen) return false;
    for (var k = 0; k < p.n; k++) {
      if (!quizOk(p.a.sublist(k * kQLen, (k + 1) * kQLen))) return false;
    }
    return true;
  }

  @override
  Widget build(PartiPlay play) => FamilyQuizView(play: play);
}

/// Sorunun tek doğru cevabı olduğunu denetler.
bool quizOk(List<int> q) {
  final type = q[0], ans = q[1];
  final grid = [for (var k = 6; k < 22; k++) if (q[k] >= 0) q[k]];
  switch (type) {
    case 0: {
      final opts = q.sublist(2, 6);
      if (!uniqIn(opts, kCards.length) || ans < 0 || ans > 3) return false;
      final odd = kCards[opts[ans]].cat;
      final others = [for (var k = 0; k < 4; k++) if (k != ans) kCards[opts[k]].cat];
      return others.toSet().length == 1 && others.first != odd;
    }
    case 1: {
      final opts = q.sublist(2, 6);
      if (opts.toSet().length != 4 || ans < 0 || ans > 3 || q[22] < 0) return false;
      return grid.where((x) => x == q[22]).length == opts[ans] && grid.length >= 12;
    }
    case 2: {
      final opts = q.sublist(2, 6);
      if (!uniqIn(opts, kCards.length) || ans < 0 || ans > 3 || q[22] < 0 || q[22] >= _whichCats.length) return false;
      final c = _whichCats[q[22]];
      return [for (final o in opts) if (kCards[o].cat == c) o].length == 1 && kCards[opts[ans]].cat == c;
    }
    case 3: {
      final opts = q.sublist(2, 5);
      if (!uniqIn(opts, kCards.length) || ans < 0 || ans > 2) return false;
      final counts = [for (final o in opts) grid.where((x) => x == o).length];
      if (counts.toSet().length != 3 || grid.length != counts.fold<int>(0, (a, b) => a + b)) return false;
      return counts[ans] == counts.reduce((a, b) => a > b ? a : b);
    }
    default: {
      return false;
    }
  }
}

class FamilyQuizView extends StatefulWidget {
  final PartiPlay play;
  const FamilyQuizView({super.key, required this.play});

  @override
  State<FamilyQuizView> createState() => _FamilyQuizViewState();
}

class _FamilyQuizViewState extends State<FamilyQuizView> with Clock {
  PSettings? s;
  int qi = 0;
  List<int> scores = const [];
  Set<int> locked = {};
  int? solvedBy;

  PartiPlay get p => widget.play;
  String t(String k, [Map<String, Object> a = const {}]) => p.t(k, a);

  List<int> get q => p.deck.a.sublist(qi * kQLen, (qi + 1) * kQLen);

  String get question => switch (q[0]) {
        0 => t('odd'),
        1 => t('countQ'),
        2 => t('which_${_whichCats[q[22]]}'),
        _ => t('most'),
      };

  void _answer(int player, int k) {
    final v = s;
    if (v == null || solvedBy != null || locked.contains(player)) return;
    if (k == q[1]) {
      p.sfx(Sfx.win);
      setState(() {
        solvedBy = player;
        scores[player]++;
      });
      later(1100, _nextQ);
    } else {
      p.sfx(Sfx.error);
      setState(() => locked.add(player));
      if (locked.length >= v.count) {
        setState(() => solvedBy = -1);
        later(1300, _nextQ);
      }
    }
  }

  void _nextQ() => setState(() {
        qi++;
        locked = {};
        solvedBy = null;
      });

  String _opt(int k) {
    final x = q[2 + k];
    if (q[0] == 1) return '$x';
    return kCards[x].emoji;
  }

  Widget _zone(int i) {
    final v = s!;
    final c = PColors.player(i);
    final n = q[0] == 3 ? 3 : 4;
    final lock = locked.contains(i);
    return Container(
      margin: const EdgeInsets.all(4),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: c.withValues(alpha: lock ? 0.08 : 0.2),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: solvedBy == i ? PColors.good : c, width: solvedBy == i ? 4 : 2),
      ),
      child: Column(children: [
        Text('${v.names[i]} · ${scores[i]}', maxLines: 1, style: TextStyle(fontWeight: FontWeight.w800, color: c)),
        const SizedBox(height: 4),
        Expanded(
          child: Row(children: [
            for (var k = 0; k < n; k++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: Material(
                    color: solvedBy != null && k == q[1] ? PColors.good : PColors.paper,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: lock ? null : () => _answer(i, k),
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(_opt(k), style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: PColors.ink)),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      ]),
    );
  }

  Widget _center() {
    final grid = [for (var k = 6; k < 22; k++) if (q[k] >= 0) q[k]];
    final showGrid = q[0] == 1 || q[0] == 3;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(children: [
        Text(t('round', {'n': qi + 1, 'm': p.deck.n}), style: const TextStyle(fontSize: 13)),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Flexible(
            child: Text(question, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          ),
          if (q[0] == 1) Text('  ${kCards[q[22]].emoji}', style: const TextStyle(fontSize: 34)),
        ]),
        if (showGrid)
          Expanded(
            child: Center(
              child: Wrap(alignment: WrapAlignment.center, children: [
                for (final g in grid) Padding(padding: const EdgeInsets.all(3), child: Text(kCards[g].emoji, style: const TextStyle(fontSize: 30))),
              ]),
            ),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final v = s;
    if (v == null) {
      return Lobby(
        play: p,
        spec: const LobbySpec(minP: 1, maxP: 4, defP: 2),
        emoji: '🧠',
        onStart: (x) => setState(() {
          s = x;
          scores = List.filled(x.count, 0);
        }),
      );
    }
    if (qi >= p.deck.n) {
      return FinalBoard(play: p, names: v.names, scores: scores, colors: [for (var i = 0; i < v.count; i++) PColors.player(i)]);
    }
    return Zones(players: v.count, zone: _zone, center: _center());
  }
}

// ---------------------------------------------------------------- Emoji İpucu (5×5 takım tahmini)

class EmojiClueKind extends PartiKind {
  @override
  String get id => 'kelime-ipucu';
  const EmojiClueKind();

  @override
  PDeck? make(int d, SeededRandom r) {
    final pool = [for (var i = 0; i < kCards.length; i++) if (kCards[i].cat != 'x') i];
    r.shuffle(pool);
    final cards = pool.take(25).toList();
    final key = [for (var i = 0; i < 9; i++) 0, for (var i = 0; i < 8; i++) 1, for (var i = 0; i < 7; i++) 2, 3];
    r.shuffle(key);
    return PDeck(cards, b: key, n: d);
  }

  @override
  bool check(PDeck p) {
    if (p.a.length != 25 || !uniqIn(p.a, kCards.length) || p.b.length != 25) return false;
    final c = List.filled(4, 0);
    for (final k in p.b) {
      if (k < 0 || k > 3) return false;
      c[k]++;
    }
    // Kategoriler çeşitli olmalı ki ipuçları birden çok karta bağlanabilsin.
    final cats = {for (final i in p.a) kCards[i].cat};
    if (cats.contains('x') || {for (final i in p.a) kCards[i].emoji}.length != 25) return false;
    return c[0] == 9 && c[1] == 8 && c[2] == 7 && c[3] == 1 && cats.length >= 4;
  }

  @override
  Widget build(PartiPlay play) => EmojiClueView(play: play);
}

const _keyColors = [Color(0xFFE0735A), Color(0xFF3B86A8), Color(0xFFD8CFBF), Color(0xFF2B2B2B)];

class EmojiClueView extends StatefulWidget {
  final PartiPlay play;
  const EmojiClueView({super.key, required this.play});

  @override
  State<EmojiClueView> createState() => _EmojiClueViewState();
}

class _EmojiClueViewState extends State<EmojiClueView> {
  PSettings? s;
  bool keyGate = true;
  bool keyOpen = false;
  final Set<int> open = {};
  int team = 0;
  int? sel;
  int winner = -1;

  PartiPlay get p => widget.play;
  String t(String k, [Map<String, Object> a = const {}]) => p.t(k, a);

  int left(int tm) => [for (var i = 0; i < 25; i++) if (p.deck.b[i] == tm && !open.contains(i)) i].length;

  void _tap(int i) {
    if (open.contains(i) || winner >= 0) return;
    if (sel != i) {
      p.sfx(Sfx.tap);
      setState(() => sel = i);
      return;
    }
    final k = p.deck.b[i];
    setState(() {
      open.add(i);
      sel = null;
      if (k == 3) {
        winner = 1 - team;
        p.sfx(Sfx.lose);
      } else if (left(0) == 0) {
        winner = 0;
      } else if (left(1) == 0) {
        winner = 1;
      } else if (k != team) {
        team = 1 - team;
        p.sfx(Sfx.error);
      } else {
        p.sfx(Sfx.coin);
      }
    });
    if (winner >= 0) p.sfx(Sfx.win);
  }

  Widget _grid({required bool key}) {
    return LayoutBuilder(builder: (context, box) {
      final side = (box.maxWidth < box.maxHeight ? box.maxWidth : box.maxHeight) / 5;
      return Center(
        child: SizedBox(
          width: side * 5,
          height: side * 5,
          child: GridView.count(
            crossAxisCount: 5,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (var i = 0; i < 25; i++)
                Padding(
                  padding: const EdgeInsets.all(3),
                  child: Material(
                    color: key || open.contains(i) ? _keyColors[p.deck.b[i]] : PColors.paper,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: key ? null : () => _tap(i),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: sel == i ? PColors.warn : PColors.line, width: sel == i ? 4 : 1),
                        ),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Text(kCards[p.deck.a[i]].emoji, style: TextStyle(fontSize: side * 0.38)),
                          if (side > 62)
                            Text(cardLabel(p.lang, kCards[p.deck.a[i]]),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: side * 0.13, color: PColors.ink)),
                        ]),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final v = s;
    if (v == null) {
      return Lobby(
        play: p,
        spec: const LobbySpec(minP: 4, maxP: 12, defP: 4, teams: 2),
        emoji: '🔎',
        onStart: (x) => setState(() => s = x),
      );
    }
    final ta = t('team', {'n': 'A'}), tb = t('team', {'n': 'B'});
    if (winner >= 0) {
      final sc = [9 - left(0), 8 - left(1)];
      return FinalBoard(
        play: p,
        names: [ta, tb],
        scores: sc,
        colors: PColors.teams,
        headline: t('wins', {'n': winner == 0 ? ta : tb}),
      );
    }
    if (keyGate) {
      return Column(children: [
        PBar(status: t('keyNote')),
        Expanded(
          child: keyOpen
              ? Column(children: [
                  Expanded(child: Padding(padding: const EdgeInsets.all(8), child: _grid(key: true))),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: BigBtn(
                      label: t('hide'),
                      icon: Icons.visibility_off,
                      color: PColors.ink,
                      onTap: () => setState(() {
                        keyOpen = false;
                        keyGate = false;
                      }),
                    ),
                  ),
                ])
              : PassGate(lang: p.lang, name: t('clueGivers'), color: PColors.ink, note: t('keyNote'), onReady: () => setState(() => keyOpen = true)),
        ),
      ]);
    }
    final tc = PColors.teams[team];
    return Column(children: [
      PBar(
        left: team == 0 ? ta : tb,
        status: '🟥 ${left(0)}  🟦 ${left(1)}',
        extra: [
          IconButton(
            tooltip: t('key'),
            onPressed: () => setState(() => keyGate = true),
            icon: const Icon(Icons.key),
          ),
        ],
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
        child: Text(t('clueNote'), textAlign: TextAlign.center, style: TextStyle(color: tc, fontWeight: FontWeight.w700)),
      ),
      Expanded(child: Padding(padding: const EdgeInsets.all(6), child: _grid(key: false))),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: BigBtn(
          label: t('endTurn'),
          icon: Icons.swap_horiz,
          color: tc,
          onTap: () => setState(() {
            team = 1 - team;
            sel = null;
          }),
        ),
      ),
    ]);
  }
}
