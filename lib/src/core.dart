import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/app/game_api.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/game_rules.dart';
import 'package:studio_core/core/level_plan.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/stats.dart';

import 'identity.dart';
import 'texts.dart';
import 'studio_chrome.dart';

/// Bir parti oyununun bölümü: tohumlanmış deste ve tur planı.
/// [a] ana liste (kart sırası, ızgara...), [b] yardımcı liste,
/// [n] ve [m] türün kendi anlamıyla kullandığı sayılar.
class PDeck {
  final List<int> a;
  final List<int> b;
  final int n;
  final int m;
  const PDeck(this.a, {this.b = const [], this.n = 0, this.m = 0});
}

class PLevel {
  final String kind;
  final int d;
  final PDeck deck;
  const PLevel(this.kind, this.d, this.deck);
}

/// Parti oyunu türü: desteyi üretir, denetler, ekranı kurar.
abstract class PartiKind {
  const PartiKind();
  String get id;

  /// Zorluk 1..10 için deterministik deste (kurulamazsa null).
  PDeck? make(int d, SeededRandom r);

  /// Destenin kurallara uyduğunu denetler.
  bool check(PDeck p);

  Widget build(PartiPlay play);

  List<GameStat> get stats => const [
        GameStat('games_played', 'Oynanan oyun', 'Games played', scale: 5),
        GameStat('points', 'Kazanılan puan', 'Points scored', scale: 25),
      ];

  List<MissionTemplate> get missions => const [
        MissionTemplate('play', 'games_played', [1, 5, 15]),
        MissionTemplate('points', 'points', [10, 50, 200]),
      ];
}

PDeck realizeParti(PartiKind k, int d, int seed) {
  for (var dd = d; dd >= 1; dd--) {
    for (var a = 0; a < 25; a++) {
      PDeck? p;
      try {
        p = k.make(dd, SeededRandom(mixSeed([seed, a, dd, 9091])));
      } catch (_) {
        p = null;
      }
      if (p != null && k.check(p)) return p;
    }
  }
  throw StateError('parti destesi kurulamadı: ${k.id} $d');
}

class PartiRules extends GameRules<PLevel> {
  @override
  final String gameId;
  final PartiKind kind;
  final int levels;
  PartiRules({required this.gameId, required this.kind, this.levels = 100000});

  @override
  int get levelCount => levels;

  @override
  List<String> get optionalMechanics => const [];

  @override
  List<GameModeId> get modes => const [GameModeId.campaign, GameModeId.daily];

  @override
  List<GameStat> get gameStats => kind.stats;

  @override
  List<MissionTemplate> get missionTemplates => kind.missions;

  @override
  PLevel generate(LevelSpec spec) {
    final d = clampI(spec.difficulty, 1, 10);
    return PLevel(kind.id, d, realizeParti(kind, d, spec.seed));
  }

  @override
  Validation validate(PLevel puzzle, LevelSpec spec) =>
      puzzle.kind == kind.id && kind.check(puzzle.deck) ? const Validation.ok() : const Validation.fail('invalid');
}

class PartiPlay {
  final PlayContext ctx;
  final PDeck deck;
  final int d;
  final int seed;
  const PartiPlay({required this.ctx, required this.deck, required this.d, required this.seed});

  String get lang => ctx.lang;

  void sfx(Sfx s) => ctx.sfx(s);

  String t(String key, [Map<String, Object> params = const {}]) => pt(lang, key, params);

  /// Varsayılan oyuncu adı (33 dilde, çekirdekten).
  String playerName(int i) => ctx.t('player_n', {'n': i + 1});

  /// Oyunu bitirir: en yüksek puanlı ad(lar) başlığa yazılır.
  void finishScores(List<String> names, List<int> scores, {String? headline, int stars = 3}) {
    var best = -1 << 30;
    for (final s in scores) {
      if (s > best) best = s;
    }
    final top = [for (var i = 0; i < scores.length; i++) if (scores[i] == best) names[i]];
    final h = headline ?? (scores.isEmpty ? null : (top.length == 1 ? t('wins', {'n': top.first}) : t('tie')));
    final total = scores.fold<int>(0, (a, b) => a + (b > 0 ? b : 0));
    ctx.finish(RoundResult(
      won: true,
      score: total,
      stars: clampI(stars, 1, 3),
      headline: h,
      gameStats: {'games_played': 1, 'points': best > 0 ? best : 0},
    ));
  }
}

/// Parti oyunlarının ortak sahnesi.
class PartiStage extends StatelessWidget {
  final PlayContext ctx;
  final PartiRules rules;
  const PartiStage({super.key, required this.ctx, required this.rules});

  /// Motorun bütün arayüzü (paneller, pencereler, düğmeler) onaylı koyu
  /// tasarımda; tahta çizimleri kendi renklerini korur.
  ///
  /// Oyun alanı oyuna özgüdür (zemin tonu, desen ve panel vurgusu): aynı
  /// motorun oyunları birbirinin kopyası gibi görünmez.
  @override
  Widget build(BuildContext context) =>
      withGameIdentity(context, rules.gameId, StudioChrome(child: Builder(builder: _build)));

  Widget _build(BuildContext context) {
    final lv = ctx.generated.puzzle as PLevel;
    return rules.kind.build(PartiPlay(ctx: ctx, deck: lv.deck, d: lv.d, seed: ctx.spec.seed));
  }
}

PartiRules partiRules(String gameId, PartiKind kind) => PartiRules(gameId: gameId, kind: kind);

// ---------------------------------------------------------------- ortak yardımcılar

int clampI(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);
double clampD(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

/// Listede yineleme yoksa ve hepsi [0, max) aralığındaysa true.
bool uniqIn(List<int> xs, int max) {
  if (xs.toSet().length != xs.length) return false;
  for (final x in xs) {
    if (x < 0 || x >= max) return false;
  }
  return true;
}

/// [0, n) karışık sıra.
List<int> perm(int n, SeededRandom r) {
  final l = [for (var i = 0; i < n; i++) i];
  r.shuffle(l);
  return l;
}

class PColors {
  static const paper = Color(0xFFF7F2E8);
  static const ink = Color(0xFF26313D);
  static const good = Color(0xFF4F9A6E);
  static const bad = Color(0xFFC8553D);
  static const warn = Color(0xFFD9A441);
  static const soft = Color(0xFFE9E2D3);
  static const line = Color(0xFFBDB29E);

  /// İki takım: mercan ve deniz mavisi.
  static const teams = [Color(0xFFE0735A), Color(0xFF3B86A8)];

  /// Oyuncu renkleri (12 kişiye kadar ayırt edilir).
  static const players = [
    Color(0xFFE0735A),
    Color(0xFF3B86A8),
    Color(0xFF6A9E4F),
    Color(0xFFD9A441),
    Color(0xFF8A5BA6),
    Color(0xFF2E9C93),
    Color(0xFFC2507A),
    Color(0xFF5C6FC4),
    Color(0xFFB0763B),
    Color(0xFF4D8C6B),
    Color(0xFF9E4B4B),
    Color(0xFF607489),
  ];

  static Color player(int i) => players[i % players.length];
}

/// Saniye sayacı ve iptal edilebilen gecikmeler.
mixin Clock<T extends StatefulWidget> on State<T> {
  int seconds = 0;
  Timer? _t;
  final List<Timer> _later = [];

  void startClock() {
    _t?.cancel();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => seconds++);
    });
  }

  void later(int ms, VoidCallback f) {
    _later.add(Timer(Duration(milliseconds: ms), () {
      if (mounted) f();
    }));
  }

  @override
  void dispose() {
    _t?.cancel();
    for (final t in _later) {
      t.cancel();
    }
    super.dispose();
  }
}

Paint fill(Color c) => Paint()
  ..color = c
  ..isAntiAlias = true;

Paint stroke(Color c, double w) => Paint()
  ..color = c
  ..style = PaintingStyle.stroke
  ..strokeWidth = w
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round
  ..isAntiAlias = true;

/// Ortalanmış kısa yazı (mantıksal birimlerle).
void drawLabel(Canvas c, String s, Offset center, double size, Color color, {FontWeight weight = FontWeight.w700}) {
  if (s.isEmpty) return;
  final tp = TextPainter(
    text: TextSpan(text: s, style: TextStyle(fontSize: size, color: color, fontWeight: weight, height: 1.0)),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
  )..layout();
  tp.paint(c, center - Offset(tp.width / 2, tp.height / 2));
}

/// Mantıksal birimlerle çizilen, dokunuşları aynı birimlere çeviren tuval.
class TapCanvas extends StatelessWidget {
  final double w;
  final double h;
  final void Function(Canvas c) paint;
  final void Function(Offset p)? onTap;
  final void Function(Offset p)? onPanStart;
  final void Function(Offset p)? onPanUpdate;
  final VoidCallback? onPanEnd;
  const TapCanvas({
    super.key,
    required this.w,
    required this.h,
    required this.paint,
    this.onTap,
    this.onPanStart,
    this.onPanUpdate,
    this.onPanEnd,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final mw = box.maxWidth.isFinite ? box.maxWidth : 360.0;
      final mh = box.maxHeight.isFinite ? box.maxHeight : 360.0;
      final k = math.min(mw / w, mh / h);
      final size = Size(w * k, h * k);
      Offset lp(Offset o) => o / k;
      final ps = onPanStart, pu = onPanUpdate, pe = onPanEnd, t = onTap;
      return Center(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: t == null ? null : (e) => t(lp(e.localPosition)),
          onPanStart: ps == null ? null : (e) => ps(lp(e.localPosition)),
          onPanUpdate: pu == null ? null : (e) => pu(lp(e.localPosition)),
          onPanEnd: pe == null ? null : (_) => pe(),
          child: CustomPaint(size: size, painter: _FnPainter(paint, k)),
        ),
      );
    });
  }
}

class _FnPainter extends CustomPainter {
  final void Function(Canvas c) fn;
  final double k;
  _FnPainter(this.fn, this.k);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(k);
    fn(canvas);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FnPainter old) => true;
}
