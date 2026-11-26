/// 4. tur Parti ve Aile türleri: Köşe Kapışması (2-4 kişilik 20 mini oyun),
/// Hangisini Seçerdin? (gizli seçim + çoğunluk tahmini), Tek İpucu (ortak
/// tahmin, aynı ipuçları silinir) ve İki Doğru Bir Yalan (yalnız numara seçilir).
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/rng.dart';

import '../core.dart';
import '../data/cards.dart';
import '../data/party2.dart';
import '../party.dart';
import '../studio_chrome.dart';
import 'hot.dart' show dealLines, linesOk;

// ================================================================ Köşe Kapışması

/// Ortak tetik: herkes aynı anı bekler, ilk doğru dokunan kazanır.
const Set<int> kMgReact = {0, 7, 9, 10, 13, 17, 19};

/// Kişiye özel tetik: her adımda bir oyuncunun anı; doğru +1, yanlış -1.
const Set<int> kMgScore = {2, 11, 15, 16};

/// Hızlı dokunma oyunları.
const Set<int> kMgMash = {1, 4, 5, 14};

/// Zamanlama: herkes bir kez dokunur, hedef ana en yakın kazanır.
const Set<int> kMgTiming = {3, 6, 12, 18};

const int kMgCount = 20;

const List<String> _mgEmoji = ['🍎', '🐸', '🚀', '🎈', '🦊', '🍩', '⚽', '🌵', '🐙', '🎸', '🍉', '🦄'];
const List<IconData> _mgShapes = [
  Icons.star_rounded,
  Icons.favorite_rounded,
  Icons.circle,
  Icons.square_rounded,
  Icons.change_history_rounded,
  Icons.hexagon_rounded,
  Icons.cloud_rounded,
  Icons.bolt_rounded,
];
const List<String> _mgSymbols = ['♠', '♣', '♥', '♦', '☀', '☂', '♫', '✿', '☾', '✈'];
const List<String> _dice = ['⚀', '⚁', '⚂', '⚃', '⚄', '⚅'];

/// Köşe yönleri (orta kareye göre): 2 kişi üst/alt, 3 kişi iki üst bir alt, 4 kişi dört köşe.
List<Offset> cornerDirs(int n) => switch (n) {
      2 => const [Offset(0, -1), Offset(0, 1)],
      3 => const [Offset(-1, -1), Offset(1, -1), Offset(0, 1)],
      _ => const [Offset(-1, -1), Offset(1, -1), Offset(-1, 1), Offset(1, 1)],
    };

/// Bir mini oyun turunun deterministik uyaran dizisi.
class MgStep {
  /// Adımın uyaranı (oyuna göre: renk sırası, emoji, şekil, toplam...).
  final int v;
  final int w;
  final int x;

  /// Ortak tetik oyunlarında bu adımda dokunmak doğru mu.
  final bool go;

  /// Kişiye özel oyunlarda adımın sahibi.
  final int owner;
  const MgStep(this.v, {this.w = 0, this.x = 0, this.go = false, this.owner = -1});
}

/// Turun planı: adımlar, adım süresi ve oyuna özel değerler.
class MgPlan {
  final int game;
  final List<MgStep> steps;
  final int stepMs;

  /// Hedef (emoji / şekil / simge) ya da balon sınırları, bomba fitili...
  final int target;
  final List<int> limits;
  final int firstHolder;
  const MgPlan(this.game, this.steps, this.stepMs, {this.target = 0, this.limits = const [], this.firstHolder = 0});
}

MgPlan mgPlan(int game, int players, int d, int seed) {
  final r = SeededRandom(mixSeed([seed, game, players, 4407]));
  final stepMs = 1150 - clampI(d, 1, 10) * 45;
  final steps = <MgStep>[];
  var target = 0;
  if (kMgReact.contains(game)) {
    final goAt = r.range(3, 8);
    target = r.nextInt(game == 10 ? _mgShapes.length : (game == 17 ? _mgSymbols.length : _mgEmoji.length));
    for (var i = 0; i < 11; i++) {
      final go = i == goAt;
      switch (game) {
        case 0:
          steps.add(MgStep(go ? 1 : 0, go: go));
        case 7:
        case 10:
        case 17:
          final n = game == 10 ? _mgShapes.length : (game == 17 ? _mgSymbols.length : _mgEmoji.length);
          var v = go ? target : r.nextInt(n);
          if (!go && v == target) v = (v + 1 + r.nextInt(n - 1)) % n;
          steps.add(MgStep(v, go: go));
        case 9:
          final a = r.range(1, 9), b = r.range(1, 9);
          var c = a + b;
          if (!go) c += r.nextInt(2) == 0 ? -r.range(1, 3) : r.range(1, 3);
          steps.add(MgStep(a, w: b, x: c, go: go));
        case 13:
          // v: 0 sarı yıldız, 1-4 başka renk yıldız, 5 sarı daire.
          steps.add(MgStep(go ? 0 : r.range(1, 5), go: go));
        default:
          // 19: iki zar.
          final a = r.nextInt(6);
          var b = go ? a : r.nextInt(6);
          if (!go && b == a) b = (a + 1 + r.nextInt(5)) % 6;
          steps.add(MgStep(a, w: b, go: go));
      }
    }
    if (game == 17) {
      // İlk adım hatırlanacak simge (dokunulmaz); hedef ilk kez tetikte döner.
      steps.insert(0, MgStep(target));
      for (var i = 1; i < steps.length; i++) {
        if (!steps[i].go && steps[i].v == target) steps[i] = MgStep((target + 1) % _mgSymbols.length);
      }
    }
  } else if (kMgScore.contains(game)) {
    var last = -1;
    for (var i = 0; i < 10; i++) {
      var o = r.nextInt(players);
      if (o == last) o = (o + 1) % players;
      last = o;
      // 11 ve 15'te bazen kimsenin olmayan adım (ortada boşluk / yukarı ok): -1.
      final none = (game == 11 || game == 15 || game == 16) && r.nextInt(5) == 0;
      steps.add(MgStep(r.nextInt(9), owner: none ? -1 : o));
    }
  }
  final limits = <int>[];
  var holder = 0;
  if (game == 4) {
    for (var i = 0; i < players; i++) {
      limits.add(r.range(14, 32));
    }
  } else if (game == 16) {
    final nums = [for (var i = 1; i <= 9; i++) i];
    r.shuffle(nums);
    limits.addAll(nums.take(players));
  } else if (game == 8) {
    limits.add(r.range(4000, 9000));
    holder = r.nextInt(players);
  } else if (game == 12) {
    limits.add(r.range(560, 820));
  }
  return MgPlan(game, steps, stepMs, target: target, limits: limits, firstHolder: holder);
}

/// Planın kurallara uyup uymadığı (testler ve deste denetimi).
bool mgPlanOk(MgPlan p, int players) {
  if (kMgReact.contains(p.game)) {
    final gos = [for (var i = 0; i < p.steps.length; i++) if (p.steps[i].go) i];
    if (gos.length != 1) return false;
    for (final s in p.steps) {
      if (p.game == 9 && s.go != (s.v + s.w == s.x)) return false;
      if (p.game == 19 && s.go != (s.v == s.w)) return false;
      if ((p.game == 7 || p.game == 10) && s.go != (s.v == p.target)) return false;
    }
    if (p.game == 17 && p.steps.first.v != p.target) return false;
  }
  if (kMgScore.contains(p.game)) {
    if (p.steps.length < 6) return false;
    for (final s in p.steps) {
      if (s.owner >= players) return false;
    }
  }
  if (p.game == 4 && p.limits.length != players) return false;
  if (p.game == 16 && p.limits.toSet().length != players) return false;
  return p.stepMs >= 600;
}

class CornerKind extends PartiKind {
  @override
  String get id => 'mini-oyunlar';
  const CornerKind();

  @override
  PDeck? make(int d, SeededRandom r) => PDeck(perm(kMgCount, r), n: 6 + d ~/ 3);

  @override
  bool check(PDeck p) {
    if (p.a.length != kMgCount || !uniqIn(p.a, kMgCount)) return false;
    if (p.n < 6 || p.n > 10) return false;
    for (var k = 0; k < p.n; k++) {
      for (var players = 2; players <= 4; players++) {
        if (!mgPlanOk(mgPlan(p.a[k % kMgCount], players, 5, k * 31 + players), players)) return false;
      }
    }
    return true;
  }

  @override
  Widget build(PartiPlay play) => CornerView(play: play);
}

class CornerView extends StatefulWidget {
  final PartiPlay play;
  const CornerView({super.key, required this.play});

  @override
  State<CornerView> createState() => _CornerViewState();
}

class _CornerViewState extends State<CornerView> {
  PSettings? s;
  int round = 0;

  /// 0 tanıtım, 1 oyun, 2 tur sonucu, 3 bitiş.
  int phase = 0;
  List<int> scores = const [];
  late MgPlan plan;
  Timer? _tick;
  final Stopwatch _sw = Stopwatch();

  // Tur durumu.
  List<int> taps = const [];
  List<int?> tapMs = const [];
  List<bool> out = const [];
  List<int> gain = const [];
  List<int> stepScore = const [];
  int lastStepTapped = -1;
  Set<int> tappedThisStep = {};
  Offset ball = Offset.zero;
  int holder = 0;
  bool exploded = false;
  String note = '';

  static const _preMs = 900;

  PartiPlay get p => widget.play;
  String t(String k, [Map<String, Object> a = const {}]) => p.t(k, a);
  int get n => s?.count ?? 2;
  int get game => p.deck.a[round % kMgCount];
  int get rounds => p.deck.n;
  int get ms => _sw.elapsedMilliseconds - _preMs;

  int get stepIdx => ms < 0 ? -1 : ms ~/ plan.stepMs;
  MgStep? get step {
    final i = stepIdx;
    return i >= 0 && i < plan.steps.length ? plan.steps[i] : null;
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _start(PSettings v) => setState(() {
        s = v;
        scores = List.filled(v.count, 0);
        _intro();
      });

  void _intro() {
    plan = mgPlan(game, n, p.d, mixSeed([p.seed, round]));
    taps = List.filled(n, 0);
    tapMs = List.filled(n, null);
    out = List.filled(n, false);
    gain = List.filled(n, 0);
    stepScore = List.filled(n, 0);
    tappedThisStep = {};
    lastStepTapped = -1;
    ball = Offset.zero;
    holder = plan.firstHolder;
    exploded = false;
    note = '';
    phase = 0;
  }

  void _go() {
    setState(() => phase = 1);
    _sw
      ..reset()
      ..start();
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(milliseconds: 40), (_) => _frame());
  }

  int get _duration {
    final g = game;
    if (kMgReact.contains(g) || kMgScore.contains(g)) return plan.steps.length * plan.stepMs;
    return switch (g) {
      1 => 5000,
      4 => 6000,
      5 => 12000,
      14 => 15000,
      3 => 10 * plan.stepMs + 300,
      6 => 6000,
      12 => 5 * (plan.limits.isEmpty ? 700 : plan.limits.first) + 1000,
      18 => 5000,
      _ => plan.limits.isEmpty ? 6000 : plan.limits.first,
    };
  }

  void _frame() {
    if (!mounted || phase != 1) return;
    final m = ms;
    if (game == 8 && m >= _duration) {
      exploded = true;
      p.sfx(Sfx.lose);
      for (var i = 0; i < n; i++) {
        if (i != holder) gain[i] = 1;
      }
      _end();
      return;
    }
    if (m >= _duration) {
      _timeUp();
      return;
    }
    setState(() {});
  }

  void _timeUp() {
    final g = game;
    if (kMgReact.contains(g)) {
      note = t('nobody');
    } else if (kMgScore.contains(g)) {
      _bestOf(stepScore);
    } else if (g == 1) {
      _bestOf(taps);
    } else if (g == 4) {
      _bestOf([for (var i = 0; i < n; i++) out[i] ? 0 : taps[i]]);
    } else if (g == 5) {
      final dirs = cornerDirs(n);
      final d = [for (var i = 0; i < n; i++) -((ball - dirs[i]).distance * 1000).round()];
      _bestOf(d, allowZero: true);
    } else if (g == 14) {
      _bestOf(taps);
    } else if (kMgTiming.contains(g)) {
      final tgt = _timingTarget();
      final err = [for (var i = 0; i < n; i++) tapMs[i] == null ? null : (tapMs[i]! - tgt).abs()];
      var best = 1 << 30;
      for (final e in err) {
        if (e != null && e < best) best = e;
      }
      if (best <= 1200) {
        for (var i = 0; i < n; i++) {
          if (err[i] == best) gain[i] = 1;
        }
      } else {
        note = t('nobody');
      }
    }
    _end();
  }

  void _bestOf(List<int> xs, {bool allowZero = false}) {
    var best = -1 << 30;
    for (final x in xs) {
      if (x > best) best = x;
    }
    if (!allowZero && best <= 0) {
      note = t('nobody');
      return;
    }
    for (var i = 0; i < n; i++) {
      if (xs[i] == best) gain[i] = 1;
    }
  }

  int _timingTarget() => switch (game) {
        3 => 6 * plan.stepMs + plan.stepMs ~/ 2,
        6 => 3000,
        12 => 4 * (plan.limits.isEmpty ? 700 : plan.limits.first),
        _ => 3000,
      };

  void _end() {
    _tick?.cancel();
    _sw.stop();
    setState(() {
      for (var i = 0; i < n; i++) {
        scores[i] += gain[i];
      }
      if (gain.any((g) => g > 0)) p.sfx(Sfx.win);
      phase = 2;
    });
  }

  void _next() => setState(() {
        round++;
        if (round >= rounds) {
          phase = 3;
        } else {
          _intro();
        }
      });

  void _tap(int i) {
    if (phase != 1 || ms < 0) return;
    final g = game;
    final m = ms;
    if (kMgReact.contains(g)) {
      if (out[i]) return;
      final st = step;
      if (g == 17 && stepIdx == 0) return;
      if (st != null && st.go) {
        gain[i] = 1;
        p.sfx(Sfx.coin);
        _end();
        return;
      }
      setState(() => out[i] = true);
      p.sfx(Sfx.error);
      if (out.every((o) => o)) {
        note = t('tooEarly');
        _end();
      }
      return;
    }
    if (kMgScore.contains(g)) {
      final si = stepIdx;
      if (si != lastStepTapped) {
        tappedThisStep = {};
        lastStepTapped = si;
      }
      if (tappedThisStep.contains(i)) return;
      tappedThisStep.add(i);
      final st = step;
      setState(() => stepScore[i] += (st != null && st.owner == i) ? 1 : -1);
      p.sfx(st != null && st.owner == i ? Sfx.coin : Sfx.error);
      return;
    }
    switch (g) {
      case 1:
        setState(() => taps[i]++);
      case 4:
        if (out[i]) return;
        setState(() {
          taps[i]++;
          if (taps[i] >= plan.limits[i]) {
            out[i] = true;
            p.sfx(Sfx.lose);
          }
        });
      case 5:
        final dir = cornerDirs(n)[i];
        setState(() {
          final v = dir - ball;
          final len = v.distance;
          if (len > 0) ball += v / len * 0.07;
        });
        if ((ball - dir).distance < 0.25) {
          gain[i] = 1;
          _end();
        }
      case 14:
        setState(() => taps[i]++);
        if (taps[i] >= 30) {
          gain[i] = 1;
          _end();
        }
      case 8:
        if (i == holder) {
          setState(() => holder = (holder + 1) % n);
          p.sfx(Sfx.tap);
        }
      default:
        // Zamanlama oyunları: herkes bir kez.
        if (tapMs[i] != null) return;
        setState(() => tapMs[i] = m);
        p.sfx(Sfx.tap);
        if (tapMs.every((x) => x != null)) _timeUp();
    }
  }

  // ------------------------------------------------------------ çizim

  Widget _stim() {
    final g = game;
    final st = step;
    if (phase == 1 && ms < 0) {
      final k = 3 - ((ms + _preMs) * 3 ~/ _preMs);
      return Text('${clampI(k, 1, 3)}', style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w900));
    }
    if (phase != 1) return const SizedBox.shrink();
    Widget big(String s, {double size = 54, Color? color}) =>
        Text(s, style: TextStyle(fontSize: size, fontWeight: FontWeight.w900, color: color, height: 1.0));
    switch (g) {
      case 0:
        return big(st == null ? '' : (st.go ? '🟢' : '🟥'));
      case 7:
        return big(st == null ? '' : _mgEmoji[st.v]);
      case 9:
        return st == null ? const SizedBox.shrink() : big('${st.v}+${st.w}=${st.x}', size: 38);
      case 10:
        return st == null ? const SizedBox.shrink() : Icon(_mgShapes[st.v], size: 64, color: const Color(0xFFF2C14E));
      case 13:
        if (st == null) return const SizedBox.shrink();
        const cols = [Color(0xFFF2C94C), Color(0xFF5DADE2), Color(0xFFE56B6F), Color(0xFF6FCF97), Color(0xFFB388EB)];
        return Icon(st.v == 5 ? Icons.circle : Icons.star_rounded, size: 70, color: st.v == 5 ? cols[0] : cols[st.v % 5]);
      case 17:
        return big(st == null ? '' : _mgSymbols[st.v], color: Colors.white);
      case 19:
        return st == null ? const SizedBox.shrink() : big('${_dice[st.v]}${_dice[st.w]}', size: 58, color: Colors.white);
      case 2:
        if (st == null) return const SizedBox.shrink();
        final o = st.owner < 0 ? 0 : st.owner;
        final c = PColors.player(o);
        return CircleAvatar(
          radius: 34,
          backgroundColor: c,
          child: Text(_initial(s!.names[o]), style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: pOn(c))),
        );
      case 15:
        if (st == null) return const SizedBox.shrink();
        final dir = st.owner < 0 ? const Offset(0, 0) : cornerDirs(n)[st.owner];
        if (st.owner < 0) return const Icon(Icons.do_not_touch_rounded, size: 60, color: kStudioSubtle);
        return Transform.rotate(angle: math.atan2(dir.dy, dir.dx), child: const Icon(Icons.arrow_forward_rounded, size: 72, color: Colors.white));
      case 16:
        if (st == null) return const SizedBox.shrink();
        return big(st.owner < 0 ? '${_freeNumber(st.v)}' : '${plan.limits[st.owner]}', color: Colors.white);
      case 11:
        return const Icon(Icons.gps_fixed_rounded, size: 52, color: kStudioSubtle);
      case 5:
        return SizedBox(width: 120, height: 120, child: CustomPaint(painter: _TugPainter(ball, n)));
      case 3:
        final k = ms ~/ plan.stepMs + 1;
        return big('${clampI(k, 1, 10)}', color: Colors.white);
      case 6:
        return big(ms < 400 ? '3.0' : '⏳');
      case 12:
        final iv = plan.limits.first;
        final beat = ms ~/ iv;
        final on = beat < 4 && ms % iv < 180;
        return Icon(Icons.circle, size: 60, color: on ? const Color(0xFFF2C14E) : Colors.white24);
      case 18:
        final f = ms / 3000.0;
        return SizedBox(width: 120, height: 120, child: CustomPaint(painter: _RingPainter(f)));
      case 8:
        return big('💣');
      case 1:
      case 4:
      case 14:
        final left = ((_duration - ms) / 1000).ceil();
        return big('$left', color: Colors.white);
    }
    return const SizedBox.shrink();
  }

  int _freeNumber(int v) {
    // Kimsenin olmayan bir sayı.
    for (var k = 0; k < 9; k++) {
      final x = (v + k) % 9 + 1;
      if (!plan.limits.contains(x)) return x;
    }
    return 0;
  }

  String _initial(String name) => name.isEmpty ? '?' : String.fromCharCode(name.runes.first).toUpperCase();

  /// Oyuncunun köşesinde gösterilen kendi durumu.
  Widget _zoneInfo(int i) {
    final g = game;
    final st = step;
    const big = TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: Colors.white);
    if (phase == 2) {
      return Text(gain[i] > 0 ? '+1' : (exploded && i == holder ? '💥' : '·'), style: big);
    }
    if (phase == 0) {
      // Tanıtımda oyuna özel hedef.
      if (g == 7) return Text(_mgEmoji[plan.target], style: const TextStyle(fontSize: 40));
      if (g == 10) return Icon(_mgShapes[plan.target], size: 46, color: Colors.black87);
      if (g == 16) return Text('${plan.limits[i]}', style: big);
      if (g == 2) return CircleAvatar(radius: 16, backgroundColor: PColors.player(i));
      return const SizedBox.shrink();
    }
    if (out[i] && kMgReact.contains(g)) return Text('✋ ${t('tooEarly')}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, color: Colors.white));
    if (kMgScore.contains(g)) {
      final mine = st != null && st.owner == i && g == 11;
      return Column(mainAxisSize: MainAxisSize.min, children: [
        if (mine) const Icon(Icons.gps_fixed_rounded, size: 40, color: Color(0xFFF2C14E)),
        if (g == 16) Text('${plan.limits[i]}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white70)),
        Text('${stepScore[i]}', style: big),
      ]);
    }
    switch (g) {
      case 1:
        return Text('${taps[i]}', style: big);
      case 4:
        return Text(out[i] ? '💥' : '🎈', style: TextStyle(fontSize: 22.0 + taps[i] * 1.6));
      case 14:
        return SizedBox(
          width: 150,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('🏎️', style: TextStyle(fontSize: 26)),
            LinearProgressIndicator(value: taps[i] / 30, minHeight: 10, color: Colors.white, backgroundColor: Colors.white24),
          ]),
        );
      case 8:
        return Text(i == holder ? '💣' : '', style: const TextStyle(fontSize: 46));
      case 7:
        return Text(_mgEmoji[plan.target], style: const TextStyle(fontSize: 30));
      case 10:
        return Icon(_mgShapes[plan.target], size: 36, color: Colors.black87);
    }
    if (kMgTiming.contains(g)) return Text(tapMs[i] == null ? '👆' : '✔', style: big);
    return const SizedBox.shrink();
  }

  Widget _zone(int i) {
    final c = PColors.player(i);
    final name = s!.names[i];
    final hot = phase == 1 && game == 11 && step?.owner == i;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => _tap(i),
      child: Container(
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Color.lerp(c, Colors.black, 0.35),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: hot ? const Color(0xFFF2C14E) : c, width: hot ? 6 : 2),
        ),
        padding: const EdgeInsets.all(10),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('$name · ${scores[i]}',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
          if (phase == 0)
            Flexible(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(t('mg$game'),
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
          Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: _zoneInfo(i))),
        ]),
      ),
    );
  }

  Widget _center() {
    Widget mid;
    if (phase == 0) {
      mid = BigBtn(label: t('start'), icon: Icons.flag_rounded, color: PColors.good, onTap: _go, height: 56);
    } else if (phase == 2) {
      final winners = [for (var i = 0; i < n; i++) if (gain[i] > 0) s!.names[i]];
      final head = winners.isEmpty ? (note.isEmpty ? t('nobody') : note) : winners.join(', ');
      mid = Row(children: [
        Expanded(
          child: Text(head, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 8),
        Expanded(child: BigBtn(label: t('next'), icon: Icons.arrow_forward, color: PColors.good, onTap: _next, height: 56)),
      ]);
    } else {
      final st = _stim();
      // Karşıdaki oyuncular için uyaran ters çevrilmiş olarak da gösterilir
      // (yön bildiren ok ve çekişme haritası hariç).
      mid = (game == 5 || game == 15) ? st : Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        RotatedBox(quarterTurns: 2, child: FittedBox(fit: BoxFit.scaleDown, child: st)),
        FittedBox(fit: BoxFit.scaleDown, child: st),
      ]);
    }
    return Container(
      height: 112,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: partyCard(context, radius: 20, width: 2),
      child: Row(children: [
        Text('${round + 1}/$rounds', style: const TextStyle(fontSize: 13, color: kStudioSubtle)),
        const SizedBox(width: 8),
        Expanded(child: Center(child: mid)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final v = s;
    if (v == null) {
      return Lobby(play: p, spec: const LobbySpec(minP: 2, maxP: 4, defP: 2), emoji: '🕹️', onStart: _start);
    }
    if (phase == 3) {
      return FinalBoard(play: p, names: v.names, scores: scores, colors: [for (var i = 0; i < n; i++) PColors.player(i)]);
    }
    Widget top(int i) => RotatedBox(quarterTurns: 2, child: _zone(i));
    final List<Widget> rows = switch (n) {
      2 => [Expanded(child: top(0)), _center(), Expanded(child: _zone(1))],
      3 => [
          Expanded(child: Row(children: [Expanded(child: top(0)), Expanded(child: top(1))])),
          _center(),
          Expanded(child: _zone(2)),
        ],
      _ => [
          Expanded(child: Row(children: [Expanded(child: top(0)), Expanded(child: top(1))])),
          _center(),
          Expanded(child: Row(children: [Expanded(child: _zone(2)), Expanded(child: _zone(3))])),
        ],
    };
    return Column(children: [
      Expanded(child: Column(children: rows)),
      Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(t('mgCorner'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: kStudioSubtle)),
      ),
    ]);
  }
}

class _TugPainter extends CustomPainter {
  final Offset ball;
  final int n;
  _TugPainter(this.ball, this.n);

  @override
  void paint(Canvas c, Size size) {
    final h = size.width / 2;
    Offset at(Offset o) => Offset(h + o.dx * (h - 10), h + o.dy * (h - 10));
    c.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(14)), stroke(Colors.white38, 2));
    final dirs = cornerDirs(n);
    for (var i = 0; i < n; i++) {
      c.drawCircle(at(dirs[i]), 12, fill(PColors.player(i)));
    }
    c.drawCircle(at(ball), 11, fill(Colors.white));
  }

  @override
  bool shouldRepaint(covariant _TugPainter old) => true;
}

class _RingPainter extends CustomPainter {
  final double f;
  _RingPainter(this.f);

  @override
  void paint(Canvas c, Size size) {
    final ctr = size.center(Offset.zero);
    final ring = size.width * 0.36;
    c.drawCircle(ctr, ring, stroke(Colors.white, 4));
    c.drawCircle(ctr, clampD(ring * f, 0, size.width * 0.5), fill(const Color(0xFFF2C14E).withValues(alpha: 0.75)));
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => true;
}

// ================================================================ Hangisini Seçerdin?

const List<String> kWyrCats = ['a', 'f', 'o', 'j', 's', 'v', 'n', 'x'];

/// Turun iki kartı: aynı kategoriden, yaş paketine uyan ve daha önce çıkmamış.
List<(int, int, String)> wyrPairs(List<int> order, List<int> cats, int age, int rounds) {
  final used = <int>{};
  final out = <(int, int, String)>[];
  for (var k = 0; out.length < rounds && k < cats.length * 3; k++) {
    final cat = kWyrCats[cats[k % cats.length] % kWyrCats.length];
    final pick = <int>[];
    for (final i in order) {
      final c = kCards[i];
      if (c.cat == cat && c.tier <= age && !used.contains(i)) pick.add(i);
      if (pick.length == 2) break;
    }
    if (pick.length < 2) continue;
    used.addAll(pick);
    out.add((pick[0], pick[1], cat));
  }
  return out;
}

class WyrKind extends PartiKind {
  @override
  String get id => 'hangisini';
  const WyrKind();

  @override
  PDeck? make(int d, SeededRandom r) {
    final cats = perm(kWyrCats.length, r);
    final more = [for (var i = 0; i < 16; i++) r.nextInt(kWyrCats.length)];
    return PDeck(perm(kCards.length, r), b: [...cats, ...more], n: 4 + d ~/ 3);
  }

  @override
  bool check(PDeck p) {
    if (p.a.length != kCards.length || !uniqIn(p.a, kCards.length)) return false;
    if (p.n < 4 || p.n > 8 || p.b.length < 8) return false;
    // Çocuk paketinde bile bütün turlar kurulabilmeli.
    return wyrPairs(p.a, p.b, 0, p.n).length == p.n;
  }

  @override
  Widget build(PartiPlay play) => WyrView(play: play);
}

class WyrView extends StatefulWidget {
  final PartiPlay play;
  const WyrView({super.key, required this.play});

  @override
  State<WyrView> createState() => _WyrViewState();
}

class _WyrViewState extends State<WyrView> {
  PSettings? s;
  List<(int, int, String)> pairs = const [];
  int round = 0;
  int who = 0;

  /// 0 telefonu ver, 1 seç, 2 tahmin et, 3 sonuç, 4 bitiş.
  int phase = 0;
  List<int> scores = const [];
  List<int> pick = const [];
  List<int> guess = const [];

  PartiPlay get p => widget.play;
  String t(String k, [Map<String, Object> a = const {}]) => p.t(k, a);

  void _start(PSettings v) => setState(() {
        s = v;
        scores = List.filled(v.count, 0);
        pairs = wyrPairs(p.deck.a, p.deck.b, v.age, p.deck.n);
        if (pairs.isEmpty) pairs = wyrPairs(p.deck.a, p.deck.b, 2, p.deck.n);
        _reset();
      });

  void _reset() {
    pick = List.filled(s!.count, -1);
    guess = List.filled(s!.count, -1);
    who = 0;
    phase = 0;
  }

  void _choose(int side) => setState(() {
        if (phase == 1) {
          pick[who] = side;
          phase = 2;
        } else {
          guess[who] = side;
          who++;
          if (who >= s!.count) {
            _score();
          } else {
            phase = 0;
          }
        }
      });

  int get countA => pick.where((x) => x == 0).length;
  int get countB => pick.where((x) => x == 1).length;

  void _score() {
    final a = countA, b = countB;
    for (var i = 0; i < s!.count; i++) {
      if (a == b || (a > b ? 0 : 1) == guess[i]) scores[i]++;
    }
    p.sfx(Sfx.coin);
    phase = 3;
  }

  void _next() => setState(() {
        round++;
        if (round >= pairs.length) {
          phase = 4;
        } else {
          _reset();
        }
      });

  Widget _option(PCard c, int side, Color col) => Expanded(
        child: Semantics(
          button: true,
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: () => _choose(side),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: partyCard(context, edge: col),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Flexible(child: FittedBox(child: Text(c.emoji, style: const TextStyle(fontSize: 64)))),
                const SizedBox(height: 8),
                Text(cardLabel(p.lang, c),
                    textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              ]),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final v = s;
    if (v == null) {
      return Lobby(play: p, spec: const LobbySpec(minP: 3, maxP: 12, defP: 4, age: true), emoji: '⚖️', onStart: _start);
    }
    final names = v.names;
    if (phase == 4) return FinalBoard(play: p, names: names, scores: scores, colors: [for (var i = 0; i < v.count; i++) PColors.player(i)]);
    final (ia, ib, cat) = pairs[round];
    final a = kCards[ia], b = kCards[ib];
    final status = t('round', {'n': round + 1, 'm': pairs.length});
    final q = t('wyrQ_$cat');
    if (phase == 0) {
      return Column(children: [
        PBar(status: status),
        Expanded(
          child: PassGate(lang: p.lang, name: names[who], color: PColors.player(who), note: t('wyrPick'), onReady: () => setState(() => phase = 1)),
        ),
      ]);
    }
    if (phase == 1 || phase == 2) {
      return Column(children: [
        PBar(left: names[who], status: status),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(q, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(phase == 1 ? t('wyrPick') : t('wyrGuess'),
              textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: phase == 1 ? kStudioSubtle : const Color(0xFFF2C14E))),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              _option(a, 0, PColors.teams[0]),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Text(t('wyrOr'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
              _option(b, 1, PColors.teams[1]),
            ]),
          ),
        ),
      ]);
    }
    final ca = countA, cb = countB;
    return Column(children: [
      PBar(status: status),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(q, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          Expanded(child: Text('${a.emoji} ${cardLabel(p.lang, a)}\n$ca', textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
          Expanded(child: Text('${b.emoji} ${cardLabel(p.lang, b)}\n$cb', textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(ca == cb ? t('wyrTie') : t('wyrMajority'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, color: kStudioSubtle)),
      ),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: ScoreList(names: names, scores: scores, colors: [for (var i = 0; i < v.count; i++) PColors.player(i)]),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: BigBtn(label: t('next'), icon: Icons.arrow_forward, color: PColors.good, onTap: _next),
      ),
    ]);
  }
}

// ================================================================ Tek İpucu

/// İpucunu karşılaştırmak için sadeleştirir (büyük/küçük harf, boşluk, noktalama).
String clueKey(String s) => s.toLowerCase().replaceAll(RegExp(r'[\s\p{P}]+', unicode: true), '');

/// Aynı olan ya da gizli kelimeyi içeren ipuçlarını eler; kalanların sırası döner.
List<int> autoCancel(List<String> clues, String word) {
  final w = clueKey(word);
  final keys = [for (final c in clues) clueKey(c)];
  final out = <int>[];
  for (var i = 0; i < clues.length; i++) {
    final k = keys[i];
    if (k.isEmpty) continue;
    if (w.isNotEmpty && (k.contains(w) || w.contains(k))) continue;
    if (keys.where((x) => x == k).length > 1) continue;
    out.add(i);
  }
  return out;
}

class OneClueKind extends PartiKind {
  @override
  String get id => 'tek-ipucu';
  const OneClueKind();

  @override
  PDeck? make(int d, SeededRandom r) => PDeck(perm(kCards.length, r), n: 5 + d ~/ 3);

  @override
  bool check(PDeck p) {
    if (p.a.length != kCards.length || !uniqIn(p.a, kCards.length)) return false;
    final kids = p.a.where((i) => kCards[i].tier == 0).length;
    return kids >= 20 && p.n >= 5 && p.n <= 9;
  }

  @override
  Widget build(PartiPlay play) => OneClueView(play: play);
}

class OneClueView extends StatefulWidget {
  final PartiPlay play;
  const OneClueView({super.key, required this.play});

  @override
  State<OneClueView> createState() => _OneClueViewState();
}

class _OneClueViewState extends State<OneClueView> {
  PSettings? s;
  List<PlayCard> cards = const [];
  int round = 0;

  /// 0 tahminci uyarısı, 1 ipucu verene geçir, 2 ipucu yaz, 3 gözden geçir, 4 tahminciye geçir, 5 tahmin, 6 sonuç, 7 bitiş.
  int phase = 0;
  int giverIdx = 0;
  List<String> clues = [];
  Set<int> keep = {};
  int got = 0;
  bool? lastOk;
  final TextEditingController _ctl = TextEditingController();

  PartiPlay get p => widget.play;
  String t(String k, [Map<String, Object> a = const {}]) => p.t(k, a);
  int get guesser => round % s!.count;
  List<int> get givers => [for (var i = 0; i < s!.count; i++) if (i != guesser) i];
  PlayCard get card => cards[round % cards.length];

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _start(PSettings v) => setState(() {
        s = v;
        cards = dealCards(p, v, p.deck.a, withCat: true);
        _reset();
      });

  void _reset() {
    giverIdx = 0;
    clues = [];
    keep = {};
    lastOk = null;
    _ctl.clear();
    phase = 0;
  }

  void _submit() {
    final c = _ctl.text.trim().split(RegExp(r'\s+')).first;
    setState(() {
      clues.add(c);
      _ctl.clear();
      giverIdx++;
      if (giverIdx >= givers.length) {
        keep = autoCancel(clues, card.label).toSet();
        phase = 3;
      } else {
        phase = 1;
      }
    });
  }

  void _judge(bool ok) => setState(() {
        lastOk = ok;
        if (ok) got++;
        p.sfx(ok ? Sfx.win : Sfx.lose);
        phase = 6;
      });

  void _next() => setState(() {
        round++;
        if (round >= p.deck.n) {
          phase = 7;
        } else {
          _reset();
        }
      });

  Widget _clueChips({required bool editable}) => Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          for (var i = 0; i < clues.length; i++)
            if (editable || keep.contains(i))
              FilterChip(
                label: Text(clues[i].isEmpty ? '—' : clues[i],
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      decoration: keep.contains(i) ? null : TextDecoration.lineThrough,
                    )),
                selected: keep.contains(i),
                onSelected: editable
                    ? (on) => setState(() {
                          if (on) {
                            keep.add(i);
                          } else {
                            keep.remove(i);
                          }
                        })
                    : null,
              ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final v = s;
    if (v == null) {
      return Lobby(play: p, spec: const LobbySpec(minP: 3, maxP: 8, defP: 4, age: true, custom: true), emoji: '💡', onStart: _start);
    }
    if (phase == 7) return FinalBoard(play: p, names: [t('tiScore')], scores: [got], colors: const [PColors.good], headline: '${t('tiScore')}: $got');
    final status = '${t('round', {'n': round + 1, 'm': p.deck.n})} · ${t('tiScore')}: $got';
    final gname = v.names[guesser];
    switch (phase) {
      case 0:
        return Column(children: [
          PBar(left: '${t('tiGuesser')}: $gname', status: status),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('🙈', style: TextStyle(fontSize: 64)),
                  const SizedBox(height: 12),
                  Text(t('tiHide', {'n': gname}), textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 20),
                  BigBtn(label: t('next'), icon: Icons.arrow_forward, color: PColors.good, onTap: () => setState(() => phase = 1)),
                ]),
              ),
            ),
          ),
        ]);
      case 1:
        final gi = givers[giverIdx];
        return Column(children: [
          PBar(status: status),
          Expanded(child: PassGate(lang: p.lang, name: v.names[gi], color: PColors.player(gi), note: t('tiHide', {'n': gname}), onReady: () => setState(() => phase = 2))),
        ]);
      case 2:
        final gi = givers[giverIdx];
        return ListView(padding: const EdgeInsets.all(16), children: [
          PBar(left: v.names[gi], status: status),
          const SizedBox(height: 10),
          Text(t('tiWord'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, color: kStudioSubtle)),
          SizedBox(height: 180, child: CardFace(emoji: card.emoji, label: card.label, sub: card.sub)),
          const SizedBox(height: 12),
          Text(t('tiClue'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          TextField(
            controller: _ctl,
            maxLength: 24,
            textAlign: TextAlign.center,
            autocorrect: false,
            enableSuggestions: false,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 8),
          BigBtn(label: t('done'), icon: Icons.check, color: PColors.player(gi), onTap: _submit),
        ]);
      case 3:
        return Column(children: [
          PBar(status: status),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Text(t('tiHide', {'n': gname}), textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, color: kPartyWarnText)),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text('${card.emoji} ${card.label}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(t('tiReview'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 15)),
          ),
          Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(12), child: _clueChips(editable: true))),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: BigBtn(label: t('hide'), icon: Icons.visibility_off, color: PColors.good, onTap: () => setState(() => phase = 4)),
          ),
        ]);
      case 4:
        return Column(children: [
          PBar(status: status),
          Expanded(child: PassGate(lang: p.lang, name: gname, color: PColors.player(guesser), onReady: () => setState(() => phase = 5))),
        ]);
      case 5:
        return Column(children: [
          PBar(left: gname, status: status),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(t('tiGuessNow', {'n': gname}), textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: keep.isEmpty ? const Text('∅', textAlign: TextAlign.center, style: TextStyle(fontSize: 40)) : _clueChips(editable: false),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Row(children: [
              Expanded(child: BigBtn(label: t('tiMiss'), icon: Icons.close, color: PColors.bad, onTap: () => _judge(false))),
              const SizedBox(width: 8),
              Expanded(child: BigBtn(label: t('tiGot'), icon: Icons.check, color: PColors.good, onTap: () => _judge(true))),
            ]),
          ),
        ]);
      default:
        return Column(children: [
          PBar(status: status),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(lastOk == true ? '🎉' : '🤔', style: const TextStyle(fontSize: 56)),
                  const SizedBox(height: 8),
                  Text('${card.emoji} ${card.label}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
                ]),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: BigBtn(label: t('next'), icon: Icons.arrow_forward, color: PColors.good, onTap: _next),
          ),
        ]);
    }
  }
}

// ================================================================ İki Doğru Bir Yalan

class TwoTruthKind extends PartiKind {
  @override
  String get id => 'iki-dogru';
  const TwoTruthKind();

  @override
  PDeck? make(int d, SeededRandom r) => PDeck(perm(kFiveTopics.length, r), n: d >= 7 ? 2 : 1);

  @override
  bool check(PDeck p) => p.a.length == kFiveTopics.length && uniqIn(p.a, kFiveTopics.length) && linesOk(kFiveTopics) && (p.n == 1 || p.n == 2);

  @override
  Widget build(PartiPlay play) => TwoTruthView(play: play);
}

class TwoTruthView extends StatefulWidget {
  final PartiPlay play;
  const TwoTruthView({super.key, required this.play});

  @override
  State<TwoTruthView> createState() => _TwoTruthViewState();
}

class _TwoTruthViewState extends State<TwoTruthView> {
  PSettings? s;
  List<String> topics = const [];
  int round = 0;

  /// 0 anlatıcıya geçir, 1 yalanı gizlice seç, 2 anlat + oyla, 3 sonuç, 4 bitiş.
  int phase = 0;
  int lie = 0;
  List<int> votes = const [];
  List<int> scores = const [];

  PartiPlay get p => widget.play;
  String t(String k, [Map<String, Object> a = const {}]) => p.t(k, a);
  int get rounds => s!.count * p.deck.n;
  int get speaker => round % s!.count;
  String get topic => topics.isEmpty ? '' : topics[round % topics.length];

  void _start(PSettings v) => setState(() {
        s = v;
        scores = List.filled(v.count, 0);
        topics = dealLines(kFiveTopics, p.deck.a, v.age, p.lang);
        _reset();
      });

  void _reset() {
    lie = 0;
    votes = List.filled(s!.count, 0);
    phase = 0;
  }

  void _reveal() => setState(() {
        var fooled = 0;
        for (var i = 0; i < s!.count; i++) {
          if (i == speaker) continue;
          if (votes[i] == lie) {
            scores[i]++;
          } else {
            fooled++;
          }
        }
        scores[speaker] += fooled;
        p.sfx(fooled > 0 ? Sfx.coin : Sfx.win);
        phase = 3;
      });

  void _next() => setState(() {
        round++;
        if (round >= rounds) {
          phase = 4;
        } else {
          _reset();
        }
      });

  Widget _num(int k, int sel, VoidCallback onTap, Color col) {
    final on = k == sel;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: ChoiceChip(
        label: Text('$k', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
        selected: on,
        selectedColor: col,
        onSelected: (_) => onTap(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final v = s;
    if (v == null) {
      return Lobby(play: p, spec: const LobbySpec(minP: 3, maxP: 12, defP: 4, age: true), emoji: '🤥', onStart: _start);
    }
    final names = v.names;
    final colors = [for (var i = 0; i < v.count; i++) PColors.player(i)];
    if (phase == 4) return FinalBoard(play: p, names: names, scores: scores, colors: colors);
    final status = t('round', {'n': round + 1, 'm': rounds});
    final sc = PColors.player(speaker);
    Widget topicCard() => Container(
          margin: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          padding: const EdgeInsets.all(14),
          decoration: partyCard(context, edge: sc),
          child: Column(children: [
            Text(t('tlTopic'), style: const TextStyle(fontSize: 14, color: kStudioSubtle)),
            Text(topic, textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          ]),
        );
    if (phase == 0) {
      return Column(children: [
        PBar(status: status),
        Expanded(child: PassGate(lang: p.lang, name: names[speaker], color: sc, note: t('tlNote'), onReady: () => setState(() => phase = 1))),
      ]);
    }
    if (phase == 1) {
      return ListView(padding: const EdgeInsets.only(bottom: 16), children: [
        PBar(left: names[speaker], status: status),
        topicCard(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
          child: Text(t('tlSay'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
        ),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var k = 1; k <= 3; k++) _num(k, lie, () => setState(() => lie = k), sc),
        ]),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: BigBtn(label: t('hide'), icon: Icons.visibility_off, color: sc, onTap: lie == 0 ? null : () => setState(() => phase = 2)),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(t('tlNote'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: kStudioSubtle)),
        ),
      ]);
    }
    if (phase == 2) {
      final ready = [for (var i = 0; i < v.count; i++) if (i != speaker) votes[i]].every((x) => x > 0);
      return Column(children: [
        PBar(left: names[speaker], status: status),
        topicCard(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(t('tlWhich'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.all(12), children: [
            for (var i = 0; i < v.count; i++)
              if (i != speaker)
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: colors[i].withValues(alpha: 0.16), borderRadius: BorderRadius.circular(14)),
                  child: Row(children: [
                    CircleAvatar(radius: 9, backgroundColor: colors[i]),
                    const SizedBox(width: 8),
                    Expanded(child: Text(names[i], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16))),
                    for (var k = 1; k <= 3; k++) _num(k, votes[i], () => setState(() => votes[i] = k), colors[i]),
                  ]),
                ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          child: BigBtn(label: t('showVotes'), icon: Icons.how_to_vote, color: sc, onTap: ready ? _reveal : null),
        ),
      ]);
    }
    return Column(children: [
      PBar(status: status),
      Padding(
        padding: const EdgeInsets.all(14),
        child: Text('${t('tlLie')}: $lie', textAlign: TextAlign.center, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Color(0xFFF2C14E))),
      ),
      Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(12), child: ScoreList(names: names, scores: scores, colors: colors, highlight: speaker))),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: BigBtn(label: t('next'), icon: Icons.arrow_forward, color: PColors.good, onTap: _next),
      ),
    ]);
  }
}
