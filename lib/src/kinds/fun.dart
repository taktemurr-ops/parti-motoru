import 'dart:async';

import 'package:flutter/material.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/rng.dart';

import '../core.dart';
import '../data/cards.dart';
import '../party.dart';
import 'quiz.dart' show Zones;

// ---------------------------------------------------------------- Skor Tahtası

const kScoreTargets = [10, 15, 20, 25, 30, 40, 50, 75, 100, 150];

class ScoreKind extends PartiKind {
  @override
  String get id => 'skor-tahtasi';
  const ScoreKind();

  @override
  PDeck? make(int d, SeededRandom r) => PDeck([for (var i = 0; i < 60; i++) r.range(1, 6)], n: kScoreTargets[clampI(d, 1, 10) - 1]);

  @override
  bool check(PDeck p) => p.a.length == 60 && p.a.every((x) => x >= 1 && x <= 6) && kScoreTargets.contains(p.n);

  @override
  Widget build(PartiPlay play) => ScoreView(play: play);
}

class ScoreView extends StatefulWidget {
  final PartiPlay play;
  const ScoreView({super.key, required this.play});

  @override
  State<ScoreView> createState() => _ScoreViewState();
}

class _ScoreViewState extends State<ScoreView> {
  PSettings? s;
  List<int> scores = const [];
  final List<(int, int)> history = [];
  int round = 1;
  int dice = 0;
  List<int> rolled = const [];
  bool done = false;
  int? reached;

  PartiPlay get p => widget.play;
  String t(String k, [Map<String, Object> a = const {}]) => p.t(k, a);

  void _add(int i, int d) {
    p.sfx(d > 0 ? Sfx.coin : Sfx.tap);
    setState(() {
      scores[i] += d;
      history.add((i, d));
      if (reached == null && scores[i] >= p.deck.n) {
        reached = i;
        p.sfx(Sfx.win);
      }
    });
  }

  void _undo() {
    if (history.isEmpty) return;
    setState(() {
      final (i, d) = history.removeLast();
      scores[i] -= d;
      if (reached == i && scores[i] < p.deck.n) reached = null;
    });
  }

  void _roll() {
    p.sfx(Sfx.place);
    setState(() {
      rolled = [p.deck.a[dice % 60], p.deck.a[(dice + 1) % 60]];
      dice += 2;
    });
  }

  @override
  Widget build(BuildContext context) {
    final v = s;
    if (v == null) {
      return Lobby(
        play: p,
        spec: const LobbySpec(minP: 1, maxP: 12, defP: 4, teams: 1),
        emoji: '📋',
        onStart: (x) => setState(() {
          s = x;
          scores = List.filled(x.teams ? 2 : x.count, 0);
        }),
      );
    }
    final names = v.teams ? [t('team', {'n': 'A'}), t('team', {'n': 'B'})] : v.names;
    final colors = v.teams ? PColors.teams : [for (var i = 0; i < v.count; i++) PColors.player(i)];
    if (done) return FinalBoard(play: p, names: names, scores: scores, colors: colors);
    const faces = ['⚀', '⚁', '⚂', '⚃', '⚄', '⚅'];
    final rc = reached;
    return Column(children: [
      PBar(
        left: t('goal', {'n': p.deck.n}),
        status: t('roundN', {'n': round}),
        extra: [
          IconButton(tooltip: t('undo'), onPressed: history.isEmpty ? null : _undo, icon: const Icon(Icons.undo)),
          IconButton(tooltip: '+', onPressed: () => setState(() => round++), icon: const Icon(Icons.exposure_plus_1)),
        ],
      ),
      if (rc != null)
        Container(
          margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: PColors.warn.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(12)),
          child: Text('🏁 ${t('wins', {'n': names[rc]})}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
      Expanded(
        child: ListView(padding: const EdgeInsets.all(10), children: [
          for (var i = 0; i < names.length; i++)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: colors[i].withValues(alpha: 0.15), borderRadius: BorderRadius.circular(16)),
              child: Row(children: [
                CircleAvatar(radius: 10, backgroundColor: colors[i]),
                const SizedBox(width: 8),
                Expanded(child: Text(names[i], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17))),
                IconButton(tooltip: '−1', onPressed: () => _add(i, -1), icon: const Icon(Icons.remove_circle_outline)),
                GestureDetector(
                  onLongPress: () => _add(i, 10),
                  child: SizedBox(
                    width: 58,
                    child: Text('${scores[i]}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
                  ),
                ),
                IconButton(tooltip: '+1', onPressed: () => _add(i, 1), icon: const Icon(Icons.add_circle)),
                TextButton(onPressed: () => _add(i, 5), child: const Text('+5')),
              ]),
            ),
          const SizedBox(height: 6),
          Text(t('scoreTip'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 13)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Row(children: [
          Expanded(
            child: BigBtn(
              label: rolled.isEmpty ? t('roll') : rolled.map((x) => faces[x - 1]).join(' '),
              icon: Icons.casino,
              color: PColors.ink,
              onTap: _roll,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: BigBtn(label: t('finish'), icon: Icons.flag, color: PColors.good, onTap: () => setState(() => done = true))),
        ]),
      ),
    ]);
  }
}

// ---------------------------------------------------------------- Emoji Hikâye (özgün)

class StoryKind extends PartiKind {
  @override
  String get id => 'emoji-hikaye';
  const StoryKind();

  @override
  PDeck? make(int d, SeededRandom r) {
    final pool = [for (var i = 0; i < kCards.length; i++) if (kCards[i].cat != 'j' || r.chance(0.5)) i];
    r.shuffle(pool);
    return PDeck(pool.take(150).toList(), n: 1 + d ~/ 6, m: 5 + (d + 1) ~/ 3);
  }

  @override
  bool check(PDeck p) {
    if (p.n < 1 || p.n > 2 || p.m < 5 || p.m > 8 || !uniqIn(p.a, kCards.length) || p.a.length != 150) return false;
    // Her zarda farklı emojiler: 12 kişi × 2 tur × 8 emoji = 192 > 150 ise başa döner, ama bir atışta yineleme olmaz.
    return {for (final i in p.a) kCards[i].emoji}.length >= p.m * 4;
  }

  @override
  Widget build(PartiPlay play) => StoryView(play: play);
}

class StoryView extends StatefulWidget {
  final PartiPlay play;
  const StoryView({super.key, required this.play});

  @override
  State<StoryView> createState() => _StoryViewState();
}

class _StoryViewState extends State<StoryView> with Clock {
  PSettings? s;
  int turn = 0;

  /// 0 zar at, 1 anlat, 2 puanla.
  int phase = 0;
  int shownDice = 0;
  List<int> scores = const [];
  int stars = 0;

  PartiPlay get p => widget.play;
  String t(String k, [Map<String, Object> a = const {}]) => p.t(k, a);

  int get turns => s!.count * p.deck.n;
  int get teller => turn % s!.count;
  List<int> get dice => [for (var k = 0; k < p.deck.m; k++) p.deck.a[(turn * p.deck.m + k) % p.deck.a.length]];

  void _roll() {
    setState(() {
      phase = 1;
      shownDice = 0;
    });
    for (var k = 0; k < p.deck.m; k++) {
      later(160 * (k + 1), () {
        p.sfx(Sfx.place);
        setState(() => shownDice = k + 1);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = s;
    if (v == null) {
      return Lobby(
        play: p,
        spec: const LobbySpec(minP: 1, maxP: 12, defP: 4, times: [60, 90, 120, 180], defTime: 90),
        emoji: '📖',
        onStart: (x) => setState(() {
          s = x;
          scores = List.filled(x.count, 0);
        }),
      );
    }
    final colors = [for (var i = 0; i < v.count; i++) PColors.player(i)];
    if (turn >= turns) return FinalBoard(play: p, names: v.names, scores: scores, colors: colors);
    final c = PColors.player(teller);
    final ds = dice;
    return Column(children: [
      PBar(left: v.names[teller], status: t('round', {'n': turn + 1, 'm': turns})),
      if (phase == 1 && shownDice >= ds.length)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Countdown(key: ValueKey('st$turn'), seconds: v.seconds, sfx: p.sfx, onEnd: () {
            if (mounted && phase == 1) setState(() => phase = 2);
          }),
        ),
      Expanded(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Text(phase == 0 ? t('yourTurnN', {'n': v.names[teller]}) : t('story'),
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
            for (var k = 0; k < ds.length; k++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 86,
                height: 86,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: k < shownDice ? PColors.paper : c.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: c, width: 3),
                ),
                child: Text(k < shownDice ? kCards[ds[k]].emoji : '?', style: const TextStyle(fontSize: 46)),
              ),
          ]),
          const SizedBox(height: 20),
          if (phase == 0) BigBtn(label: t('roll'), icon: Icons.casino, color: c, onTap: _roll),
          if (phase == 1 && shownDice >= ds.length)
            BigBtn(label: t('done'), icon: Icons.check, color: PColors.good, onTap: () => setState(() => phase = 2)),
          if (phase == 2) ...[
            Text(t('rate'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 18)),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var k = 1; k <= 3; k++)
                IconButton(
                  iconSize: 48,
                  tooltip: '$k',
                  onPressed: () => setState(() => stars = k),
                  icon: Icon(k <= stars ? Icons.star : Icons.star_border, color: PColors.warn),
                ),
            ]),
            BigBtn(
              label: t('next'),
              icon: Icons.arrow_forward,
              color: PColors.ink,
              onTap: () {
                p.sfx(Sfx.coin);
                setState(() {
                  scores[teller] += stars;
                  stars = 0;
                  turn++;
                  phase = 0;
                  shownDice = 0;
                });
              },
            ),
          ],
          const SizedBox(height: 16),
          ScoreList(names: v.names, scores: scores, colors: colors, highlight: teller),
        ]),
      ),
    ]);
  }
}

// ---------------------------------------------------------------- Hafıza Zinciri (özgün)

class ChainKind extends PartiKind {
  @override
  String get id => 'hafiza-zinciri';
  const ChainKind();

  @override
  PDeck? make(int d, SeededRandom r) {
    final m = 8 + d ~/ 3;
    final pool = [for (var i = 0; i < kCards.length; i++) if ('afnv'.contains(kCards[i].cat)) i];
    r.shuffle(pool);
    final pal = pool.take(m).toList();
    return PDeck(pal, b: [for (var i = 0; i < 60; i++) r.nextInt(m)], n: d < 5 ? 2 : 1, m: m);
  }

  @override
  bool check(PDeck p) =>
      p.m >= 8 &&
      p.m <= 11 &&
      p.a.length == p.m &&
      uniqIn(p.a, kCards.length) &&
      {for (final i in p.a) kCards[i].emoji}.length == p.m &&
      p.b.length == 60 &&
      p.b.every((x) => x >= 0 && x < p.m) &&
      (p.n == 1 || p.n == 2);

  @override
  Widget build(PartiPlay play) => ChainView(play: play);
}

class ChainView extends StatefulWidget {
  final PartiPlay play;
  const ChainView({super.key, required this.play});

  @override
  State<ChainView> createState() => _ChainViewState();
}

class _ChainViewState extends State<ChainView> with Clock {
  PSettings? s;
  final List<int> chain = [];
  int pos = 0;
  int cur = 0;
  List<int> lives = const [];
  List<int> added = const [];

  /// 0 telefonu ver, 1 tekrar et, 2 ekle, 3 izle (tek kişi), 4 bitti.
  int phase = 0;
  int? flash;
  int best = 0;

  PartiPlay get p => widget.play;
  String t(String k, [Map<String, Object> a = const {}]) => p.t(k, a);
  bool get solo => s!.count == 1;

  void _start(PSettings v) {
    setState(() {
      s = v;
      lives = List.filled(v.count, p.deck.n);
      added = List.filled(v.count, 0);
      chain.clear();
    });
    if (v.count == 1) {
      chain.add(p.deck.b[0]);
      _show();
    } else {
      setState(() => phase = 0);
    }
  }

  /// Tek kişide zincir sırayla yanıp söner.
  void _show() {
    setState(() {
      phase = 3;
      flash = null;
    });
    for (var k = 0; k < chain.length; k++) {
      later(300 + 650 * k, () {
        p.sfx(Sfx.tap);
        setState(() => flash = chain[k]);
      });
      later(300 + 650 * k + 450, () => setState(() => flash = null));
    }
    later(300 + 650 * chain.length, () => setState(() {
          phase = 1;
          pos = 0;
        }));
  }

  int _nextAlive(int from) {
    final v = s!;
    for (var k = 1; k <= v.count; k++) {
      final i = (from + k) % v.count;
      if (lives[i] > 0) return i;
    }
    return from;
  }

  int get aliveCount => lives.where((x) => x > 0).length;

  void _tap(int k) {
    final v = s!;
    if (phase == 2) {
      p.sfx(Sfx.place);
      setState(() {
        chain.add(k);
        added[cur]++;
        cur = _nextAlive(cur);
        phase = 0;
      });
      return;
    }
    if (phase != 1) return;
    if (chain.isEmpty) {
      // İlk oyuncu doğrudan ekler.
      setState(() => phase = 2);
      _tap(k);
      return;
    }
    if (chain[pos] == k) {
      p.sfx(Sfx.coin);
      setState(() => pos++);
      if (pos >= chain.length) {
        if (chain.length > best) best = chain.length;
        if (solo) {
          later(400, () {
            chain.add(p.deck.b[chain.length % 60]);
            _show();
          });
        } else {
          setState(() => phase = 2);
        }
      }
      return;
    }
    p.sfx(Sfx.error);
    setState(() {
      lives[cur]--;
      pos = 0;
      if (solo) {
        phase = lives[cur] > 0 ? 3 : 4;
      } else if (aliveCount <= 1) {
        phase = 4;
      } else {
        if (lives[cur] <= 0 || v.count > 1) cur = _nextAlive(cur);
        phase = 0;
      }
    });
    if (solo && lives[cur] > 0) later(600, _show);
  }

  @override
  Widget build(BuildContext context) {
    final v = s;
    if (v == null) {
      return Lobby(play: p, spec: const LobbySpec(minP: 1, maxP: 12, defP: 3), emoji: '🔗', onStart: _start);
    }
    final colors = [for (var i = 0; i < v.count; i++) PColors.player(i)];
    if (phase == 4) {
      final sc = solo ? [best] : [for (var i = 0; i < v.count; i++) added[i] + (lives[i] > 0 ? 3 : 0)];
      return FinalBoard(play: p, names: v.names, scores: sc, colors: colors, headline: solo ? t('chainBest', {'n': best}) : null);
    }
    if (phase == 0) {
      return Column(children: [
        PBar(status: t('chainLen', {'n': chain.length})),
        Expanded(
          child: PassGate(
            lang: p.lang,
            name: v.names[cur],
            color: PColors.player(cur),
            note: chain.isEmpty ? t('chainFirst') : t('repeatChain'),
            onReady: () => setState(() {
              phase = 1;
              pos = 0;
            }),
          ),
        ),
      ]);
    }
    final pal = p.deck.a;
    return Column(children: [
      PBar(
        left: solo ? '❤️ ${lives[0]}' : '${v.names[cur]} ${'❤️' * lives[cur]}',
        status: phase == 2 ? t('addOne') : (phase == 3 ? t('watch') : '${t('chainLen', {'n': chain.length})} · $pos/${chain.length}'),
      ),
      Expanded(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(alignment: WrapAlignment.center, spacing: 10, runSpacing: 10, children: [
              for (var k = 0; k < pal.length; k++)
                GestureDetector(
                  onTap: () => _tap(k),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 84,
                    height: 84,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: flash == k ? PColors.warn : PColors.paper,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: flash == k ? PColors.bad : PColors.line, width: flash == k ? 5 : 2),
                    ),
                    child: Text(kCards[pal[k]].emoji, style: const TextStyle(fontSize: 44)),
                  ),
                ),
            ]),
          ),
        ),
      ),
      if (!solo)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text([for (var i = 0; i < v.count; i++) '${v.names[i]} ${lives[i] > 0 ? '❤️' * lives[i] : '💤'}'].join('   '),
              textAlign: TextAlign.center),
        ),
    ]);
  }
}

// ---------------------------------------------------------------- Hızlı Parmak (özgün)

class ReflexKind extends PartiKind {
  @override
  String get id => 'hizli-parmak';
  const ReflexKind();

  @override
  PDeck? make(int d, SeededRandom r) {
    final pool = [for (var i = 0; i < kCards.length; i++) if ('afv'.contains(kCards[i].cat)) i];
    r.shuffle(pool);
    final target = pool[0];
    final decoys = pool.sublist(1, 7);
    final stream = <int>[];
    final delays = <int>[];
    var gap = r.range(2, 4);
    for (var k = 0; k < 120; k++) {
      if (gap == 0) {
        stream.add(target);
        gap = r.range(2, 5);
      } else {
        stream.add(r.pick(decoys));
        gap--;
      }
      delays.add(r.range(_floor450(950 - d * 40), 1500 - d * 50));
    }
    return PDeck(stream, b: delays, n: 4 + (d + 1) ~/ 3, m: target);
  }

  static int _floor450(int x) => x < 450 ? 450 : x;

  @override
  bool check(PDeck p) {
    if (p.a.length != 120 || p.b.length != 120 || p.n < 4 || p.n > 7) return false;
    if (p.m < 0 || p.m >= kCards.length || p.a.first == p.m) return false;
    for (var k = 1; k < p.a.length; k++) {
      if (p.a[k] == p.m && p.a[k - 1] == p.m) return false;
    }
    final targets = p.a.where((x) => x == p.m).length;
    final others = {for (final x in p.a) if (x != p.m) kCards[x].emoji};
    return targets >= 20 && !others.contains(kCards[p.m].emoji) && p.b.every((x) => x >= 400 && x <= 1500);
  }

  @override
  Widget build(PartiPlay play) => ReflexView(play: play);
}

class ReflexView extends StatefulWidget {
  final PartiPlay play;
  const ReflexView({super.key, required this.play});

  @override
  State<ReflexView> createState() => _ReflexViewState();
}

class _ReflexViewState extends State<ReflexView> {
  PSettings? s;
  bool running = false;
  int k = 0;
  Timer? _tm;
  List<int> scores = const [];
  int? claimed;
  int? early;
  final Stopwatch sw = Stopwatch();
  final List<int> times = [];
  bool over = false;

  PartiPlay get p => widget.play;
  String t(String key, [Map<String, Object> a = const {}]) => p.t(key, a);

  bool get solo => s!.count == 1;
  int get goal => solo ? 10 : p.deck.n;
  int get current => p.deck.a[k % p.deck.a.length];

  @override
  void dispose() {
    _tm?.cancel();
    super.dispose();
  }

  void _go() {
    setState(() {
      running = true;
      k = 0;
      claimed = null;
    });
    _schedule();
  }

  void _schedule() {
    _tm?.cancel();
    sw
      ..reset()
      ..start();
    _tm = Timer(Duration(milliseconds: p.deck.b[k % p.deck.b.length]), () {
      if (!mounted || over) return;
      setState(() {
        k++;
        claimed = null;
        early = null;
        if (solo && k >= 400) over = true;
      });
      if (!over) _schedule();
    });
  }

  void _hit(int i) {
    if (!running || over || claimed != null) return;
    if (current == p.deck.m) {
      p.sfx(Sfx.coin);
      setState(() {
        claimed = i;
        scores[i]++;
        times.add(sw.elapsedMilliseconds);
        if (scores[i] >= goal) {
          over = true;
          _tm?.cancel();
          p.sfx(Sfx.win);
        }
      });
    } else {
      p.sfx(Sfx.error);
      setState(() {
        early = i;
        if (scores[i] > 0) scores[i]--;
      });
    }
  }

  Widget _zone(int i) {
    final v = s!;
    final c = PColors.player(i);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _hit(i),
      child: Container(
        margin: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: claimed == i ? PColors.good : (early == i ? PColors.bad : c.withValues(alpha: 0.85)),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(v.names[i], style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
            Text('${scores[i]} / $goal', style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900)),
            if (early == i) Text(t('tooEarly'), style: const TextStyle(color: Colors.white, fontSize: 16)),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final v = s;
    if (v == null) {
      return Lobby(
        play: p,
        spec: const LobbySpec(minP: 1, maxP: 4, defP: 2),
        emoji: '⚡',
        onStart: (x) => setState(() {
          s = x;
          scores = List.filled(x.count, 0);
        }),
      );
    }
    final colors = [for (var i = 0; i < v.count; i++) PColors.player(i)];
    final target = kCards[p.deck.m].emoji;
    if (over) {
      final avg = times.isEmpty ? 0 : times.fold<int>(0, (a, b) => a + b) ~/ times.length;
      return FinalBoard(
        play: p,
        names: v.names,
        scores: scores,
        colors: colors,
        headline: solo ? t('reaction', {'n': avg}) : null,
      );
    }
    if (!running) {
      return ListView(padding: const EdgeInsets.all(24), children: [
        Center(child: Text(target, style: const TextStyle(fontSize: 110))),
        const SizedBox(height: 10),
        Text(t('tapWhen'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(t('firstTo', {'n': goal}), textAlign: TextAlign.center),
        const SizedBox(height: 24),
        BigBtn(label: t('start'), icon: Icons.bolt, color: PColors.bad, onTap: _go),
      ]);
    }
    final center = Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text('${t('target')}: $target', style: const TextStyle(fontSize: 16)),
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 120),
        child: Text(kCards[current].emoji, key: ValueKey(k), style: const TextStyle(fontSize: 120)),
      ),
    ]);
    return Zones(players: v.count, zone: _zone, center: center);
  }
}
