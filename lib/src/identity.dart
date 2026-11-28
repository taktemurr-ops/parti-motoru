/// Oyun içi görsel kimlik: aynı motoru kullanan oyunların her biri oyun
/// alanında kendi zemin tonunu, desenini ve panel vurgusunu taşır (kapak tek
/// başına yetmez). Dış çerçeve (merkezin onaylı tasarımı) değişmez.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/app/studio_look.dart';

/// Zemin deseni.
enum GameMotif { grid, dots, diagonal, honeycomb, waves, tiles, rings, chevrons, plus, sparkles, bricks, steps }

/// Bir oyunun oyun içi kimliği.
class GameSkin {
  final Color seed;
  final GameMotif motif;
  const GameSkin(this.seed, this.motif);

  HSLColor get _h => HSLColor.fromColor(seed);
  Color _c(double s, double l, [double shift = 0]) =>
      HSLColor.fromAHSL(1, (_h.hue + shift) % 360, s.clamp(0.0, 1.0), l.clamp(0.0, 1.0)).toColor();
  double get _s => _h.saturation < 0.2 ? 0.35 : _h.saturation.clamp(0.35, 0.8);

  /// Oyun alanının zemin renkleri (koyu: paneller öne çıkar).
  List<Color> get backdrop => [_c(_s * 0.8, 0.24, -10), _c(_s * 0.85, 0.14, -4), _c(_s * 0.9, 0.07)];

  /// Desen çizgisi rengi.
  Color get ink => _c(_s, 0.78).withValues(alpha: 0.075);

  /// Onaylı paletin oyuna özgü hali: vurgu, kart ve oynat rengi oyunun tonunda.
  StudioLook lookOver(StudioLook base) => base.copyWith(
        background: backdrop,
        accent: _c(_s.clamp(0.55, 0.85), 0.66, 6),
        card: _c(_s * 0.7, 0.30, -8),
        play: _c(_s.clamp(0.55, 0.85), 0.45),
      );
}

const Map<String, GameSkin> kGameSkins = {
  'oyun-aile-bilgi-yarismasi': GameSkin(Color(0xff2e5e8c), GameMotif.tiles),
  'oyun-ben-kimim': GameSkin(Color(0xffb0763b), GameMotif.sparkles),
  'oyun-bes-saniye': GameSkin(Color(0xff2e9c93), GameMotif.rings),
  'oyun-bomba-kelime': GameSkin(Color(0xffd9542b), GameMotif.diagonal),
  'oyun-casus-kim': GameSkin(Color(0xff3a4a5c), GameMotif.plus),
  'oyun-cevir-bakalim': GameSkin(Color(0xff2e7d7a), GameMotif.rings),
  'oyun-ciz-tahmin': GameSkin(Color(0xff3f7d6b), GameMotif.grid),
  'oyun-dogruluk-cesaret': GameSkin(Color(0xff7a4e7e), GameMotif.chevrons),
  'oyun-dort-kisilik-mini-oyunlar': GameSkin(Color(0xff1f8fb0), GameMotif.tiles),
  'oyun-emoji-hikaye': GameSkin(Color(0xff6b4e3a), GameMotif.dots),
  'oyun-emoji-ipucu': GameSkin(Color(0xff34495e), GameMotif.sparkles),
  'oyun-hafiza-zinciri': GameSkin(Color(0xff41606e), GameMotif.steps),
  'oyun-hangisini-secerdin': GameSkin(Color(0xff8a5ba6), GameMotif.diagonal),
  'oyun-hizli-parmak': GameSkin(Color(0xff8c3b2e), GameMotif.chevrons),
  'oyun-iki-dogru-bir-yalan': GameSkin(Color(0xffc2507a), GameMotif.plus),
  'oyun-isi-olcer': GameSkin(Color(0xffb5513b), GameMotif.waves),
  'oyun-isim-sehir': GameSkin(Color(0xff3a6aa8), GameMotif.grid),
  'oyun-kim-en-cok': GameSkin(Color(0xffa8507e), GameMotif.honeycomb),
  'oyun-kirik-kalem': GameSkin(Color(0xff5a4e8c), GameMotif.waves),
  'oyun-koylu-vampir': GameSkin(Color(0xff2b2f52), GameMotif.sparkles),
  'oyun-sessiz-sinema': GameSkin(Color(0xff5b4a7a), GameMotif.bricks),
  'oyun-skor-tahtasi': GameSkin(Color(0xff4d6b4a), GameMotif.grid),
  'oyun-tek-ipucu': GameSkin(Color(0xffd9a441), GameMotif.dots),
  'oyun-yasakli-kelime': GameSkin(Color(0xffc8553d), GameMotif.bricks),
};

/// Oyunun kimliği; tabloda yoksa kimlikten türetilir (her oyun yine farklı).
GameSkin gameSkinFor(String gameId) {
  final hit = kGameSkins[gameId];
  if (hit != null) return hit;
  var h = 0;
  for (final c in gameId.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return GameSkin(HSLColor.fromAHSL(1, (h % 360).toDouble(), 0.55, 0.45).toColor(), GameMotif.values[h % GameMotif.values.length]);
}

/// Oyun alanını oyunun kimliğiyle sarar: zemin, desen ve oyuna özgü palet.
Widget withGameIdentity(BuildContext context, String gameId, Widget child) {
  final skin = gameSkinFor(gameId);
  final look = skin.lookOver(StudioLook.of(context));
  final theme = Theme.of(context);
  return Theme(
    data: theme.copyWith(extensions: [...theme.extensions.values.where((e) => e is! StudioLook), look]),
    child: StudioLookScope(look: look, child: GameBackdrop(skin: skin, child: child)),
  );
}

/// Oyun alanı zemini: oyunun tonunda koyu geçiş ve ince desen.
class GameBackdrop extends StatelessWidget {
  final GameSkin skin;
  final Widget child;
  const GameBackdrop({super.key, required this.skin, required this.child});

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: skin.backdrop),
        ),
        child: CustomPaint(painter: _MotifPainter(skin.motif, skin.ink), child: child),
      );
}

class _MotifPainter extends CustomPainter {
  final GameMotif motif;
  final Color color;
  const _MotifPainter(this.motif, this.color);

  @override
  void paint(Canvas c, Size s) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final f = Paint()..color = color;
    const g = 28.0;
    switch (motif) {
      case GameMotif.grid:
        for (var x = 0.0; x < s.width; x += g) {
          c.drawLine(Offset(x, 0), Offset(x, s.height), p);
        }
        for (var y = 0.0; y < s.height; y += g) {
          c.drawLine(Offset(0, y), Offset(s.width, y), p);
        }
      case GameMotif.dots:
        for (var y = g / 2; y < s.height; y += g) {
          for (var x = g / 2; x < s.width; x += g) {
            c.drawCircle(Offset(x, y), 2.2, f);
          }
        }
      case GameMotif.diagonal:
        for (var x = -s.height; x < s.width; x += g * 0.8) {
          c.drawLine(Offset(x, s.height), Offset(x + s.height, 0), p);
        }
      case GameMotif.honeycomb:
        const r = 18.0;
        final w = r * math.sqrt(3);
        var row = 0;
        for (var y = 0.0; y < s.height + r; y += r * 1.5, row++) {
          for (var x = row.isOdd ? w / 2 : 0.0; x < s.width + w; x += w) {
            final path = Path();
            for (var k = 0; k < 6; k++) {
              final a = math.pi / 6 + k * math.pi / 3;
              final pt = Offset(x + r * math.cos(a), y + r * math.sin(a));
              if (k == 0) {
                path.moveTo(pt.dx, pt.dy);
              } else {
                path.lineTo(pt.dx, pt.dy);
              }
            }
            c.drawPath(path..close(), p);
          }
        }
      case GameMotif.waves:
        for (var y = 0.0; y < s.height; y += g) {
          final path = Path()..moveTo(0, y);
          for (var x = 0.0; x <= s.width; x += 8) {
            path.lineTo(x, y + 5 * math.sin(x / 18));
          }
          c.drawPath(path, p);
        }
      case GameMotif.tiles:
        for (var y = 8.0; y < s.height; y += g * 1.4) {
          for (var x = 8.0; x < s.width; x += g * 1.4) {
            c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y, g * 0.9, g * 0.9), const Radius.circular(5)), p);
          }
        }
      case GameMotif.rings:
        final o = Offset(s.width * 0.85, s.height * 0.12);
        for (var r = 30.0; r < s.longestSide * 1.3; r += 34) {
          c.drawCircle(o, r, p);
        }
      case GameMotif.chevrons:
        for (var y = 0.0; y < s.height; y += g) {
          final path = Path()..moveTo(0, y);
          var up = true;
          for (var x = 0.0; x <= s.width + g; x += g / 2) {
            path.lineTo(x, y + (up ? -7 : 7));
            up = !up;
          }
          c.drawPath(path, p);
        }
      case GameMotif.plus:
        for (var y = g / 2; y < s.height; y += g * 1.2) {
          for (var x = g / 2; x < s.width; x += g * 1.2) {
            c.drawLine(Offset(x - 5, y), Offset(x + 5, y), p);
            c.drawLine(Offset(x, y - 5), Offset(x, y + 5), p);
          }
        }
      case GameMotif.sparkles:
        final r = math.Random(7);
        for (var i = 0; i < (s.width * s.height / 2600).clamp(20, 400); i++) {
          final o = Offset(r.nextDouble() * s.width, r.nextDouble() * s.height);
          final k = 3 + r.nextDouble() * 5;
          final path = Path()
            ..moveTo(o.dx, o.dy - k)
            ..quadraticBezierTo(o.dx, o.dy, o.dx + k, o.dy)
            ..quadraticBezierTo(o.dx, o.dy, o.dx, o.dy + k)
            ..quadraticBezierTo(o.dx, o.dy, o.dx - k, o.dy)
            ..quadraticBezierTo(o.dx, o.dy, o.dx, o.dy - k);
          c.drawPath(path, f);
        }
      case GameMotif.bricks:
        var row = 0;
        for (var y = 0.0; y < s.height; y += g * 0.7, row++) {
          c.drawLine(Offset(0, y), Offset(s.width, y), p);
          for (var x = row.isOdd ? g : 0.0; x < s.width; x += g * 2) {
            c.drawLine(Offset(x, y), Offset(x, y + g * 0.7), p);
          }
        }
      case GameMotif.steps:
        for (var k = -s.height; k < s.width; k += g * 2.2) {
          final path = Path()..moveTo(k, s.height);
          var x = k, y = s.height;
          while (y > 0) {
            x += g * 0.7;
            path.lineTo(x, y);
            y -= g * 0.7;
            path.lineTo(x, y);
          }
          c.drawPath(path, p);
        }
    }
  }

  @override
  bool shouldRepaint(covariant _MotifPainter old) => old.motif != motif || old.color != color;
}
