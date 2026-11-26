import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/strings.dart';

import 'core.dart';
import 'data/cards.dart';
import 'texts.dart';
import 'studio_chrome.dart';

/// Lobide seçilen ayarlar.
class PSettings {
  final List<String> names;
  final bool teams;
  final int seconds;

  /// 0 çocuk, 1 aile, 2 herkes.
  final int age;
  final List<String> custom;
  const PSettings({required this.names, this.teams = false, this.seconds = 60, this.age = 1, this.custom = const []});

  int get count => names.length;

  /// Takım oyununda oyuncu sırayla A, B, A, B... takımına girer.
  int teamOf(int p) => p % 2;

  List<int> members(int team) => [for (var i = 0; i < names.length; i++) if (i % 2 == team) i];
}

/// Lobinin türe göre seçenekleri.
class LobbySpec {
  final int minP;
  final int maxP;
  final int defP;

  /// 0: takım yok, 1: isteğe bağlı, 2: zorunlu.
  final int teams;
  final List<int> times;
  final int defTime;
  final bool age;
  final bool custom;
  const LobbySpec({
    this.minP = 2,
    this.maxP = 12,
    this.defP = 4,
    this.teams = 0,
    this.times = const [],
    this.defTime = 60,
    this.age = false,
    this.custom = false,
  });
}

/// Oyuncu adları ve kendi kelimeler cihazda saklanır (aile her açışta yeniden yazmasın).
class PartyStore {
  static List<String> names = const [];
  static List<String> custom = const [];
  static bool _loaded = false;

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      names = p.getStringList('parti.names') ?? const [];
      custom = p.getStringList('parti.custom') ?? const [];
    } catch (_) {}
  }

  static Future<void> save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList('parti.names', names);
      await p.setStringList('parti.custom', custom);
    } catch (_) {}
  }
}

/// Ortak lobi: oyuncular, takım, süre, kart paketi ve kendi kelimeler.
class Lobby extends StatefulWidget {
  final PartiPlay play;
  final LobbySpec spec;
  final String emoji;
  final void Function(PSettings s) onStart;
  const Lobby({super.key, required this.play, required this.spec, required this.emoji, required this.onStart});

  @override
  State<Lobby> createState() => _LobbyState();
}

class _LobbyState extends State<Lobby> {
  late List<String> names;
  late bool teams;
  late int secs;
  int age = 1;
  List<String> custom = const [];

  LobbySpec get sp => widget.spec;
  String t(String k, [Map<String, Object> p = const {}]) => widget.play.t(k, p);

  @override
  void initState() {
    super.initState();
    names = [for (var i = 0; i < sp.defP; i++) widget.play.playerName(i)];
    teams = sp.teams == 2;
    secs = sp.defTime;
    unawaited(PartyStore.load().then((_) {
      if (!mounted) return;
      setState(() {
        final saved = PartyStore.names;
        if (saved.isNotEmpty) {
          final n = clampI(saved.length, sp.minP, sp.maxP);
          names = [for (var i = 0; i < n; i++) i < saved.length ? saved[i] : widget.play.playerName(i)];
        }
        custom = List.of(PartyStore.custom);
      });
    }));
  }

  void _setCount(int n) {
    final c = clampI(n, sp.minP, sp.maxP);
    setState(() {
      if (c > names.length) {
        names = [...names, for (var i = names.length; i < c; i++) widget.play.playerName(i)];
      } else {
        names = names.sublist(0, c);
      }
    });
    widget.play.sfx(Sfx.tap);
  }

  Future<String?> _ask(String title, String initial, {bool multi = false}) async {
    final c = TextEditingController(text: initial);
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLines: multi ? 8 : 1,
          maxLength: multi ? 4000 : 18,
          decoration: InputDecoration(hintText: multi ? t('customHint') : null),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: Text(t('save'))),
        ],
      ),
    );
    c.dispose();
    return r;
  }

  Future<void> _rename(int i) async {
    final r = await _ask(t('rename'), names[i]);
    if (r == null || !mounted) return;
    final v = r.trim();
    if (v.isEmpty) return;
    setState(() => names[i] = v);
  }

  Future<void> _editCustom() async {
    final r = await _ask(t('custom'), custom.join('\n'), multi: true);
    if (r == null || !mounted) return;
    setState(() {
      custom = [
        for (final l in r.split('\n'))
          if (l.trim().isNotEmpty) l.trim().length > 40 ? l.trim().substring(0, 40) : l.trim()
      ].take(300).toList();
    });
  }

  void _start() {
    PartyStore.names = List.of(names);
    PartyStore.custom = List.of(custom);
    unawaited(PartyStore.save());
    widget.play.sfx(Sfx.unlock);
    widget.onStart(PSettings(
      names: List.unmodifiable(names),
      teams: teams,
      seconds: secs,
      age: sp.age ? age : 2,
      custom: sp.custom ? List.unmodifiable(custom) : const [],
    ));
  }

  Widget _label(String s) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
        child: Text(s, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Colors.white)),
      );

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Expanded(
        child: ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      children: [
        Center(child: Text(widget.emoji, style: const TextStyle(fontSize: 54))),
        _label(t('players')),
        StudioPanel(
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(children: [
          IconButton.filledTonal(
            tooltip: '−',
            onPressed: names.length > sp.minP ? () => _setCount(names.length - 1) : null,
            icon: const Icon(Icons.remove),
          ),
          Expanded(
            child: Center(
              child: Text('${names.length}', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: StudioLook.of(context).number)),
            ),
          ),
          IconButton.filledTonal(
            tooltip: '+',
            onPressed: names.length < sp.maxP ? () => _setCount(names.length + 1) : null,
            icon: const Icon(Icons.add),
          ),
        ]),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (var i = 0; i < names.length; i++)
            ActionChip(
              avatar: CircleAvatar(
                backgroundColor: teams ? PColors.teams[i % 2] : PColors.player(i),
                child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 11)),
              ),
              label: Text(names[i]),
              tooltip: t('rename'),
              onPressed: () => _rename(i),
            ),
        ]),
        if (sp.teams == 1)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(t('teams')),
            value: teams,
            onChanged: (v) => setState(() => teams = v),
          ),
        if (teams)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(children: [
              for (var tm = 0; tm < 2; tm++)
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.all(3),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: PColors.teams[tm].withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t('team', {'n': teamLetter(tm)}),
                          style: TextStyle(fontWeight: FontWeight.w800, color: PColors.teams[tm])),
                      for (var i = tm; i < names.length; i += 2) Text(names[i], maxLines: 1, overflow: TextOverflow.ellipsis),
                    ]),
                  ),
                ),
            ]),
          ),
        if (sp.times.isNotEmpty) ...[
          _label(t('timer')),
          Wrap(spacing: 8, children: [
            for (final s in sp.times)
              ChoiceChip(
                label: Text(s <= 0 ? t('noTimer') : (s >= 120 && s % 60 == 0 ? t('min', {'n': s ~/ 60}) : t('sec', {'n': s}))),
                selected: secs == s,
                onSelected: (_) => setState(() => secs = s),
              ),
          ]),
        ],
        if (sp.age) ...[
          _label(t('age')),
          Wrap(spacing: 8, children: [
            for (var a = 0; a < 3; a++)
              ChoiceChip(
                avatar: Text(const ['🧸', '🏡', '🎉'][a]),
                label: Text(t(const ['ageKids', 'ageFamily', 'ageAll'][a])),
                selected: age == a,
                onSelected: (_) => setState(() => age = a),
              ),
          ]),
        ],
        if (sp.custom)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.edit_note),
              title: Text(t('custom')),
              subtitle: Text(custom.isEmpty ? t('customHint') : '${custom.length} · ${custom.take(4).join(', ')}',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: _editCustom,
            ),
          ),
      ],
        ),
      ),
      // Başlat düğmesi her zaman görünür kalır (küçük ekranlarda da):
      // onaylı tasarımın büyük turuncu "Hemen Oyna" düğmesi.
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: StudioButton.hot(label: t('start'), icon: Icons.play_arrow, onPressed: _start),
      ),
    ]);
  }
}

String teamLetter(int t) => t == 0 ? 'A' : 'B';

/// Renkli zemin üstünde en okunur yazı rengi (beyaz ya da koyu mürekkep).
Color pOn(Color bg) {
  final l = bg.computeLuminance();
  return 1.05 / (l + 0.05) >= (l + 0.05) / (PColors.ink.computeLuminance() + 0.05) ? Colors.white : PColors.ink;
}

/// "Telefonu ver" ekranı: gizli bilgi göstermeden önce sıradaki kişiyi çağırır.
class PassGate extends StatelessWidget {
  final String lang;
  final String name;
  final Color color;
  final String? note;
  final VoidCallback onReady;
  const PassGate({super.key, required this.lang, required this.name, required this.color, required this.onReady, this.note});

  @override
  Widget build(BuildContext context) {
    final n = note;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircleAvatar(
            radius: 44,
            backgroundColor: color,
            child: Text(name.isEmpty ? '?' : String.fromCharCode(name.runes.first).toUpperCase(),
                style: TextStyle(fontSize: 40, color: pOn(color), fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 16),
          Text(pt(lang, 'passTo', {'n': name}),
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          if (n != null) ...[
            const SizedBox(height: 8),
            Text(n, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15)),
          ],
          const SizedBox(height: 22),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size(220, 54), backgroundColor: color, foregroundColor: pOn(color)),
            onPressed: onReady,
            icon: const Icon(Icons.visibility),
            label: Text(pt(lang, 'ready'), style: const TextStyle(fontSize: 18)),
          ),
        ]),
      ),
    );
  }
}

/// Geri sayım çubuğu: son 5 saniyede tıklar, bitince [onEnd] bir kez çağrılır.
class Countdown extends StatefulWidget {
  final int seconds;
  final bool paused;
  final VoidCallback onEnd;
  final void Function(Sfx s) sfx;
  const Countdown({super.key, required this.seconds, required this.onEnd, required this.sfx, this.paused = false});

  @override
  State<Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<Countdown> {
  late int left;
  Timer? _t;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    left = widget.seconds;
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || widget.paused || _done) return;
      setState(() => left--);
      if (left <= 5 && left > 0) widget.sfx(Sfx.tap);
      if (left <= 0) {
        _done = true;
        _t?.cancel();
        widget.sfx(Sfx.lose);
        widget.onEnd();
      }
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.seconds <= 0 ? 0.0 : clampD(left / widget.seconds, 0, 1);
    final c = left <= 5 ? PColors.bad : (left <= widget.seconds ~/ 3 ? PColors.warn : PColors.good);
    return Row(children: [
      Icon(Icons.timer_outlined, color: c),
      const SizedBox(width: 6),
      SizedBox(
        width: 44,
        child: Text('${left < 0 ? 0 : left}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c)),
      ),
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(value: f, minHeight: 10, color: c, backgroundColor: c.withValues(alpha: 0.18)),
        ),
      ),
    ]);
  }
}

/// Büyük dokunma düğmesi.
class BigBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final double height;
  const BigBtn({super.key, required this.label, required this.icon, required this.color, this.onTap, this.height = 64});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: pOn(color),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(height / 2)),
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        onPressed: onTap,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 26),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          ]),
        ),
      ),
    );
  }
}

/// Kâğıt görünümlü kart: büyük emoji, ad ve isteğe bağlı alt yazı.
class CardFace extends StatelessWidget {
  final String emoji;
  final String label;
  final String? sub;
  final List<String> forbidden;
  final Color? edge;
  const CardFace({super.key, required this.emoji, required this.label, this.sub, this.forbidden = const [], this.edge});

  @override
  Widget build(BuildContext context) {
    final s = sub;
    final look = StudioLook.of(context);
    // Onaylı tasarımın kartı: paletin degradesi, vurgu (ya da takım) kenarı.
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: look.tile,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: edge ?? look.accent.withValues(alpha: 0.7), width: 3),
        boxShadow: [BoxShadow(color: (edge ?? look.accent).withValues(alpha: 0.30), blurRadius: 18, offset: const Offset(0, 6))],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (emoji.isNotEmpty) Text(emoji, style: const TextStyle(fontSize: 76)),
        if (s != null)
          Text(s, style: const TextStyle(color: kStudioSubtle, fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900)),
        ),
        if (forbidden.isNotEmpty) ...[
          const Divider(height: 22, color: Colors.white24),
          for (final f in forbidden)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(f,
                  style: const TextStyle(color: Color(0xFFFF8A78), fontSize: 21, fontWeight: FontWeight.w800),
                  textAlign: TextAlign.center),
            ),
        ],
      ]),
    );
  }
}

/// Puan tablosu (oyuncular ya da takımlar).
class ScoreList extends StatelessWidget {
  final List<String> names;
  final List<int> scores;
  final List<Color> colors;
  final int? highlight;
  const ScoreList({super.key, required this.names, required this.scores, required this.colors, this.highlight});

  @override
  Widget build(BuildContext context) {
    final order = [for (var i = 0; i < names.length; i++) i]..sort((a, b) => scores[b].compareTo(scores[a]));
    final best = scores.isEmpty ? 0 : scores[order.first];
    return Column(mainAxisSize: MainAxisSize.min, children: [
      for (final i in order)
        Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: colors[i].withValues(alpha: i == highlight ? 0.32 : 0.14),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors[i].withValues(alpha: i == highlight ? 0.9 : 0.45), width: 1.2),
          ),
          child: Row(children: [
            CircleAvatar(radius: 9, backgroundColor: colors[i]),
            const SizedBox(width: 10),
            Expanded(child: Text(names[i], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16))),
            if (scores[i] == best && best > 0) const Text('👑 '),
            Text('${scores[i]}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
          ]),
        ),
    ]);
  }
}

/// Üst bilgi çubuğu.
class PBar extends StatelessWidget {
  final String left;
  final String status;
  final List<Widget> extra;
  const PBar({super.key, this.left = '', this.status = '', this.extra = const []});

  @override
  Widget build(BuildContext context) {
    final look = StudioLook.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      height: 46,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: look.accent.withValues(alpha: 0.45), width: 1.2),
      ),
      child: Row(children: [
        if (left.isNotEmpty) Text(left, style: TextStyle(fontWeight: FontWeight.w900, color: look.number)),
        const SizedBox(width: 8),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(status, maxLines: 1, style: const TextStyle(fontWeight: FontWeight.w700, color: kStudioSubtle)),
          ),
        ),
        ...extra,
      ]),
    );
  }
}

/// Oyun sonu tablosu ve "Bitir" düğmesi.
class FinalBoard extends StatelessWidget {
  final PartiPlay play;
  final List<String> names;
  final List<int> scores;
  final List<Color> colors;
  final String? headline;
  const FinalBoard({super.key, required this.play, required this.names, required this.scores, required this.colors, this.headline});

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(18), children: [
      const Center(child: Text('🏆', style: TextStyle(fontSize: 64))),
      const SizedBox(height: 6),
      Center(
        child: StudioSheetTitle(play.t('results'), icon: Icons.emoji_events_rounded, iconColor: StudioLook.gold),
      ),
      const SizedBox(height: 12),
      ScoreList(names: names, scores: scores, colors: colors),
      const SizedBox(height: 18),
      BigBtn(
        label: play.t('finish'),
        icon: Icons.flag,
        color: PColors.good,
        onTap: () => play.finishScores(names, scores, headline: headline),
      ),
    ]);
  }
}

/// Kartın ekrandaki adı, oyuncunun dilinde (33 dil).
String cardLabel(String lang, PCard c) => Strings.pick(c.names, lang);

/// [Strings.languages] sırasındaki dil listelerinden bu dilinkini seçer (yoksa İngilizce).
T langItem<T>(List<T> byLang, String lang) {
  final i = Strings.languages.indexOf(lang);
  return i >= 0 && i < byLang.length ? byLang[i] : byLang[1];
}

/// Kart kategorisinin bu dildeki adı.
String catLabel(String lang, String cat) => pt(lang, 'cat_$cat');

/// Kendi kelimelerden ve desteden karışık oyun kartları (kendi kelimeler önce dağılır).
class PlayCard {
  final String emoji;
  final String label;
  final String? sub;
  final List<String> forbidden;
  const PlayCard(this.emoji, this.label, {this.sub, this.forbidden = const []});
}

/// Destedeki kart sırasından, yaş paketine uyanları seçip kendi kelimelerle harmanlar.
List<PlayCard> dealCards(PartiPlay play, PSettings s, List<int> order, {bool withCat = true}) {
  final out = <PlayCard>[];
  for (final i in order) {
    final c = kCards[i];
    if (c.tier > s.age) continue;
    out.add(PlayCard(c.emoji, cardLabel(play.lang, c), sub: withCat ? catLabel(play.lang, c.cat) : null));
  }
  if (s.custom.isEmpty) return out;
  final mine = List.of(s.custom);
  // Kendi kelimeler destenin içine düzenli aralıklarla yerleşir (her iki karttan biri).
  final mixed = <PlayCard>[];
  var k = 0;
  for (var i = 0; i < out.length || k < mine.length; i++) {
    if (k < mine.length && (i.isOdd || i >= out.length)) {
      mixed.add(PlayCard('✍️', mine[(k + play.seed) % mine.length]));
      k++;
    }
    if (i < out.length) mixed.add(out[i]);
  }
  return mixed;
}
