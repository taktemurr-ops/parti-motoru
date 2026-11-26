import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/strings.dart';

import '../core.dart';
import '../studio_chrome.dart';
import '../data/cards.dart';
import '../data/party2.dart';
import '../party.dart';

// ---------------------------------------------------------------- ortak

/// Sıradaki hâlâ oyunda olan oyuncu (kimse yoksa aynı kişi).
int nextAlive(List<int> lives, int from) {
  for (var k = 1; k <= lives.length; k++) {
    final i = (from + k) % lives.length;
    if (lives[i] > 0) return i;
  }
  return from;
}

/// Bir 33 dilli içerik listesinin destedeki sırayla, yaş paketine uyan metinleri.
List<String> dealLines(List<PLine> src, List<int> order, int age, String lang) {
  final out = [for (final i in order) if (src[i].tier <= age) Strings.pick(src[i].t, lang)];
  if (out.isEmpty) return [for (final i in order) Strings.pick(src[i].t, lang)];
  return out;
}

bool linesOk(List<PLine> src, {int minKids = 8}) {
  var kids = 0;
  for (final l in src) {
    if (l.t.length != 33 || l.tier < 0 || l.tier > 2) return false;
    for (final s in l.t) {
      if (s.trim().isEmpty) return false;
    }
    if (l.tier == 0) kids++;
  }
  return kids >= minKids;
}

// ---------------------------------------------------------------- Kelime Bombası

/// Kelime Bombası: kategoriye uyan kelimeyi söyle, telefonu elden ele geçir;
/// gizli fitil kimin elinde biterse o bir can kaybeder.
class BombKind extends PartiKind {
  @override
  String get id => 'bomba-kelime';
  const BombKind();

  static const fuses = 40;

  @override
  PDeck? make(int d, SeededRandom r) {
    final lo = d <= 3 ? 14 : 10;
    final hi = d <= 3 ? 34 : 28;
    final b = [
      for (var i = 0; i < fuses; i++) r.range(lo, hi),
      for (var i = 0; i < fuses; i++) r.nextInt(997),
    ];
    return PDeck(perm(kIsimCats.length, r), b: b, n: 3, m: d >= 4 ? 1 : 0);
  }

  @override
  bool check(PDeck p) {
    if (p.a.length != kIsimCats.length || !uniqIn(p.a, kIsimCats.length)) return false;
    if (p.b.length != 2 * fuses) return false;
    for (var i = 0; i < fuses; i++) {
      if (p.b[i] < 8 || p.b[i] > 40) return false;
      if (p.b[fuses + i] < 0) return false;
    }
    if (kAlphabets.length != 33 || kIsimCats.any((c) => c.length != 33)) return false;
    return p.n >= 1 && p.n <= 5 && (p.m == 0 || p.m == 1);
  }

  @override
  Widget build(PartiPlay play) => BombView(play: play);
}

class BombView extends StatefulWidget {
  final PartiPlay play;
  const BombView({super.key, required this.play});

  @override
  State<BombView> createState() => _BombViewState();
}

class _BombViewState extends State<BombView> {
  PSettings? s;
  List<int> lives = const [];
  List<int> scores = const [];
  int holder = 0;
  int round = 0;
  int passes = 0;

  /// 0 kart (fitil yanmadı), 1 fitil yanıyor, 2 patladı, 3 bitiş.
  int phase = 0;
  int elapsed = 0;
  int nextTick = 0;
  int lastBoom = -1;
  Timer? _timer;

  PartiPlay get p => widget.play;
  String t(String k, [Map<String, Object> a = const {}]) => p.t(k, a);

  int get fuseMs => p.deck.b[round % BombKind.fuses] * 1000;

  String get category => Strings.pick(kIsimCats[p.deck.a[round % p.deck.a.length]], p.lang);

  String? get letter {
    if (p.deck.m != 1) return null;
    final alpha = Strings.pick(kAlphabets, p.lang).split(' ').where((x) => x.isNotEmpty).toList();
    if (alpha.isEmpty) return null;
    return alpha[p.deck.b[BombKind.fuses + round % BombKind.fuses] % alpha.length];
  }

  int get aliveCount => lives.where((l) => l > 0).length;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _start(PSettings v) => setState(() {
        s = v;
        lives = List.filled(v.count, p.deck.n);
        scores = List.filled(v.count, 0);
        holder = (p.seed % v.count).abs();
      });

  void _light() {
    if (phase != 0) return;
    setState(() {
      phase = 1;
      elapsed = 0;
      nextTick = 0;
      passes = 0;
    });
    p.sfx(Sfx.unlock);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
  }

  void _tick() {
    if (!mounted || phase != 1) return;
    elapsed += 100;
    final f = clampD(elapsed / fuseMs, 0, 1);
    if (elapsed >= nextTick) {
      p.sfx(Sfx.tap);
      // Tıkırtı sona doğru hızlanır: 900 ms'den 180 ms'ye.
      nextTick = elapsed + (900 - 720 * f).round();
    }
    if (elapsed >= fuseMs) {
      _boom();
    } else {
      setState(() {});
    }
  }

  void _pass() {
    if (phase != 1) return;
    setState(() {
      holder = nextAlive(lives, holder);
      passes++;
    });
    p.sfx(Sfx.place);
  }

  void _boom() {
    _timer?.cancel();
    setState(() {
      lastBoom = holder;
      lives[holder] = math.max(0, lives[holder] - 1);
      for (var i = 0; i < lives.length; i++) {
        if (i != holder && lives[i] > 0) scores[i] += 1;
      }
      phase = 2;
    });
    p.sfx(Sfx.lose);
  }

  void _nextRound() {
    setState(() {
      if (aliveCount <= 1) {
        for (var i = 0; i < lives.length; i++) {
          if (lives[i] > 0) scores[i] += 2;
        }
        phase = 3;
        p.sfx(Sfx.win);
        return;
      }
      round++;
      if (lives[holder] <= 0) holder = nextAlive(lives, holder);
      phase = 0;
    });
  }

  Widget _hearts(int i) => Text(
        lives[i] <= 0 ? '💀' : List.filled(lives[i], '❤️').join(),
        style: const TextStyle(fontSize: 14),
      );

  Widget _roster() {
    final v = s!;
    return Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
      for (var i = 0; i < v.count; i++)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: PColors.player(i).withValues(alpha: i == holder && phase == 1 ? 0.45 : 0.18),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: i == holder && phase == 1 ? PColors.bad : Colors.transparent, width: 2),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(v.names[i], style: TextStyle(fontWeight: FontWeight.w700, color: lives[i] > 0 ? Colors.white : Colors.white54)),
            const SizedBox(width: 6),
            _hearts(i),
          ]),
        ),
    ]);
  }

  Widget _card() {
    final l = letter;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(18),
      decoration: partyCard(context, edge: PColors.bad),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(t('bombSay'), style: const TextStyle(fontSize: 15, color: kStudioSubtle)),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(category, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white)),
        ),
        if (l != null) ...[
          const SizedBox(height: 8),
          Text(t('startsWith', {'n': l}),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: kPartyWarnText)),
        ],
      ]),
    );
  }

  Widget _bomb() {
    final f = phase == 1 ? clampD(elapsed / fuseMs, 0, 1) : 0.0;
    // Fitil kısaldıkça bomba hafifçe titrer; ne zaman patlayacağı gizli kalır.
    final wob = phase == 1 ? math.sin(elapsed / 60) * (2 + 6 * f) : 0.0;
    return Transform.translate(
      offset: Offset(wob, 0),
      child: Text(phase == 2 ? '💥' : '💣', style: const TextStyle(fontSize: 96)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final v = s;
    if (v == null) {
      return Lobby(
        play: p,
        spec: const LobbySpec(minP: 2, maxP: 12, defP: 4),
        emoji: '💣',
        onStart: _start,
      );
    }
    final colors = [for (var i = 0; i < v.count; i++) PColors.player(i)];
    if (phase == 3) return FinalBoard(play: p, names: v.names, scores: scores, colors: colors);
    final status = '${t('roundN', {'n': round + 1})} · ${t('alive')}: $aliveCount';
    if (phase == 2) {
      return Column(children: [
        PBar(status: status),
        Expanded(
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Center(child: _bomb()),
            Text(t('boom', {'n': v.names[lastBoom < 0 ? holder : lastBoom]}),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: PColors.bad)),
            const SizedBox(height: 14),
            _roster(),
            const SizedBox(height: 14),
            ScoreList(names: v.names, scores: scores, colors: colors),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          child: BigBtn(label: t('next'), icon: Icons.arrow_forward, color: PColors.good, onTap: _nextRound),
        ),
      ]);
    }
    final hc = PColors.player(holder);
    return Column(children: [
      PBar(left: t('holder', {'n': v.names[holder]}), status: status),
      const SizedBox(height: 8),
      _card(),
      Expanded(
        child: Center(
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _bomb(),
              if (phase == 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: Text(t('bombNote'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 15)),
                ),
              const SizedBox(height: 10),
              _roster(),
            ]),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: phase == 0
            ? BigBtn(label: t('bombGo'), icon: Icons.local_fire_department, color: PColors.bad, onTap: _light)
            : BigBtn(label: t('bombPass'), icon: Icons.arrow_forward, color: hc, height: 92, onTap: _pass),
      ),
    ]);
  }
}

// ---------------------------------------------------------------- Beş Saniyede Üç

/// Beş Saniyede Üç: kart açılınca kısa sürede konuya uyan 3 şey say; masa karar verir.
class FiveKind extends PartiKind {
  @override
  String get id => 'bes-saniye';
  const FiveKind();

  @override
  PDeck? make(int d, SeededRandom r) => PDeck(perm(kFiveTopics.length, r), n: 2 + d ~/ 4);

  @override
  bool check(PDeck p) =>
      p.a.length == kFiveTopics.length &&
      uniqIn(p.a, kFiveTopics.length) &&
      p.n >= 1 &&
      p.n <= 6 &&
      linesOk(kFiveTopics, minKids: 12);

  @override
  Widget build(PartiPlay play) => FiveView(play: play);
}

class FiveView extends StatefulWidget {
  final PartiPlay play;
  const FiveView({super.key, required this.play});

  @override
  State<FiveView> createState() => _FiveViewState();
}

class _FiveViewState extends State<FiveView> {
  PSettings? s;
  List<String> topics = const [];
  List<int> scores = const [];
  int turn = 0;

  /// 0 telefonu ver, 1 kapalı kart, 2 süre işliyor, 3 masa karar verir, 4 bitiş.
  int phase = 0;

  PartiPlay get p => widget.play;
  String t(String k, [Map<String, Object> a = const {}]) => p.t(k, a);

  int get count => s!.count;
  int get player => turn % count;
  int get turns => count * p.deck.n;
  String get topic => topics[turn % topics.length];

  void _start(PSettings v) => setState(() {
        s = v;
        final deck = dealLines(kFiveTopics, p.deck.a, v.age, p.lang);
        if (v.custom.isEmpty) {
          topics = deck;
        } else {
          // Kendi konular desteye her iki kartta bir karışır.
          final mixed = <String>[];
          for (var i = 0; i < math.max(deck.length, v.custom.length); i++) {
            if (i < v.custom.length) mixed.add(v.custom[(i + p.seed) % v.custom.length]);
            if (i < deck.length) mixed.add(deck[i]);
          }
          topics = mixed;
        }
        scores = List.filled(v.count, 0);
      });

  void _judge(bool ok) {
    setState(() {
      if (ok) scores[player] += 1;
      turn++;
      phase = turn >= turns ? 4 : 0;
    });
    p.sfx(ok ? Sfx.coin : Sfx.error);
  }

  @override
  Widget build(BuildContext context) {
    final v = s;
    if (v == null) {
      return Lobby(
        play: p,
        spec: const LobbySpec(minP: 2, maxP: 12, defP: 4, times: [5, 7, 10], defTime: 5, age: true, custom: true),
        emoji: '⏱️',
        onStart: _start,
      );
    }
    final colors = [for (var i = 0; i < v.count; i++) PColors.player(i)];
    if (phase == 4) return FinalBoard(play: p, names: v.names, scores: scores, colors: colors);
    final secs = v.seconds <= 0 ? 5 : v.seconds;
    final pc = PColors.player(player);
    final status = '${t('round', {'n': turn ~/ count + 1, 'm': p.deck.n})} · ${v.names[player]} ${scores[player]}';
    if (phase == 0) {
      return Column(children: [
        PBar(status: status),
        Expanded(
          child: PassGate(
            lang: p.lang,
            name: v.names[player],
            color: pc,
            note: t('fiveNote'),
            onReady: () => setState(() => phase = 1),
          ),
        ),
      ]);
    }
    final card = Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 26),
      decoration: phase == 1
          ? BoxDecoration(color: pc, borderRadius: BorderRadius.circular(24), border: Border.all(color: pc, width: 3))
          : partyCard(context, edge: pc, radius: 24),
      child: phase == 1
          ? const Center(child: Text('❓', style: TextStyle(fontSize: 72)))
          : Column(mainAxisSize: MainAxisSize.min, children: [
              Text(t('fiveSay', {'n': secs}),
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(topic,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: Colors.white)),
              ),
              const SizedBox(height: 10),
              const Text('1 · 2 · 3', style: TextStyle(fontSize: 22, color: kStudioSubtle)),
            ]),
    );
    return Column(children: [
      PBar(left: v.names[player], status: status),
      if (phase == 2)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          child: Countdown(
            key: ValueKey('five$turn'),
            seconds: secs,
            sfx: p.sfx,
            onEnd: () {
              if (mounted && phase == 2) setState(() => phase = 3);
            },
          ),
        ),
      Expanded(child: Center(child: SingleChildScrollView(child: card))),
      if (phase == 3)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(t('fiveJudge'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: switch (phase) {
          1 => BigBtn(
              label: t('showCard'),
              icon: Icons.visibility,
              color: pc,
              onTap: () {
                setState(() => phase = 2);
                p.sfx(Sfx.unlock);
              },
            ),
          2 => BigBtn(label: t('done'), icon: Icons.check, color: PColors.good, onTap: () => setState(() => phase = 3)),
          _ => Row(children: [
              Expanded(child: BigBtn(label: t('missed'), icon: Icons.close, color: PColors.bad, onTap: () => _judge(false))),
              const SizedBox(width: 8),
              Expanded(child: BigBtn(label: t('correct'), icon: Icons.check, color: PColors.good, onTap: () => _judge(true))),
            ]),
        },
      ),
    ]);
  }
}

// ---------------------------------------------------------------- Kim En Çok?

/// Kim En Çok?: aile dostu soru, herkes sırayla gizlice oy verir; çoğunluğu
/// tahmin edenler puan alır, en çok oy alan taç kazanır.
class MostKind extends PartiKind {
  @override
  String get id => 'kim-en-cok';
  const MostKind();

  @override
  PDeck? make(int d, SeededRandom r) => PDeck(perm(kMostLikely.length, r), n: 4 + d ~/ 2);

  @override
  bool check(PDeck p) =>
      p.a.length == kMostLikely.length && uniqIn(p.a, kMostLikely.length) && p.n >= 3 && p.n <= 10 && linesOk(kMostLikely);

  @override
  Widget build(PartiPlay play) => MostView(play: play);
}

class MostView extends StatefulWidget {
  final PartiPlay play;
  const MostView({super.key, required this.play});

  @override
  State<MostView> createState() => _MostViewState();
}

class _MostViewState extends State<MostView> {
  PSettings? s;
  List<String> qs = const [];
  List<int> scores = const [];
  List<int> crowns = const [];
  List<int> votes = [];
  int round = 0;
  int voter = 0;

  /// 0 soru okunur, 1 telefonu ver, 2 oy ver, 3 oyları göster, 4 sonuç, 5 bitiş.
  int phase = 0;

  PartiPlay get p => widget.play;
  String t(String k, [Map<String, Object> a = const {}]) => p.t(k, a);

  String get question => qs[round % qs.length];

  void _start(PSettings v) => setState(() {
        s = v;
        qs = dealLines(kMostLikely, p.deck.a, v.age, p.lang);
        scores = List.filled(v.count, 0);
        crowns = List.filled(v.count, 0);
      });

  List<int> get tally {
    final n = List.filled(s!.count, 0);
    for (final x in votes) {
      if (x >= 0 && x < n.length) n[x]++;
    }
    return n;
  }

  void _vote(int who) {
    setState(() {
      votes.add(who);
      voter++;
      phase = voter >= s!.count ? 3 : 1;
    });
    p.sfx(Sfx.place);
  }

  void _reveal() {
    setState(() {
      final n = tally;
      final best = n.fold<int>(0, math.max);
      for (var i = 0; i < n.length; i++) {
        if (n[i] == best && best > 0) crowns[i]++;
      }
      for (var v = 0; v < votes.length; v++) {
        if (n[votes[v]] == best) scores[v] += 1;
      }
      phase = 4;
    });
    p.sfx(Sfx.win);
  }

  void _next() => setState(() {
        round++;
        voter = 0;
        votes = [];
        phase = round >= p.deck.n ? 5 : 0;
      });

  Widget _question() => Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        padding: const EdgeInsets.all(18),
        decoration: partyCard(context, edge: PColors.warn),
        child: Text(question,
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white)),
      );

  @override
  Widget build(BuildContext context) {
    final v = s;
    if (v == null) {
      return Lobby(
        play: p,
        spec: const LobbySpec(minP: 3, maxP: 12, defP: 4, age: true),
        emoji: '🗳️',
        onStart: _start,
      );
    }
    final colors = [for (var i = 0; i < v.count; i++) PColors.player(i)];
    if (phase == 5) return FinalBoard(play: p, names: v.names, scores: scores, colors: colors);
    final status = t('round', {'n': round + 1, 'm': p.deck.n});
    switch (phase) {
      case 0:
        return Column(children: [
          PBar(status: status),
          const SizedBox(height: 12),
          const Text('🗳️', style: TextStyle(fontSize: 56)),
          _question(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(t('mostRead'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 15)),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: BigBtn(label: t('vote'), icon: Icons.how_to_vote, color: PColors.warn, onTap: () => setState(() => phase = 1)),
          ),
        ]);
      case 1:
        return Column(children: [
          PBar(status: '$status · ${voter + 1}/${v.count}'),
          Expanded(
            child: PassGate(
              lang: p.lang,
              name: v.names[voter],
              color: PColors.player(voter),
              note: t('secretNote'),
              onReady: () => setState(() => phase = 2),
            ),
          ),
        ]);
      case 2:
        return Column(children: [
          PBar(left: v.names[voter], status: '$status · ${voter + 1}/${v.count}'),
          _question(),
          Text(t('mostVote'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
          Expanded(
            child: GridView.count(
              crossAxisCount: v.count <= 4 ? 2 : 3,
              padding: const EdgeInsets.all(12),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.6,
              children: [
                for (var i = 0; i < v.count; i++)
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: PColors.player(i),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    ),
                    onPressed: () => _vote(i),
                    child: Text(v.names[i],
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  ),
              ],
            ),
          ),
        ]);
      case 3:
        return Column(children: [
          PBar(status: status),
          const Spacer(),
          const Text('🥁', style: TextStyle(fontSize: 72)),
          _question(),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: BigBtn(label: t('showVotes'), icon: Icons.bar_chart, color: PColors.warn, onTap: _reveal),
          ),
        ]);
    }
    final n = tally;
    final best = n.fold<int>(0, math.max);
    final order = [for (var i = 0; i < v.count; i++) i]..sort((a, b) => n[b].compareTo(n[a]));
    return Column(children: [
      PBar(status: status),
      Expanded(
        child: ListView(padding: const EdgeInsets.all(12), children: [
          _question(),
          for (final i in order)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                SizedBox(
                  width: 110,
                  child: Text('${n[i] == best && best > 0 ? '👑 ' : ''}${v.names[i]}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: v.count == 0 ? 0 : n[i] / v.count,
                      minHeight: 18,
                      color: PColors.player(i),
                      backgroundColor: PColors.player(i).withValues(alpha: 0.15),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(t('votesN', {'n': n[i]})),
              ]),
            ),
          const SizedBox(height: 10),
          Text(t('crowdPt'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ScoreList(names: [for (var i = 0; i < v.count; i++) '${v.names[i]}${crowns[i] > 0 ? '  👑×${crowns[i]}' : ''}'], scores: scores, colors: colors),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: BigBtn(label: t('next'), icon: Icons.arrow_forward, color: PColors.good, onTap: _next),
      ),
    ]);
  }
}
