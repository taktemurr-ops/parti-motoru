import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/strings.dart';

import '../core.dart';
import '../data/cards.dart';
import '../party.dart';

// ---------------------------------------------------------------- Köylü ve Vampir

/// Roller: 0 köylü, 1 vampir, 2 doktor, 3 gözcü.
const kRoleEmoji = ['🧑‍🌾', '🧛', '🩺', '🔮'];
const _roleKey = ['roleVillager', 'roleVampire', 'roleDoctor', 'roleSeer'];
const _roleDesc = ['descVillager', 'descVampire', 'descDoctor', 'descSeer'];

/// [players] kişilik masa için rol dizisi (kişi sırasına göre değil, dağıtım öncesi).
List<int> vampireRoles(int players) {
  final v = players <= 6 ? 1 : (players <= 9 ? 2 : 3);
  return [
    for (var i = 0; i < v; i++) 1,
    2,
    if (players >= 6) 3,
    for (var i = v + (players >= 6 ? 2 : 1); i < players; i++) 0,
  ];
}

class VampireKind extends PartiKind {
  @override
  String get id => 'koylu-vampir';
  const VampireKind();

  @override
  PDeck? make(int d, SeededRandom r) => PDeck(perm(12, r), n: d);

  @override
  bool check(PDeck p) {
    if (p.a.length != 12 || !uniqIn(p.a, 12)) return false;
    for (var n = 5; n <= 12; n++) {
      final roles = vampireRoles(n);
      if (roles.length != n) return false;
      final v = roles.where((x) => x == 1).length;
      // Vampirler her zaman azınlıkta başlar.
      if (v < 1 || v * 2 >= n) return false;
    }
    return true;
  }

  @override
  Widget build(PartiPlay play) => VampireView(play: play);
}

class VampireView extends StatefulWidget {
  final PartiPlay play;
  const VampireView({super.key, required this.play});

  @override
  State<VampireView> createState() => _VampireViewState();
}

class _VampireViewState extends State<VampireView> {
  PSettings? s;
  List<int> roles = const [];
  List<bool> alive = const [];

  /// reveal, night, vamp, doc, seer, seerSaw, morning, day, vote, out, end
  String phase = 'reveal';
  int who = 0;
  bool shown = false;
  int night = 1;
  int? victim;
  int? saved;
  int? seen;
  int? lastOut;
  int winner = -1;

  PartiPlay get p => widget.play;
  String t(String k, [Map<String, Object> a = const {}]) => p.t(k, a);

  void _start(PSettings v) {
    final base = vampireRoles(v.count);
    final order = [for (final x in p.deck.a) if (x < v.count) x];
    final r = List.filled(v.count, 0);
    for (var k = 0; k < v.count; k++) {
      r[order[k]] = base[k];
    }
    setState(() {
      s = v;
      roles = r;
      alive = List.filled(v.count, true);
      phase = 'reveal';
      who = 0;
    });
  }

  bool _has(int role) {
    for (var i = 0; i < roles.length; i++) {
      if (roles[i] == role && alive[i]) return true;
    }
    return false;
  }

  /// 1 köylüler, 2 vampirler, 0 sürüyor.
  int _check() {
    var v = 0, o = 0;
    for (var i = 0; i < roles.length; i++) {
      if (!alive[i]) continue;
      if (roles[i] == 1) {
        v++;
      } else {
        o++;
      }
    }
    if (v == 0) return 1;
    if (v >= o) return 2;
    return 0;
  }

  void _go(String ph) => setState(() => phase = ph);

  void _afterNightStep(String from) {
    // Ölü rollerin sırası atlanır.
    if (from == 'vamp') {
      if (_has(2)) return _go('doc');
      from = 'doc';
    }
    if (from == 'doc') {
      if (_has(3)) return _go('seer');
    }
    _morning();
  }

  void _morning() {
    setState(() {
      final vv = victim;
      if (vv != null && vv != saved) {
        alive[vv] = false;
        lastOut = vv;
      } else {
        lastOut = null;
      }
      victim = saved = seen = null;
      phase = 'morning';
      winner = _check();
    });
    p.sfx(lastOut == null ? Sfx.unlock : Sfx.lose);
  }

  Widget _pickList(List<int> ids, void Function(int i) onPick, {Widget? footer}) {
    final v = s!;
    final f = footer;
    return Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: [
      for (final i in ids)
        ActionChip(
          avatar: CircleAvatar(backgroundColor: PColors.player(i)),
          label: Text(v.names[i], style: const TextStyle(fontSize: 18)),
          onPressed: () {
            p.sfx(Sfx.tap);
            onPick(i);
          },
        ),
      if (f != null) f,
    ]);
  }

  Widget _screen(String emoji, String title, String body, {Widget? child, String? button, VoidCallback? onButton}) {
    final c = child;
    final b = button;
    return ListView(padding: const EdgeInsets.all(20), children: [
      Center(child: Text(emoji, style: const TextStyle(fontSize: 64))),
      const SizedBox(height: 8),
      Center(child: Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900))),
      const SizedBox(height: 10),
      Text(body, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18)),
      const SizedBox(height: 18),
      if (c != null) c,
      if (b != null) ...[
        const SizedBox(height: 18),
        BigBtn(label: b, icon: Icons.arrow_forward, color: PColors.ink, onTap: onButton),
      ],
    ]);
  }

  List<int> get living => [for (var i = 0; i < roles.length; i++) if (alive[i]) i];

  @override
  Widget build(BuildContext context) {
    final v = s;
    if (v == null) {
      return Lobby(
        play: p,
        spec: const LobbySpec(minP: 5, maxP: 12, defP: 6, times: [60, 120, 180, 300], defTime: 120),
        emoji: '🧛',
        onStart: _start,
      );
    }
    final bar = PBar(left: '${t('night')} $night', status: '${t('alive')}: ${living.length}/${v.count}');
    Widget body;
    switch (phase) {
      case 'reveal':
        if (!shown) {
          body = PassGate(
            lang: p.lang,
            name: v.names[who],
            color: PColors.player(who),
            note: t('secretNote'),
            onReady: () => setState(() => shown = true),
          );
        } else {
          final r = roles[who];
          body = _screen(kRoleEmoji[r], '${t('roleYour')}: ${t(_roleKey[r])}', t(_roleDesc[r]),
              child: r == 1 && v.count > 6
                  ? Text(
                      '🧛 ${[for (var i = 0; i < v.count; i++) if (roles[i] == 1 && i != who) v.names[i]].join(', ')}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))
                  : null,
              button: t('hide'), onButton: () {
            setState(() {
              shown = false;
              if (who + 1 < v.count) {
                who++;
              } else {
                phase = 'night';
              }
            });
          });
        }
      case 'night':
        body = _screen('🌙', '${t('night')} $night', t('closeEyes'), button: t('next'), onButton: () => _go('vamp'));
      case 'vamp':
        body = _screen('🧛', t('roleVampire'), t('vampWake'),
            child: _pickList([for (final i in living) if (roles[i] != 1) i], (i) {
              victim = i;
              _afterNightStep('vamp');
            }));
      case 'doc':
        body = _screen('🩺', t('roleDoctor'), t('doctorWake'), child: _pickList(living, (i) {
          saved = i;
          _afterNightStep('doc');
        }));
      case 'seer':
        body = _screen('🔮', t('roleSeer'), t('seerWake'),
            child: _pickList([for (final i in living) if (roles[i] != 3) i], (i) {
              setState(() {
                seen = i;
                phase = 'seerSaw';
              });
            }));
      case 'seerSaw':
        final sn = seen ?? 0;
        final vamp = roles[sn] == 1;
        body = _screen(vamp ? '🧛' : '🧑‍🌾', v.names[sn], t(vamp ? 'isVamp' : 'notVamp'),
            button: t('eyesClosed'), onButton: _morning);
      case 'morning':
        final lm = lastOut;
        body = _screen(
          '☀️',
          t('morning'),
          lm == null ? t('nobodyOut') : '${t('out', {'n': v.names[lm]})} ${kRoleEmoji[roles[lm]]} ${t(_roleKey[roles[lm]])}',
          button: t('next'),
          onButton: () => _go(winner != 0 ? 'end' : 'day'),
        );
      case 'day':
        body = Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Countdown(key: ValueKey('day$night'), seconds: v.seconds, sfx: p.sfx, onEnd: () {
              if (mounted && phase == 'day') _go('vote');
            }),
          ),
          Expanded(
            child: _screen('🗣️', t('day'), t('discuss'), button: t('vote'), onButton: () => _go('vote')),
          ),
        ]);
      case 'vote':
        body = _screen('🗳️', t('vote'), t('voteNote'),
            child: _pickList(
              living,
              (i) {
                setState(() {
                  alive[i] = false;
                  lastOut = i;
                  winner = _check();
                  phase = 'out';
                });
              },
              footer: ActionChip(
                avatar: const Text('🤝'),
                label: Text(t('skipVote')),
                onPressed: () => setState(() {
                  lastOut = null;
                  phase = 'out';
                }),
              ),
            ));
      case 'out':
        final lx = lastOut;
        body = _screen(
          lx == null ? '🤝' : kRoleEmoji[roles[lx]],
          lx == null ? t('nobodyOut') : t('out', {'n': v.names[lx]}),
          lx == null ? '' : t(_roleKey[roles[lx]]),
          button: t('next'),
          onButton: () => setState(() {
            if (winner != 0) {
              phase = 'end';
            } else {
              night++;
              phase = 'night';
            }
          }),
        );
      default:
        final vampWin = winner == 2;
        final sc = [for (var i = 0; i < v.count; i++) (roles[i] == 1) == vampWin ? 1 : 0];
        final head = t(vampWin ? 'vampiresWin' : 'villagersWin');
        body = ListView(padding: const EdgeInsets.all(18), children: [
          Center(child: Text(vampWin ? '🧛' : '🧑‍🌾', style: const TextStyle(fontSize: 70))),
          Center(child: Text(head, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900))),
          const SizedBox(height: 12),
          for (var i = 0; i < v.count; i++)
            ListTile(
              leading: Text(kRoleEmoji[roles[i]], style: const TextStyle(fontSize: 26)),
              title: Text(v.names[i], style: TextStyle(decoration: alive[i] ? null : TextDecoration.lineThrough)),
              subtitle: Text(t(_roleKey[roles[i]])),
              trailing: sc[i] > 0 ? const Text('🏆') : null,
            ),
          const SizedBox(height: 12),
          BigBtn(
            label: t('finish'),
            icon: Icons.flag,
            color: PColors.good,
            onTap: () => p.finishScores(v.names, sc, headline: head),
          ),
        ]);
    }
    return Column(children: [bar, Expanded(child: body)]);
  }
}

// ---------------------------------------------------------------- Casus Kim

class SpyKind extends PartiKind {
  @override
  String get id => 'casus-kim';
  const SpyKind();

  @override
  PDeck? make(int d, SeededRandom r) {
    final n = 3 + d ~/ 4;
    return PDeck(perm(kPlaces.length, r).take(n).toList(), b: perm(12, r), n: n, m: d >= 6 ? 2 : 1);
  }

  @override
  bool check(PDeck p) =>
      p.n >= 3 &&
      p.n <= 5 &&
      p.a.length == p.n &&
      uniqIn(p.a, kPlaces.length) &&
      p.b.length == 12 &&
      uniqIn(p.b, 12) &&
      (p.m == 1 || p.m == 2) &&
      kPlaces.every((x) => x.names.length == 33);

  @override
  Widget build(PartiPlay play) => SpyView(play: play);
}

String placeName(String lang, int i) => Strings.pick(kPlaces[i].names, lang);

class SpyView extends StatefulWidget {
  final PartiPlay play;
  const SpyView({super.key, required this.play});

  @override
  State<SpyView> createState() => _SpyViewState();
}

class _SpyViewState extends State<SpyView> {
  PSettings? s;
  int round = 0;

  /// reveal, talk, vote, guess, result, end
  String phase = 'reveal';
  int who = 0;
  bool shown = false;
  List<int> scores = const [];
  Set<int> spies = const {};
  String result = '';

  PartiPlay get p => widget.play;
  String t(String k, [Map<String, Object> a = const {}]) => p.t(k, a);

  int get place => p.deck.a[round];

  void _setupRound() {
    final v = s!;
    final n = v.count >= 8 && p.deck.m == 2 ? 2 : 1;
    final order = [for (final x in p.deck.b) if (x < v.count) x];
    spies = {for (var k = 0; k < n; k++) order[(round * n + k) % order.length]};
    who = 0;
    shown = false;
    phase = 'reveal';
  }

  void _start(PSettings v) => setState(() {
        s = v;
        scores = List.filled(v.count, 0);
        round = 0;
        _setupRound();
      });

  void _spyWins() {
    p.sfx(Sfx.lose);
    setState(() {
      for (final x in spies) {
        scores[x] += 2;
      }
      result = '${t('spyWins')} ${placeEmoji()} ${placeName(p.lang, place)}';
      phase = 'result';
    });
  }

  void _townWins() {
    p.sfx(Sfx.win);
    setState(() {
      for (var i = 0; i < scores.length; i++) {
        if (!spies.contains(i)) scores[i] += 1;
      }
      result = '${t('spyCaught')} ${placeEmoji()} ${placeName(p.lang, place)}';
      phase = 'result';
    });
  }

  String placeEmoji() => kPlaces[place].emoji;

  @override
  Widget build(BuildContext context) {
    final v = s;
    if (v == null) {
      return Lobby(
        play: p,
        spec: const LobbySpec(minP: 3, maxP: 12, defP: 5, times: [180, 300, 420, 600], defTime: 300),
        emoji: '🕵️',
        onStart: _start,
      );
    }
    final bar = PBar(left: t('round', {'n': round + 1, 'm': p.deck.n}), status: '🕵️ ${spies.length}');
    Widget body;
    switch (phase) {
      case 'reveal':
        if (!shown) {
          body = PassGate(lang: p.lang, name: v.names[who], color: PColors.player(who), note: t('secretNote'), onReady: () => setState(() => shown = true));
        } else {
          final spy = spies.contains(who);
          body = ListView(padding: const EdgeInsets.all(20), children: [
            spy
                ? CardFace(emoji: '🕵️', label: t('spyYou'), edge: PColors.bad)
                : CardFace(emoji: placeEmoji(), label: placeName(p.lang, place), sub: t('place'), edge: PColors.good),
            const SizedBox(height: 18),
            BigBtn(
              label: t('hide'),
              icon: Icons.visibility_off,
              color: PColors.ink,
              onTap: () => setState(() {
                shown = false;
                if (who + 1 < v.count) {
                  who++;
                } else {
                  phase = 'talk';
                }
              }),
            ),
          ]);
        }
      case 'talk':
        body = Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Countdown(key: ValueKey('spy$round'), seconds: v.seconds, sfx: p.sfx, onEnd: () {
              if (mounted && phase == 'talk') setState(() => phase = 'vote');
            }),
          ),
          Expanded(
            child: ListView(padding: const EdgeInsets.all(20), children: [
              const Center(child: Text('❓', style: TextStyle(fontSize: 64))),
              Text(t('spyTalk', {'n': v.names[(round + p.seed) % v.count]}),
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 20),
              BigBtn(label: t('vote'), icon: Icons.how_to_vote, color: PColors.bad, onTap: () => setState(() => phase = 'vote')),
            ]),
          ),
        ]);
      case 'vote':
        body = ListView(padding: const EdgeInsets.all(20), children: [
          Center(child: Text(t('whoSpy'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900))),
          const SizedBox(height: 14),
          Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: [
            for (var i = 0; i < v.count; i++)
              ActionChip(
                avatar: CircleAvatar(backgroundColor: PColors.player(i)),
                label: Text(v.names[i], style: const TextStyle(fontSize: 18)),
                onPressed: () {
                  if (spies.contains(i)) {
                    p.sfx(Sfx.combo);
                    setState(() => phase = 'guess');
                  } else {
                    _spyWins();
                  }
                },
              ),
          ]),
        ]);
      case 'guess':
        body = ListView(padding: const EdgeInsets.all(14), children: [
          Text(t('spyGuess'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
            for (var i = 0; i < kPlaces.length; i++)
              ActionChip(
                avatar: Text(kPlaces[i].emoji),
                label: Text(placeName(p.lang, i)),
                onPressed: () => i == place ? _spyWins() : _townWins(),
              ),
          ]),
        ]);
      case 'result':
        body = ListView(padding: const EdgeInsets.all(18), children: [
          Center(child: Text(result, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
          const SizedBox(height: 6),
          Center(child: Text('🕵️ ${[for (final x in spies) v.names[x]].join(', ')}', style: const TextStyle(fontSize: 18))),
          const SizedBox(height: 12),
          ScoreList(names: v.names, scores: scores, colors: [for (var i = 0; i < v.count; i++) PColors.player(i)]),
          const SizedBox(height: 14),
          BigBtn(
            label: t('next'),
            icon: Icons.arrow_forward,
            color: PColors.ink,
            onTap: () => setState(() {
              round++;
              if (round >= p.deck.n) {
                phase = 'end';
              } else {
                _setupRound();
              }
            }),
          ),
        ]);
      default:
        body = FinalBoard(play: p, names: v.names, scores: scores, colors: [for (var i = 0; i < v.count; i++) PColors.player(i)]);
    }
    return Column(children: [bar, Expanded(child: body)]);
  }
}

// ---------------------------------------------------------------- Doğruluk mu Görev mi

class TruthKind extends PartiKind {
  @override
  String get id => 'dogruluk-cesaret';
  const TruthKind();

  @override
  PDeck? make(int d, SeededRandom r) => PDeck(perm(kTruthTr.length, r), b: perm(kDareTr.length, r), n: 2 + d ~/ 6);

  @override
  bool check(PDeck p) =>
      kTruth.length == Strings.languages.length &&
      kDare.length == Strings.languages.length &&
      p.a.length == kTruthTr.length &&
      uniqIn(p.a, kTruthTr.length) &&
      p.b.length == kDareTr.length &&
      uniqIn(p.b, kDareTr.length) &&
      p.n >= 2 &&
      p.n <= 3 &&
      kTruth.every((l) => _tiersMatch(kTruthTr, l)) &&
      kDare.every((l) => _tiersMatch(kDareTr, l));

  @override
  Widget build(PartiPlay play) => TruthView(play: play);
}

bool _tiersMatch(List<PPrompt> a, List<PPrompt> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].tier != b[i].tier || a[i].text.isEmpty || b[i].text.isEmpty) return false;
  }
  return true;
}

/// Görev listesi: yaş paketine uyanlar, oyuncunun dilinde, kendi görevlerle harman.
List<String> dareList(PartiPlay p, PSettings v) {
  final src = langItem(kDare, p.lang);
  final out = [for (final i in p.deck.b) if (src[i].tier <= v.age) src[i].text];
  return [
    for (var i = 0; i < out.length; i++) ...[
      if (v.custom.isNotEmpty && i % 3 == 2) '✍️ ${v.custom[(i ~/ 3) % v.custom.length]}',
      out[i],
    ]
  ];
}

class TruthView extends StatefulWidget {
  final PartiPlay play;
  const TruthView({super.key, required this.play});

  @override
  State<TruthView> createState() => _TruthViewState();
}

class _TruthViewState extends State<TruthView> {
  PSettings? s;
  List<String> truths = const [];
  List<String> dares = const [];
  int ti = 0, di = 0, turn = 0;
  List<int> scores = const [];
  List<int> passes = const [];
  String? prompt;
  bool isDare = false;

  PartiPlay get p => widget.play;
  String t(String k, [Map<String, Object> a = const {}]) => p.t(k, a);

  int get turns => s!.count * p.deck.n;
  int get player => turn % s!.count;

  void _start(PSettings v) {
    final src = langItem(kTruth, p.lang);
    setState(() {
      s = v;
      truths = [for (final i in p.deck.a) if (src[i].tier <= v.age) src[i].text];
      dares = dareList(p, v);
      scores = List.filled(v.count, 0);
      passes = List.filled(v.count, 2);
    });
  }

  void _pick(int kind) {
    // 0 doğruluk, 1 görev, 2 rastgele (tohuma ve tura göre).
    final dare = kind == 2 ? ((turn * 7 + p.seed) % 2 == 1) : kind == 1;
    p.sfx(Sfx.place);
    setState(() {
      isDare = dare;
      if (dare) {
        prompt = dares[di % dares.length];
        di++;
      } else {
        prompt = truths[ti % truths.length];
        ti++;
      }
    });
  }

  void _done(bool did) {
    setState(() {
      if (did) {
        scores[player] += isDare ? 2 : 1;
        p.sfx(Sfx.coin);
      } else {
        passes[player]--;
      }
      prompt = null;
      turn++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final v = s;
    if (v == null) {
      return Lobby(
        play: p,
        spec: const LobbySpec(minP: 2, maxP: 12, defP: 4, age: true, custom: true),
        emoji: '🎲',
        onStart: _start,
      );
    }
    final colors = [for (var i = 0; i < v.count; i++) PColors.player(i)];
    if (turn >= turns) return FinalBoard(play: p, names: v.names, scores: scores, colors: colors);
    final pr = prompt;
    final c = PColors.player(player);
    return Column(children: [
      PBar(left: v.names[player], status: t('round', {'n': turn + 1, 'm': turns})),
      Expanded(
        child: ListView(padding: const EdgeInsets.all(18), children: [
          if (pr == null) ...[
            const SizedBox(height: 10),
            Center(child: CircleAvatar(radius: 40, backgroundColor: c, child: const Text('🎯', style: TextStyle(fontSize: 34)))),
            const SizedBox(height: 10),
            Center(child: Text(t('yourTurnN', {'n': v.names[player]}), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900))),
            const SizedBox(height: 22),
            BigBtn(label: t('truth'), icon: Icons.record_voice_over, color: const Color(0xFF3B86A8), onTap: () => _pick(0)),
            const SizedBox(height: 10),
            BigBtn(label: t('dare'), icon: Icons.directions_run, color: const Color(0xFFE0735A), onTap: () => _pick(1)),
            const SizedBox(height: 10),
            BigBtn(label: t('random'), icon: Icons.casino_outlined, color: const Color(0xFF8A5BA6), onTap: () => _pick(2)),
          ] else ...[
            CardFace(
              emoji: isDare ? '🎬' : '💬',
              label: t(isDare ? 'dare' : 'truth'),
              edge: isDare ? const Color(0xFFE0735A) : const Color(0xFF3B86A8),
            ),
            const SizedBox(height: 14),
            Text(pr, textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, height: 1.25)),
            const SizedBox(height: 22),
            Row(children: [
              Expanded(
                child: BigBtn(
                  label: '${t('pass')} ${passes[player]}',
                  icon: Icons.skip_next,
                  color: PColors.line,
                  onTap: passes[player] > 0 ? () => _done(false) : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: BigBtn(label: t('did'), icon: Icons.check, color: PColors.good, onTap: () => _done(true))),
            ]),
          ],
          const SizedBox(height: 20),
          ScoreList(names: v.names, scores: scores, colors: colors, highlight: player),
        ]),
      ),
    ]);
  }
}

// ---------------------------------------------------------------- Çevir Bakalım

class SpinKind extends PartiKind {
  @override
  String get id => 'sise-cevirme';
  const SpinKind();

  @override
  PDeck? make(int d, SeededRandom r) =>
      PDeck([for (var i = 0; i < 40; i++) r.nextInt(1000)], b: perm(kDareTr.length, r), n: 8 + d);

  @override
  bool check(PDeck p) =>
      p.a.length == 40 &&
      p.a.every((x) => x >= 0 && x < 1000) &&
      p.b.length == kDareTr.length &&
      uniqIn(p.b, kDareTr.length) &&
      p.n >= 8 &&
      p.n <= 18 &&
      kDareTr.where((x) => x.tier == 0).length >= 10;

  @override
  Widget build(PartiPlay play) => SpinView(play: play);
}

class SpinView extends StatefulWidget {
  final PartiPlay play;
  const SpinView({super.key, required this.play});

  @override
  State<SpinView> createState() => _SpinViewState();
}

class _SpinViewState extends State<SpinView> with SingleTickerProviderStateMixin {
  PSettings? s;
  late final AnimationController ac = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200));
  double from = -math.pi / 2, to = -math.pi / 2;
  int spin = 0;
  int? chosen;
  List<String> dares = const [];
  List<int> scores = const [];
  String? task;

  PartiPlay get p => widget.play;
  String t(String k, [Map<String, Object> a = const {}]) => p.t(k, a);

  @override
  void initState() {
    super.initState();
    ac.addListener(() => setState(() {}));
    ac.addStatusListener((st) {
      if (st == AnimationStatus.completed && mounted) {
        final v = s;
        if (v == null) return;
        p.sfx(Sfx.combo);
        setState(() {
          chosen = _indexAt(to, v.count);
          task = dares.isEmpty ? null : dares[spin % dares.length];
          spin++;
        });
      }
    });
  }

  @override
  void dispose() {
    ac.dispose();
    super.dispose();
  }

  double get angle => from + (to - from) * Curves.easeOutCubic.transform(ac.value);

  int _indexAt(double a, int n) {
    final step = 2 * math.pi / n;
    final k = ((a + math.pi / 2) / step).round();
    return ((k % n) + n) % n;
  }

  void _spin() {
    final v = s;
    if (v == null || ac.isAnimating || spin >= p.deck.n) return;
    final r = p.deck.a[spin % p.deck.a.length];
    p.sfx(Sfx.place);
    setState(() {
      chosen = null;
      task = null;
      from = to % (2 * math.pi);
      to = from + 6 * math.pi + r / 1000 * 2 * math.pi;
    });
    ac.forward(from: 0);
  }

  void _paint(Canvas c, PSettings v) {
    const cx = 500.0, cy = 500.0;
    c.drawCircle(const Offset(cx, cy), 470, fill(const Color(0xFFEFE6D3)));
    c.drawCircle(const Offset(cx, cy), 470, stroke(PColors.line, 6));
    final n = v.count;
    for (var i = 0; i < n; i++) {
      final a = -math.pi / 2 + i * 2 * math.pi / n;
      final o = Offset(cx + 380 * math.cos(a), cy + 380 * math.sin(a));
      c.drawCircle(o, 62, fill(PColors.player(i).withValues(alpha: chosen == i ? 1 : 0.75)));
      if (chosen == i) c.drawCircle(o, 70, stroke(PColors.warn, 10));
      final nm = v.names[i];
      drawLabel(c, nm.length > 7 ? '${nm.substring(0, 6)}…' : nm, o, 30, Colors.white);
    }
    // Ok: su şişesi yerine yön oku (aile dostu).
    c.save();
    c.translate(cx, cy);
    c.rotate(angle);
    final body = Path()
      ..moveTo(250, 0)
      ..lineTo(170, -48)
      ..lineTo(170, -20)
      ..lineTo(-170, -20)
      ..lineTo(-170, 20)
      ..lineTo(170, 20)
      ..lineTo(170, 48)
      ..close();
    c.drawPath(body, fill(const Color(0xFFC8553D)));
    c.drawPath(body, stroke(const Color(0xFF7D3324), 6));
    c.restore();
    c.drawCircle(const Offset(cx, cy), 34, fill(PColors.ink));
    c.drawCircle(const Offset(cx, cy), 14, fill(PColors.warn));
  }

  @override
  Widget build(BuildContext context) {
    final v = s;
    if (v == null) {
      return Lobby(
        play: p,
        spec: const LobbySpec(minP: 2, maxP: 12, defP: 5, age: true, custom: true),
        emoji: '🌀',
        onStart: (x) => setState(() {
          s = x;
          dares = dareList(p, x);
          scores = List.filled(x.count, 0);
        }),
      );
    }
    final colors = [for (var i = 0; i < v.count; i++) PColors.player(i)];
    final ch = chosen;
    final tk = task;
    if (spin >= p.deck.n && ch == null) return FinalBoard(play: p, names: v.names, scores: scores, colors: colors);
    return Column(children: [
      PBar(status: t('round', {'n': math.min<int>(spin + (ch == null ? 1 : 0), p.deck.n), 'm': p.deck.n})),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: TapCanvas(w: 1000, h: 1000, paint: (c) => _paint(c, v), onTap: (_) => _spin(), onPanEnd: _spin, onPanStart: (_) {}),
        ),
      ),
      if (ch != null && tk != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('${v.names[ch]}: $tk', textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: ch == null
            ? BigBtn(label: t('spin'), icon: Icons.refresh, color: PColors.bad, onTap: ac.isAnimating ? null : _spin)
            : Row(children: [
                Expanded(
                  child: BigBtn(
                    label: t('pass'),
                    icon: Icons.skip_next,
                    color: PColors.line,
                    onTap: () => setState(() => chosen = null),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: BigBtn(
                    label: t('did'),
                    icon: Icons.check,
                    color: PColors.good,
                    onTap: () {
                      p.sfx(Sfx.coin);
                      setState(() {
                        scores[ch]++;
                        chosen = null;
                      });
                    },
                  ),
                ),
              ]),
      ),
    ]);
  }
}
