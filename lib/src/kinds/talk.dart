import 'package:flutter/material.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/strings.dart';

import '../core.dart';
import '../data/cards.dart';
import '../party.dart';

// ---------------------------------------------------------------- anlatım turları

/// Kart turları: Yasaklı Kelime, Sessiz Sinema ve Ben Kimim aynı akışı paylaşır.
enum TurnMode { tabu, mime, forehead }

/// Kategorilere göre uygun kart sırası (deste: [n] tur sayısı).
PDeck emojiDeck(SeededRandom r, int d, Set<String> cats, {int take = 90}) {
  final pool = [for (var i = 0; i < kCards.length; i++) if (cats.contains(kCards[i].cat)) i];
  r.shuffle(pool);
  final a = pool.take(take).toList();
  return PDeck(a, n: 1 + d ~/ 5);
}

bool emojiDeckOk(PDeck p, Set<String> cats) {
  if (p.a.length < 30 || !uniqIn(p.a, kCards.length)) return false;
  if (p.n < 1 || p.n > 3) return false;
  var kids = 0;
  for (final i in p.a) {
    if (!cats.contains(kCards[i].cat)) return false;
    if (kCards[i].tier == 0) kids++;
  }
  return kids >= 12;
}

class TabuKind extends PartiKind {
  @override
  String get id => 'yasakli-kelime';
  const TabuKind();

  @override
  PDeck? make(int d, SeededRandom r) {
    final a = perm(kTabuTr.length, r);
    return PDeck(a, n: 1 + d ~/ 4);
  }

  @override
  bool check(PDeck p) {
    if (kTabu.length != Strings.languages.length) return false;
    if (p.a.length != kTabuTr.length || !uniqIn(p.a, kTabuTr.length)) return false;
    for (final deck in kTabu) {
      if (deck.length != kTabuTr.length) return false;
    }
    for (final i in p.a) {
      final c = kTabuTr[i];
      for (final deck in kTabu) {
        final e = deck[i];
        if (e.no.length != 4 || e.tier != c.tier || e.emoji != c.emoji || e.word.isEmpty) return false;
        // Yasaklı sözcükler kartın kendisi olamaz ve birbirini yinelemez.
        if (e.no.contains(e.word) || e.no.toSet().length != 4) return false;
      }
    }
    return p.n >= 1 && p.n <= 3;
  }

  @override
  Widget build(PartiPlay play) => CardTurns(play: play, mode: TurnMode.tabu);
}

const _mimeCats = {'a', 'j', 's', 'x', 'v', 'o', 'f'};

class MimeKind extends PartiKind {
  @override
  String get id => 'sessiz-sinema';
  const MimeKind();

  @override
  PDeck? make(int d, SeededRandom r) => emojiDeck(r, d, _mimeCats);

  @override
  bool check(PDeck p) => emojiDeckOk(p, _mimeCats);

  @override
  Widget build(PartiPlay play) => CardTurns(play: play, mode: TurnMode.mime);
}

const _foreheadCats = {'a', 'j', 'f', 'v', 'o', 's', 'n'};

class ForeheadKind extends PartiKind {
  @override
  String get id => 'ben-kimim';
  const ForeheadKind();

  @override
  PDeck? make(int d, SeededRandom r) => emojiDeck(r, d, _foreheadCats);

  @override
  bool check(PDeck p) => emojiDeckOk(p, _foreheadCats);

  @override
  Widget build(PartiPlay play) => CardTurns(play: play, mode: TurnMode.forehead);
}

class CardTurns extends StatefulWidget {
  final PartiPlay play;
  final TurnMode mode;
  const CardTurns({super.key, required this.play, required this.mode});

  @override
  State<CardTurns> createState() => _CardTurnsState();
}

class _CardTurnsState extends State<CardTurns> {
  PSettings? s;
  List<PlayCard> cards = const [];
  int ci = 0;
  int turn = 0;

  /// 0 telefonu ver, 1 oyun, 2 tur özeti, 3 sonuç.
  int phase = 0;
  List<int> scores = const [];
  int ok = 0, passes = 0, fouls = 0;

  PartiPlay get p => widget.play;
  String t(String k, [Map<String, Object> a = const {}]) => p.t(k, a);

  int get passLimit => widget.mode == TurnMode.tabu ? 3 : 2;

  LobbySpec get spec => switch (widget.mode) {
        TurnMode.tabu => const LobbySpec(minP: 4, maxP: 12, defP: 4, teams: 2, times: [45, 60, 90, 120], defTime: 60, age: true, custom: true),
        TurnMode.mime => const LobbySpec(minP: 2, maxP: 12, defP: 4, teams: 1, times: [45, 60, 90, 120], defTime: 60, age: true, custom: true),
        TurnMode.forehead => const LobbySpec(minP: 2, maxP: 12, defP: 3, teams: 0, times: [45, 60, 90], defTime: 60, age: true, custom: true),
      };

  String get emoji => switch (widget.mode) { TurnMode.tabu => '🤐', TurnMode.mime => '🎭', TurnMode.forehead => '🤔' };

  void _start(PSettings v) {
    final List<PlayCard> deal;
    if (widget.mode == TurnMode.tabu) {
      final src = langItem(kTabu, p.lang);
      final base = [
        for (final i in p.deck.a)
          if (src[i].tier <= v.age) PlayCard(src[i].emoji, src[i].word, forbidden: src[i].no)
      ];
      deal = [
        for (var i = 0; i < base.length; i++) ...[
          if (v.custom.isNotEmpty && i.isOdd) PlayCard('✍️', v.custom[(i ~/ 2) % v.custom.length]),
          base[i],
        ]
      ];
    } else {
      deal = dealCards(p, v, p.deck.a);
    }
    setState(() {
      s = v;
      cards = deal;
      scores = List.filled(v.teams ? 2 : v.count, 0);
      phase = 0;
    });
  }

  int get turns => s!.teams ? 2 * p.deck.n * ((s!.count + 1) ~/ 2) : s!.count * p.deck.n;

  int get teller {
    final v = s!;
    if (!v.teams) return turn % v.count;
    final team = turn % 2;
    final m = v.members(team);
    return m[(turn ~/ 2) % m.length];
  }

  /// Puanı alan satır: takım ya da oyuncu.
  int get scorer => s!.teams ? turn % 2 : teller;

  PlayCard get card => cards[ci % cards.length];

  void _next() => setState(() => ci++);

  void _hit() {
    p.sfx(Sfx.coin);
    setState(() {
      ok++;
      scores[scorer]++;
      ci++;
    });
  }

  void _pass() {
    if (passes >= passLimit) return;
    p.sfx(Sfx.tap);
    setState(() => passes++);
    _next();
  }

  void _foul() {
    p.sfx(Sfx.error);
    setState(() {
      fouls++;
      scores[scorer]--;
      ci++;
    });
  }

  void _endTurn() {
    if (phase != 1) return;
    setState(() => phase = 2);
  }

  void _afterSummary() {
    setState(() {
      turn++;
      ok = passes = fouls = 0;
      phase = turn >= turns ? 3 : 0;
    });
  }

  List<String> get rowNames => s!.teams ? [t('team', {'n': 'A'}), t('team', {'n': 'B'})] : s!.names;

  List<Color> get rowColors =>
      s!.teams ? PColors.teams : [for (var i = 0; i < s!.count; i++) PColors.player(i)];

  @override
  Widget build(BuildContext context) {
    final v = s;
    if (v == null) return Lobby(play: p, spec: spec, emoji: emoji, onStart: _start);
    if (phase == 3) return FinalBoard(play: p, names: rowNames, scores: scores, colors: rowColors);
    final who = teller;
    final color = v.teams ? PColors.teams[turn % 2] : PColors.player(who);
    final status = t('round', {'n': turn + 1, 'm': turns});
    if (phase == 0) {
      final note = switch (widget.mode) {
        TurnMode.tabu => t('tellNote'),
        TurnMode.mime => t('act'),
        TurnMode.forehead => t('forehead'),
      };
      return Column(children: [
        PBar(left: v.teams ? t('team', {'n': teamLetter(turn % 2)}) : '', status: status),
        Expanded(child: PassGate(lang: p.lang, name: v.names[who], color: color, note: note, onReady: () => setState(() => phase = 1))),
      ]);
    }
    if (phase == 2) {
      return ListView(padding: const EdgeInsets.all(18), children: [
        Center(child: Text(t('timeUp'), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900))),
        const SizedBox(height: 8),
        Center(
          child: Text('✅ $ok   ⏭️ $passes${widget.mode == TurnMode.tabu ? '   ⛔ $fouls' : ''}',
              style: const TextStyle(fontSize: 22)),
        ),
        const SizedBox(height: 14),
        ScoreList(names: rowNames, scores: scores, colors: rowColors, highlight: scorer),
        const SizedBox(height: 16),
        BigBtn(label: t('next'), icon: Icons.arrow_forward, color: color, onTap: _afterSummary),
      ]);
    }
    final c = card;
    if (widget.mode == TurnMode.forehead) {
      // Telefon alında: sol yarı pas, sağ yarı bildim (görmeden dokunulur).
      return Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Countdown(key: ValueKey('cd$turn'), seconds: v.seconds, onEnd: _endTurn, sfx: p.sfx),
        ),
        Expanded(
          child: Stack(children: [
            Positioned.fill(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: CardFace(emoji: c.emoji, label: c.label, sub: c.sub, edge: color),
                ),
              ),
            ),
            Positioned.fill(
              child: Row(children: [
                Expanded(
                  child: Semantics(
                    button: true,
                    label: t('pass'),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        p.sfx(Sfx.tap);
                        _next();
                      },
                      child: const Align(
                        alignment: Alignment.bottomLeft,
                        child: Padding(padding: EdgeInsets.all(18), child: Text('⏭️', style: TextStyle(fontSize: 40))),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Semantics(
                    button: true,
                    label: t('gotIt'),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _hit,
                      child: const Align(
                        alignment: Alignment.bottomRight,
                        child: Padding(padding: EdgeInsets.all(18), child: Text('✅', style: TextStyle(fontSize: 40))),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text('${v.names[who]} · ✅ ${scores[scorer]}', style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      ]);
    }
    return Column(children: [
      PBar(left: v.names[who], status: status),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Countdown(key: ValueKey('cd$turn'), seconds: v.seconds, onEnd: _endTurn, sfx: p.sfx),
      ),
      Expanded(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: CardFace(
              emoji: c.emoji,
              label: c.label,
              sub: widget.mode == TurnMode.tabu ? t('forbidden') : c.sub,
              forbidden: c.forbidden,
              edge: color,
            ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
        child: Row(children: [
          Expanded(
            child: BigBtn(
              label: '${t('pass')} ${passLimit - passes}',
              icon: Icons.skip_next,
              color: PColors.line,
              onTap: passes < passLimit ? _pass : null,
            ),
          ),
          if (widget.mode == TurnMode.tabu) ...[
            const SizedBox(width: 8),
            Expanded(child: BigBtn(label: t('foul'), icon: Icons.block, color: PColors.bad, onTap: _foul)),
          ],
          const SizedBox(width: 8),
          Expanded(child: BigBtn(label: t('correct'), icon: Icons.check, color: PColors.good, onTap: _hit)),
        ]),
      ),
    ]);
  }
}

// ---------------------------------------------------------------- çiz ve tahmin et

const _drawCats = {'a', 'f', 'o', 'v', 'n', 's'};

class DrawKind extends PartiKind {
  @override
  String get id => 'ciz-tahmin';
  const DrawKind();

  @override
  PDeck? make(int d, SeededRandom r) => emojiDeck(r, d, _drawCats);

  @override
  bool check(PDeck p) => emojiDeckOk(p, _drawCats);

  @override
  Widget build(PartiPlay play) => DrawView(play: play);
}

class _Stroke {
  final Color color;
  final double width;
  final List<Offset> pts = [];
  _Stroke(this.color, this.width);
}

class DrawView extends StatefulWidget {
  final PartiPlay play;
  const DrawView({super.key, required this.play});

  @override
  State<DrawView> createState() => _DrawViewState();
}

class _DrawViewState extends State<DrawView> {
  PSettings? s;
  List<PlayCard> cards = const [];
  int ci = 0;
  int turn = 0;

  /// 0 telefonu ver, 1 kartı gör, 2 çiz, 3 kim bildi, 4 sonuç.
  int phase = 0;
  List<int> scores = const [];
  final List<_Stroke> strokes = [];
  int color = 0;
  double width = 10;
  bool skipped = false;

  static const palette = [
    Color(0xFF26313D),
    Color(0xFFC8553D),
    Color(0xFF3B86A8),
    Color(0xFF4F9A6E),
    Color(0xFFD9A441),
    Color(0xFF8A5BA6),
    Color(0xFFF7F2E8),
  ];

  PartiPlay get p => widget.play;
  String t(String k, [Map<String, Object> a = const {}]) => p.t(k, a);

  int get turns => s!.count * p.deck.n;
  int get drawer => turn % s!.count;
  PlayCard get card => cards[ci % cards.length];

  void _start(PSettings v) => setState(() {
        s = v;
        cards = dealCards(p, v, p.deck.a);
        scores = List.filled(v.teams ? 2 : v.count, 0);
      });

  void _guessed(int? who) {
    final v = s!;
    setState(() {
      if (who != null) {
        p.sfx(Sfx.coin);
        if (v.teams) {
          scores[v.teamOf(drawer)] += 1;
        } else {
          scores[drawer] += 1;
          scores[who] += 1;
        }
      }
      ci++;
      turn++;
      strokes.clear();
      skipped = false;
      phase = turn >= turns ? 4 : 0;
    });
  }

  void _paint(Canvas c) {
    c.drawRRect(RRect.fromLTRBR(0, 0, 1000, 1000, const Radius.circular(36)), fill(Colors.white));
    for (final st in strokes) {
      if (st.pts.length == 1) {
        c.drawCircle(st.pts.first, st.width / 2, fill(st.color));
        continue;
      }
      final path = Path()..moveTo(st.pts.first.dx, st.pts.first.dy);
      for (final q in st.pts.skip(1)) {
        path.lineTo(q.dx, q.dy);
      }
      c.drawPath(path, stroke(st.color, st.width));
    }
  }

  Offset _clip(Offset o) => Offset(clampD(o.dx, 0, 1000), clampD(o.dy, 0, 1000));

  @override
  Widget build(BuildContext context) {
    final v = s;
    if (v == null) {
      return Lobby(
        play: p,
        spec: const LobbySpec(minP: 2, maxP: 12, defP: 4, teams: 1, times: [45, 60, 90, 120], defTime: 60, age: true, custom: true),
        emoji: '🎨',
        onStart: _start,
      );
    }
    final names = v.teams ? [t('team', {'n': 'A'}), t('team', {'n': 'B'})] : v.names;
    final colors = v.teams ? PColors.teams : [for (var i = 0; i < v.count; i++) PColors.player(i)];
    if (phase == 4) return FinalBoard(play: p, names: names, scores: scores, colors: colors);
    final pc = v.teams ? PColors.teams[v.teamOf(drawer)] : PColors.player(drawer);
    final status = t('round', {'n': turn + 1, 'm': turns});
    if (phase == 0) {
      return Column(children: [
        PBar(status: status),
        Expanded(child: PassGate(lang: p.lang, name: v.names[drawer], color: pc, note: t('drawNote'), onReady: () => setState(() => phase = 1))),
      ]);
    }
    if (phase == 1) {
      final c = card;
      return Column(children: [
        PBar(left: v.names[drawer], status: status),
        Expanded(
          child: Center(
            child: Padding(padding: const EdgeInsets.all(20), child: CardFace(emoji: c.emoji, label: c.label, sub: c.sub, edge: pc)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Row(children: [
            if (!skipped)
              Expanded(
                child: BigBtn(
                  label: t('pass'),
                  icon: Icons.skip_next,
                  color: PColors.line,
                  onTap: () => setState(() {
                    skipped = true;
                    ci++;
                  }),
                ),
              ),
            if (!skipped) const SizedBox(width: 8),
            Expanded(
              child: BigBtn(label: t('draw'), icon: Icons.brush, color: pc, onTap: () => setState(() => phase = 2)),
            ),
          ]),
        ),
      ]);
    }
    if (phase == 3) {
      final c = card;
      return ListView(padding: const EdgeInsets.all(16), children: [
        CardFace(emoji: c.emoji, label: c.label, sub: c.sub, edge: pc),
        const SizedBox(height: 14),
        Text(t('guessedBy'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (var i = 0; i < v.count; i++)
            if (i != drawer && (!v.teams || v.teamOf(i) == v.teamOf(drawer)))
              ActionChip(
                avatar: CircleAvatar(backgroundColor: PColors.player(i)),
                label: Text(v.names[i]),
                onPressed: () => _guessed(i),
              ),
          ActionChip(avatar: const Text('🙈'), label: Text(t('nobody')), onPressed: () => _guessed(null)),
        ]),
      ]);
    }
    return Column(children: [
      PBar(left: v.names[drawer], status: status),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
        child: Countdown(
          key: ValueKey('draw$turn'),
          seconds: v.seconds,
          sfx: p.sfx,
          onEnd: () {
            if (mounted && phase == 2) setState(() => phase = 3);
          },
        ),
      ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: TapCanvas(
            w: 1000,
            h: 1000,
            paint: _paint,
            onPanStart: (o) => setState(() => strokes.add(_Stroke(palette[color], color == palette.length - 1 ? width * 3 : width)..pts.add(_clip(o)))),
            onPanUpdate: (o) => setState(() {
              if (strokes.isNotEmpty) strokes.last.pts.add(_clip(o));
            }),
            onTap: (o) => setState(() => strokes.add(_Stroke(palette[color], width)..pts.add(_clip(o)))),
          ),
        ),
      ),
      SizedBox(
        height: 52,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8), children: [
          for (var i = 0; i < palette.length; i++)
            GestureDetector(
              onTap: () => setState(() => color = i),
              child: Container(
                width: 40,
                height: 40,
                margin: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: palette[i],
                  shape: BoxShape.circle,
                  border: Border.all(color: i == color ? PColors.warn : PColors.line, width: i == color ? 4 : 1.5),
                ),
                child: i == palette.length - 1 ? const Icon(Icons.auto_fix_normal, size: 20) : null,
              ),
            ),
          for (final w in const [6.0, 10.0, 18.0, 30.0])
            IconButton(
              tooltip: '${w.round()}',
              onPressed: () => setState(() => width = w),
              icon: Icon(Icons.circle, size: 8 + w * 0.6, color: width == w ? PColors.warn : PColors.ink),
            ),
          IconButton(
            tooltip: t('undo'),
            onPressed: strokes.isEmpty ? null : () => setState(() => strokes.removeLast()),
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: t('clear'),
            onPressed: strokes.isEmpty ? null : () => setState(strokes.clear),
            icon: const Icon(Icons.delete_outline),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: BigBtn(label: t('gotIt'), icon: Icons.emoji_events, color: PColors.good, onTap: () => setState(() => phase = 3)),
      ),
    ]);
  }
}
