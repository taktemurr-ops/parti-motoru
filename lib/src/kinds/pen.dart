import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/rng.dart';

import '../core.dart';
import '../studio_chrome.dart';
import '../data/spectra.dart';
import '../party.dart';
import 'talk.dart' show emojiDeck, emojiDeckOk;

// ---------------------------------------------------------------- Kırık Kalem

const _penCats = {'a', 'f', 'o', 'v', 'n', 's'};

/// Kırık Kalem: çiz → tahmin et → çiz zinciri. Herkes yalnızca bir önceki adımı görür;
/// sonunda zincir baştan sona canlandırılarak gösterilir.
class BrokenPenKind extends PartiKind {
  @override
  String get id => 'kirik-kalem';
  const BrokenPenKind();

  @override
  PDeck? make(int d, SeededRandom r) => emojiDeck(r, d, _penCats);

  @override
  bool check(PDeck p) => emojiDeckOk(p, _penCats);

  @override
  Widget build(PartiPlay play) => BrokenPenView(play: play);
}

class PenStroke {
  final Color color;
  final double width;
  final List<Offset> pts = [];
  PenStroke(this.color, this.width);
}

/// Zincirin bir adımı: çizim ya da yazılı tahmin.
class PenStep {
  final int author;
  final List<PenStroke>? drawing;
  final String? text;
  const PenStep.draw(this.author, List<PenStroke> this.drawing) : text = null;
  const PenStep.guess(this.author, String this.text) : drawing = null;
  bool get isDraw => drawing != null;
}

/// Çizimi [frac] oranında (0..1) çizer: canlandırma için noktalar sırayla belirir.
void paintPen(Canvas c, List<PenStroke> strokes, double frac) {
  c.drawRRect(RRect.fromLTRBR(0, 0, 1000, 1000, const Radius.circular(36)), fill(Colors.white));
  var total = 0;
  for (final st in strokes) {
    total += st.pts.length;
  }
  var budget = (total * clampD(frac, 0, 1)).ceil();
  for (final st in strokes) {
    if (budget <= 0) break;
    final n = math.min<int>(budget, st.pts.length);
    budget -= n;
    if (n == 1) {
      c.drawCircle(st.pts.first, st.width / 2, fill(st.color));
      continue;
    }
    final path = Path()..moveTo(st.pts.first.dx, st.pts.first.dy);
    for (var i = 1; i < n; i++) {
      path.lineTo(st.pts[i].dx, st.pts[i].dy);
    }
    c.drawPath(path, stroke(st.color, st.width));
  }
}

/// Bir çizimi baştan sona oynatan küçük tuval.
class PenReplay extends StatelessWidget {
  final List<PenStroke> strokes;
  final int replayKey;
  const PenReplay({super.key, required this.strokes, this.replayKey = 0});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(replayKey),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 1800),
      builder: (context, f, _) => TapCanvas(w: 1000, h: 1000, paint: (c) => paintPen(c, strokes, f)),
    );
  }
}

class BrokenPenView extends StatefulWidget {
  final PartiPlay play;
  const BrokenPenView({super.key, required this.play});

  @override
  State<BrokenPenView> createState() => _BrokenPenViewState();
}

class _BrokenPenViewState extends State<BrokenPenView> {
  PSettings? s;
  List<PlayCard> cards = const [];
  int chains = 1;
  int chain = 0;
  int step = 0;

  /// 0 telefonu ver, 1 adımı yap, 2 zinciri göster, 3 sonuç.
  int phase = 0;
  List<int> scores = const [];
  final List<PenStep> steps = [];
  final List<PenStroke> strokes = [];
  int color = 0;
  double width = 12;
  int shown = 0;
  int replay = 0;
  int? fav;
  final TextEditingController guess = TextEditingController();

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

  int get count => s!.count;
  int get author => (chain + step) % count;
  bool get drawStep => step.isEven;
  PlayCard get prompt => cards[chain % cards.length];

  @override
  void dispose() {
    guess.dispose();
    super.dispose();
  }

  void _start(PSettings v) => setState(() {
        s = v;
        cards = dealCards(p, v, p.deck.a, withCat: false);
        // Uzun beklemeyi önlemek için toplam adım ~36 ile sınırlı.
        chains = clampI(p.deck.n, 1, math.max<int>(1, 36 ~/ v.count));
        scores = List.filled(v.count, 0);
      });

  void _submit() {
    if (phase != 1) return;
    setState(() {
      if (drawStep) {
        steps.add(PenStep.draw(author, [for (final st in strokes) st]));
        strokes.clear();
      } else {
        final g = guess.text.trim();
        steps.add(PenStep.guess(author, g.isEmpty ? '…' : (g.length > 40 ? g.substring(0, 40) : g)));
        guess.clear();
      }
      p.sfx(Sfx.place);
      step++;
      if (step >= count) {
        phase = 2;
        shown = 1;
        fav = null;
        p.sfx(Sfx.unlock);
      } else {
        phase = 0;
      }
    });
  }

  String _norm(String x) => x.trim().toLowerCase();

  bool get _held {
    final last = steps.lastWhere((e) => !e.isDraw, orElse: () => const PenStep.guess(0, ''));
    return last.text != null && _norm(last.text!) == _norm(prompt.label);
  }

  void _nextChain() {
    setState(() {
      final f = fav;
      if (f != null) scores[steps[f].author] += 2;
      if (_held) {
        for (var i = 0; i < scores.length; i++) {
          scores[i] += 1;
        }
      }
      p.sfx(Sfx.coin);
      steps.clear();
      chain++;
      step = 0;
      phase = chain >= chains ? 3 : 0;
    });
  }

  Offset _clip(Offset o) => Offset(clampD(o.dx, 0, 1000), clampD(o.dy, 0, 1000));

  Widget _timer() {
    final v = s!;
    if (v.seconds <= 0) return const SizedBox(height: 4);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Countdown(
        key: ValueKey('pen$chain-$step'),
        seconds: v.seconds,
        sfx: p.sfx,
        onEnd: _submit,
      ),
    );
  }

  Widget _drawScreen(String status, Color pc) {
    final v = s!;
    final seen = step == 0 ? prompt.label : (steps.last.text ?? '');
    return Column(children: [
      PBar(left: v.names[author], status: status),
      _timer(),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: partyCard(context, edge: pc, radius: 16, width: 2),
          child: Row(children: [
            if (step == 0 && prompt.emoji.isNotEmpty) Text(prompt.emoji, style: const TextStyle(fontSize: 30)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t('drawThis'), style: const TextStyle(fontSize: 13, color: kStudioSubtle)),
                Text(seen,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
              ]),
            ),
          ]),
        ),
      ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: TapCanvas(
            w: 1000,
            h: 1000,
            paint: (c) => paintPen(c, strokes, 1),
            onPanStart: (o) => setState(() => strokes.add(PenStroke(palette[color], color == palette.length - 1 ? width * 3 : width)..pts.add(_clip(o)))),
            onPanUpdate: (o) => setState(() {
              if (strokes.isNotEmpty) strokes.last.pts.add(_clip(o));
            }),
            onTap: (o) => setState(() => strokes.add(PenStroke(palette[color], width)..pts.add(_clip(o)))),
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
          for (final w in const [6.0, 12.0, 20.0, 32.0])
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
        child: BigBtn(label: t('done'), icon: Icons.check, color: PColors.good, onTap: strokes.isEmpty ? null : _submit),
      ),
    ]);
  }

  Widget _guessScreen(String status) {
    final v = s!;
    final prev = steps.last.drawing ?? const <PenStroke>[];
    return Column(children: [
      PBar(left: v.names[author], status: status),
      _timer(),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: Text(t('guessDraw'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
      ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: TapCanvas(w: 1000, h: 1000, paint: (c) => paintPen(c, prev, 1)),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: TextField(
          controller: guess,
          maxLength: 40,
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) {
            if (guess.text.trim().isNotEmpty) _submit();
          },
          decoration: InputDecoration(
            hintText: t('typeGuess'),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: BigBtn(label: t('done'), icon: Icons.check, color: PColors.good, onTap: guess.text.trim().isEmpty ? null : _submit),
      ),
    ]);
  }

  Widget _reveal(String status) {
    final v = s!;
    final f = fav;
    return Column(children: [
      PBar(status: status),
      Expanded(
        child: ListView(padding: const EdgeInsets.all(14), children: [
          CardFace(emoji: prompt.emoji, label: prompt.label, sub: t('startWord')),
          const SizedBox(height: 10),
          for (var i = 0; i < shown && i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Container(
                decoration: BoxDecoration(
                  color: PColors.player(steps[i].author).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: f == i ? PColors.warn : PColors.player(steps[i].author), width: f == i ? 4 : 2),
                ),
                padding: const EdgeInsets.all(10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    CircleAvatar(radius: 10, backgroundColor: PColors.player(steps[i].author)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(v.names[steps[i].author], style: const TextStyle(fontWeight: FontWeight.w800))),
                    IconButton(
                      tooltip: t('pickFav'),
                      onPressed: () => setState(() => fav = f == i ? null : i),
                      icon: Icon(f == i ? Icons.star : Icons.star_border, color: PColors.warn, size: 30),
                    ),
                  ]),
                  if (steps[i].isDraw)
                    AspectRatio(
                      aspectRatio: 1,
                      child: PenReplay(strokes: steps[i].drawing!, replayKey: replay * 100 + i),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text('“${steps[i].text}”',
                          textAlign: TextAlign.center, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
                    ),
                ]),
              ),
            ),
          if (shown >= steps.length) ...[
            const SizedBox(height: 8),
            if (_held)
              Center(child: Text(t('sameEnd'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: PColors.good))),
            Center(child: Text(t('pickFav'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 16))),
            TextButton.icon(
              onPressed: () => setState(() => replay++),
              icon: const Icon(Icons.replay),
              label: Text(t('replay')),
            ),
          ],
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: shown < steps.length
            ? BigBtn(
                label: t('next'),
                icon: Icons.arrow_downward,
                color: PColors.player(steps[shown].author),
                onTap: () => setState(() {
                  shown++;
                  p.sfx(Sfx.tap);
                }),
              )
            : BigBtn(label: t('next'), icon: Icons.arrow_forward, color: PColors.good, onTap: _nextChain),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final v = s;
    if (v == null) {
      return Lobby(
        play: p,
        spec: const LobbySpec(minP: 3, maxP: 12, defP: 4, teams: 0, times: [0, 30, 45, 60, 90], defTime: 60, age: true, custom: true),
        emoji: '🖊️',
        onStart: _start,
      );
    }
    final colors = [for (var i = 0; i < v.count; i++) PColors.player(i)];
    if (phase == 3) return FinalBoard(play: p, names: v.names, scores: scores, colors: colors);
    final status = '${t('chainN', {'n': chain + 1, 'm': chains})} · ${step + 1}/${v.count}';
    if (phase == 2) return _reveal(t('chainN', {'n': chain + 1, 'm': chains}));
    final pc = PColors.player(author);
    if (phase == 0) {
      return Column(children: [
        PBar(status: status),
        Expanded(
          child: PassGate(
            lang: p.lang,
            name: v.names[author],
            color: pc,
            note: step == 0 ? t('drawThis') : t('kkNote'),
            onReady: () => setState(() => phase = 1),
          ),
        ),
      ]);
    }
    return drawStep ? _drawScreen(status, pc) : _guessScreen(status);
  }
}

// ---------------------------------------------------------------- Isı Ölçer

/// Isı Ölçer: gizli hedef iki zıt kavram arasındaki bir ölçekte durur; ipucu veren
/// tek bir ipucu söyler, takım iğneyi çevirir. Yaklaştıkça puan artar.
class HeatDialKind extends PartiKind {
  @override
  String get id => 'isi-olcer';
  const HeatDialKind();

  @override
  PDeck? make(int d, SeededRandom r) {
    final a = perm(kSpectra.length, r);
    final b = [for (var i = 0; i < 40; i++) r.range(6, 94)];
    return PDeck(a, b: b, n: 3 + d ~/ 4);
  }

  @override
  bool check(PDeck p) {
    if (p.a.length != kSpectra.length || !uniqIn(p.a, kSpectra.length)) return false;
    if (p.b.length < 20) return false;
    for (final x in p.b) {
      if (x < 6 || x > 94) return false;
    }
    var kids = 0;
    for (final sp in kSpectra) {
      if (sp.l.length != 33 || sp.r.length != 33) return false;
      for (var k = 0; k < 33; k++) {
        if (sp.l[k].isEmpty || sp.r[k].isEmpty || sp.l[k] == sp.r[k]) return false;
      }
      if (sp.tier == 0) kids++;
    }
    return kids >= 20 && p.n >= 3 && p.n <= 5;
  }

  @override
  Widget build(PartiPlay play) => HeatDialView(play: play);
}

/// Hedefe uzaklığa göre puan: ±3 → 3, ±9 → 2, ±15 → 1.
int dialPoints(int target, int needle) {
  final d = (target - needle).abs();
  if (d <= 3) return 3;
  if (d <= 9) return 2;
  if (d <= 15) return 1;
  return 0;
}

class HeatDialView extends StatefulWidget {
  final PartiPlay play;
  const HeatDialView({super.key, required this.play});

  @override
  State<HeatDialView> createState() => _HeatDialViewState();
}

class _HeatDialViewState extends State<HeatDialView> {
  PSettings? s;
  List<PSpectrum> cards = const [];
  int ci = 0;
  int round = 0;

  /// 0 telefonu ver, 1 ipucu veren hedefi görür, 2 takım çevirir, 3 karşı takım, 4 sonuç, 5 bitiş.
  int phase = 0;
  List<int> scores = const [0, 0];
  int needle = 50;
  int? side;
  int last = 0;
  bool newCardUsed = false;

  PartiPlay get p => widget.play;
  String t(String k, [Map<String, Object> a = const {}]) => p.t(k, a);

  int get rounds => 2 * p.deck.n;
  int get team => round % 2;
  int get target => p.deck.b[round % p.deck.b.length];
  PSpectrum get card => cards[ci % cards.length];

  int get giver {
    final m = s!.members(team);
    return m[(round ~/ 2) % m.length];
  }

  void _start(PSettings v) => setState(() {
        s = v;
        cards = [for (final i in p.deck.a) if (kSpectra[i].tier <= v.age) kSpectra[i]];
        if (cards.isEmpty) cards = [for (final i in p.deck.a) kSpectra[i]];
      });

  void _score() {
    setState(() {
      final pts = dialPoints(target, needle);
      last = pts;
      scores[team] += pts;
      final sd = side;
      if (pts < 3 && sd != null && target != needle) {
        final right = target > needle;
        if ((sd == 1) == right) scores[1 - team] += 1;
      }
      p.sfx(pts >= 2 ? Sfx.win : (pts == 1 ? Sfx.coin : Sfx.lose));
      phase = 4;
    });
  }

  void _next() => setState(() {
        round++;
        ci++;
        needle = 50;
        side = null;
        newCardUsed = false;
        phase = round >= rounds ? 5 : 0;
      });

  static const _cx = 500.0, _cy = 560.0, _rad = 430.0;

  double _ang(int v) => math.pi - v / 100 * math.pi;

  Offset _at(int v, double r) => Offset(_cx + r * math.cos(_ang(v)), _cy - r * math.sin(_ang(v)));

  void _drag(Offset o) {
    final dx = o.dx - _cx, dy = _cy - o.dy;
    var a = math.atan2(dy, dx);
    if (a < 0) a = dx < 0 ? math.pi : 0;
    final v = ((math.pi - a) / math.pi * 100).round();
    final nv = clampI(v, 0, 100);
    if (nv != needle) setState(() => needle = nv);
  }

  void _paint(Canvas c, {required bool showTarget, required bool showNeedle}) {
    // Isı şeridi: soğuk maviden sıcak mercana.
    const steps = 50;
    for (var i = 0; i < steps; i++) {
      final a0 = math.pi - i / steps * math.pi;
      final a1 = math.pi - (i + 1) / steps * math.pi;
      final col = Color.lerp(const Color(0xFF3B86A8), const Color(0xFFE0735A), i / (steps - 1))!;
      final path = Path()
        ..moveTo(_cx, _cy)
        ..lineTo(_cx + _rad * math.cos(a0), _cy - _rad * math.sin(a0))
        ..arcTo(Rect.fromCircle(center: const Offset(_cx, _cy), radius: _rad), -a0, a0 - a1, false)
        ..close();
      c.drawPath(path, fill(col.withValues(alpha: 0.35)));
    }
    if (showTarget) {
      const bands = [(15, 1, Color(0xFFF2D49B)), (9, 2, Color(0xFFE9A866)), (3, 3, Color(0xFFC8553D))];
      for (final (w, pts, col) in bands) {
        final lo = clampI(target - w, 0, 100), hi = clampI(target + w, 0, 100);
        final a0 = _ang(lo), a1 = _ang(hi);
        final path = Path()
          ..moveTo(_cx, _cy)
          ..lineTo(_cx + _rad * math.cos(a0), _cy - _rad * math.sin(a0))
          ..arcTo(Rect.fromCircle(center: const Offset(_cx, _cy), radius: _rad), -a0, a0 - a1, false)
          ..close();
        c.drawPath(path, fill(col));
        final mid = _at(target, _rad - 40 - (3 - pts) * 50);
        drawLabel(c, '$pts', mid, 34, Colors.white);
      }
    }
    c.drawArc(Rect.fromCircle(center: const Offset(_cx, _cy), radius: _rad), math.pi, math.pi, false, stroke(PColors.ink, 8));
    c.drawLine(const Offset(_cx - _rad, _cy), const Offset(_cx + _rad, _cy), stroke(PColors.ink, 8));
    if (showNeedle) {
      final tip = _at(needle, _rad - 20);
      c.drawLine(const Offset(_cx, _cy), tip, stroke(PColors.ink, 14));
      c.drawCircle(tip, 16, fill(PColors.warn));
      c.drawCircle(const Offset(_cx, _cy), 30, fill(PColors.ink));
    }
  }

  Widget _ends() {
    final c = card;
    Widget end(String s, Color col, TextAlign al) => Expanded(
          child: Text(s,
              textAlign: al,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: col)),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(children: [
        end('← ${c.left(p.lang)}', const Color(0xFF2F6D8A), TextAlign.start),
        const SizedBox(width: 10),
        end('${c.right(p.lang)} →', const Color(0xFFB5513B), TextAlign.end),
      ]),
    );
  }

  Widget _dial({required bool target, required bool needleOn, bool drag = false}) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: TapCanvas(
            w: 1000,
            h: 600,
            paint: (c) => _paint(c, showTarget: target, showNeedle: needleOn),
            onTap: drag ? _drag : null,
            onPanStart: drag ? _drag : null,
            onPanUpdate: drag ? _drag : null,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final v = s;
    if (v == null) {
      return Lobby(
        play: p,
        spec: const LobbySpec(minP: 4, maxP: 12, defP: 4, teams: 2, age: true),
        emoji: '🌡️',
        onStart: _start,
      );
    }
    final names = [t('team', {'n': 'A'}), t('team', {'n': 'B'})];
    if (phase == 5) return FinalBoard(play: p, names: names, scores: scores, colors: PColors.teams);
    final tc = PColors.teams[team];
    final status = '${t('round', {'n': round + 1, 'm': rounds})} · ${names[0]} ${scores[0]} – ${scores[1]} ${names[1]}';
    if (phase == 0) {
      return Column(children: [
        PBar(status: status),
        Expanded(
          child: PassGate(
            lang: p.lang,
            name: v.names[giver],
            color: tc,
            note: t('dialGiver'),
            onReady: () => setState(() => phase = 1),
          ),
        ),
      ]);
    }
    if (phase == 1) {
      return Column(children: [
        PBar(left: v.names[giver], status: status),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(t('dialGiver'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
        ),
        _ends(),
        _dial(target: true, needleOn: false),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          child: Row(children: [
            if (!newCardUsed)
              Expanded(
                child: BigBtn(
                  label: t('newCard'),
                  icon: Icons.refresh,
                  color: PColors.line,
                  onTap: () => setState(() {
                    newCardUsed = true;
                    ci++;
                  }),
                ),
              ),
            if (!newCardUsed) const SizedBox(width: 8),
            Expanded(child: BigBtn(label: t('hide'), icon: Icons.visibility_off, color: tc, onTap: () => setState(() => phase = 2))),
          ]),
        ),
      ]);
    }
    if (phase == 2) {
      return Column(children: [
        PBar(left: t('cluer', {'n': v.names[giver]}), status: status),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(t('dialTurn'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        ),
        _ends(),
        _dial(target: false, needleOn: true, drag: true),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          child: BigBtn(label: t('lockIn'), icon: Icons.lock, color: tc, onTap: () => setState(() => phase = 3)),
        ),
      ]);
    }
    if (phase == 3) {
      return Column(children: [
        PBar(status: status),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Text(t('sideQ', {'n': teamLetter(1 - team)}),
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        ),
        _ends(),
        _dial(target: false, needleOn: true),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          child: Row(children: [
            Expanded(
              child: BigBtn(
                label: t('leftSide'),
                icon: Icons.arrow_back,
                color: PColors.teams[1 - team],
                onTap: () {
                  side = 0;
                  _score();
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: BigBtn(
                label: t('rightSide'),
                icon: Icons.arrow_forward,
                color: PColors.teams[1 - team],
                onTap: () {
                  side = 1;
                  _score();
                },
              ),
            ),
          ]),
        ),
      ]);
    }
    return Column(children: [
      PBar(status: status),
      Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(t('gotPts', {'n': last}),
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: last > 0 ? PColors.good : PColors.bad)),
      ),
      _ends(),
      _dial(target: true, needleOn: true),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: BigBtn(label: t('next'), icon: Icons.arrow_forward, color: PColors.good, onTap: _next),
      ),
    ]);
  }
}
