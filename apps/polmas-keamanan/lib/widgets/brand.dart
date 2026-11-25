import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Logo perisai Polmas Keamanan: sirene di atas, penanda lokasi di bawah.
/// [onRed] = garis putih untuk di atas latar merah; selain itu perisai merah terisi untuk latar putih.
class PolmasLogo extends StatelessWidget {
  const PolmasLogo({super.key, this.size = 88, this.onRed = false});
  final double size;
  final bool onRed;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Logo Polmas Keamanan',
    child: SizedBox(
      width: size,
      height: size * 1.14,
      child: CustomPaint(painter: _ShieldPainter(onRed)),
    ),
  );
}

class _ShieldPainter extends CustomPainter {
  _ShieldPainter(this.onRed);
  final bool onRed;

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final stroke = w * 0.06;
    final shield = Path()
      ..moveTo(w * 0.5, stroke / 2)
      ..cubicTo(w * 0.68, h * 0.1, w * 0.85, h * 0.12, w - stroke / 2, h * 0.12)
      ..lineTo(w - stroke / 2, h * 0.48)
      ..cubicTo(w - stroke / 2, h * 0.76, w * 0.72, h * 0.9, w * 0.5, h - stroke / 2)
      ..cubicTo(w * 0.28, h * 0.9, stroke / 2, h * 0.76, stroke / 2, h * 0.48)
      ..lineTo(stroke / 2, h * 0.12)
      ..cubicTo(w * 0.15, h * 0.12, w * 0.32, h * 0.1, w * 0.5, stroke / 2)
      ..close();

    final ink = Colors.white;
    final hole = PK.red;
    if (onRed) {
      canvas.drawPath(shield, Paint()..color = Colors.white.withValues(alpha: 0.12));
      canvas.drawPath(
        shield,
        Paint()
          ..color = ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeJoin = StrokeJoin.round,
      );
    } else {
      canvas.drawShadow(shield, const Color(0x66A80F15), 8, false);
      canvas.drawPath(
        shield,
        Paint()
          ..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [PK.red, PK.redDark]).createShader(Offset.zero & s),
      );
    }

    // sirene: kubah + alas + sinar
    final cx = w * 0.5;
    final domeTop = h * 0.22, domeBottom = h * 0.4, domeW = w * 0.26;
    final dome = Path()
      ..moveTo(cx - domeW / 2, domeBottom)
      ..lineTo(cx - domeW / 2, domeTop + domeW / 2)
      ..arcToPoint(Offset(cx + domeW / 2, domeTop + domeW / 2), radius: Radius.circular(domeW / 2))
      ..lineTo(cx + domeW / 2, domeBottom)
      ..close();
    canvas.drawPath(dome, Paint()..color = ink);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx, domeBottom + h * 0.02), width: domeW * 1.45, height: h * 0.04), Radius.circular(h * 0.01)),
      Paint()..color = ink,
    );
    final ray = Paint()
      ..color = ink
      ..strokeWidth = w * 0.035
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx, h * 0.13), Offset(cx, h * 0.17), ray);
    for (final d in [-1, 1]) {
      canvas.drawLine(Offset(cx + d * w * 0.2, h * 0.2), Offset(cx + d * w * 0.24, h * 0.17), ray);
      canvas.drawLine(Offset(cx + d * w * 0.24, h * 0.3), Offset(cx + d * w * 0.29, h * 0.3), ray);
    }

    // penanda lokasi
    final pc = Offset(cx, h * 0.6);
    final pr = w * 0.14;
    final pin = Path()
      ..addOval(Rect.fromCircle(center: pc, radius: pr))
      ..moveTo(pc.dx - pr * 0.78, pc.dy + pr * 0.62)
      ..lineTo(pc.dx, h * 0.82)
      ..lineTo(pc.dx + pr * 0.78, pc.dy + pr * 0.62)
      ..close();
    canvas.drawPath(pin, Paint()..color = ink);
    canvas.drawCircle(pc, pr * 0.42, Paint()..color = onRed ? hole : PK.redDark);
  }

  @override
  bool shouldRepaint(_ShieldPainter old) => old.onRed != onRed;
}

/// Logo + tulisan "Polmas / Keamanan" putih untuk header merah.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.logoSize = 56});
  final double logoSize;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      PolmasLogo(size: logoSize, onRed: true),
      SizedBox(width: logoSize * 0.28),
      ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Polmas',
              style: TextStyle(color: Colors.white, fontSize: logoSize * 0.46, fontWeight: FontWeight.w800, height: 1.05),
            ),
            Text(
              'Keamanan',
              style: TextStyle(color: Colors.white, fontSize: logoSize * 0.46, fontWeight: FontWeight.w800, fontStyle: FontStyle.italic, height: 1.05),
            ),
          ],
        ),
      ),
    ],
  );
}

/// Header merah bergelombang (gradasi merah + lapisan gelombang tipis, tepi bawah melengkung ke putih).
class RedWaveHeader extends StatelessWidget {
  const RedWaveHeader({super.key, required this.height, this.child, this.background});
  final double height;
  final Widget? child;

  /// Warna di bawah gelombang (latar halaman).
  final Color? background;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: Stack(
      children: [
        Positioned.fill(child: CustomPaint(painter: _WavePainter(background ?? context.surface))),
        if (child != null) Positioned.fill(child: child!),
      ],
    ),
  );
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.bg);
  final Color bg;
  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    // badan merah dengan tepi bawah bergelombang
    final body = Path()
      ..lineTo(w, 0)
      ..lineTo(w, h * 0.78)
      ..cubicTo(w * 0.78, h * 0.98, w * 0.52, h * 0.74, w * 0.3, h * 0.86)
      ..cubicTo(w * 0.16, h * 0.93, w * 0.06, h * 0.9, 0, h * 0.84)
      ..close();
    canvas.drawPath(
      body,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE02A30), PK.red, PK.redDark],
        ).createShader(Offset.zero & s),
    );
    // lapisan gelombang lembut di dalam merah
    final soft = Paint()..color = Colors.white.withValues(alpha: 0.07);
    canvas.drawPath(
      Path()
        ..moveTo(0, h * 0.45)
        ..cubicTo(w * 0.3, h * 0.3, w * 0.55, h * 0.62, w, h * 0.4)
        ..lineTo(w, h * 0.7)
        ..cubicTo(w * 0.6, h * 0.86, w * 0.3, h * 0.6, 0, h * 0.72)
        ..close(),
      soft,
    );
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.4, 0)
        ..cubicTo(w * 0.6, h * 0.18, w * 0.8, h * 0.1, w, h * 0.22)
        ..lineTo(w, 0)
        ..close(),
      Paint()..color = Colors.black.withValues(alpha: 0.06),
    );
    // garis putih tipis di tepi gelombang (aksen merah putih)
    canvas.drawPath(
      Path()
        ..moveTo(0, h * 0.84)
        ..cubicTo(w * 0.06, h * 0.9, w * 0.16, h * 0.93, w * 0.3, h * 0.86)
        ..cubicTo(w * 0.52, h * 0.74, w * 0.78, h * 0.98, w, h * 0.78),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.bg != bg;
}

/// Ilustrasi permukiman + bendera merah putih di bawah layar login (dekoratif, merah muda pudar).
class SkylineIllustration extends StatelessWidget {
  const SkylineIllustration({super.key, this.height = 150, this.grey = false});
  final double height;

  /// Abu-abu (splash) alih-alih merah muda (login).
  final bool grey;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _SkylinePainter(context.isDark, grey)),
    ),
  );
}

class _SkylinePainter extends CustomPainter {
  _SkylinePainter(this.dark, this.grey);
  final bool dark, grey;
  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final a = dark ? 0.35 : 1.0;
    final back = Paint()..color = (grey ? const Color(0xFFE6EAF0) : const Color(0xFFF9D5D8)).withValues(alpha: a);
    final front = Paint()..color = (grey ? const Color(0xFFCDD4DE) : const Color(0xFFF2AEB3)).withValues(alpha: a);
    final win = Paint()..color = (dark ? PK.darkBg : Colors.white).withValues(alpha: 0.85);
    final ground = h * 0.96;

    void house(double x, double bw, double bh, Paint p, {bool tall = false}) {
      final top = ground - bh;
      if (tall) {
        canvas.drawRect(Rect.fromLTWH(x, top, bw, bh), p);
      } else {
        final roof = bw * 0.42;
        canvas.drawRect(Rect.fromLTWH(x, top + roof, bw, bh - roof), p);
        canvas.drawPath(
          Path()
            ..moveTo(x - bw * 0.08, top + roof)
            ..lineTo(x + bw / 2, top)
            ..lineTo(x + bw * 1.08, top + roof)
            ..close(),
          p,
        );
      }
      // jendela
      final cols = (bw / 14).floor().clamp(1, 4);
      final rows = tall ? (bh / 22).floor().clamp(1, 5) : 1;
      final gw = bw / (cols * 2 + 1);
      for (var r = 0; r < rows; r++) {
        for (var c = 0; c < cols; c++) {
          final wy = tall ? top + 8 + r * 20 : ground - bh * 0.42;
          canvas.drawRect(Rect.fromLTWH(x + gw * (c * 2 + 1), wy, gw, math.min(10, bh * 0.16)), win);
        }
      }
      if (!tall) canvas.drawRect(Rect.fromLTWH(x + bw / 2 - bw * 0.09, ground - bh * 0.24, bw * 0.18, bh * 0.24), win);
    }

    void tree(double x, double r, Paint p) {
      canvas.drawRect(Rect.fromLTWH(x - 1.5, ground - r * 2.2, 3, r * 2.2), p);
      canvas.drawCircle(Offset(x, ground - r * 2.4), r, p);
    }

    // lapisan belakang
    house(w * 0.02, w * 0.12, h * 0.38, back);
    house(w * 0.3, w * 0.1, h * 0.62, back, tall: true);
    house(w * 0.62, w * 0.14, h * 0.45, back);
    house(w * 0.86, w * 0.12, h * 0.5, back, tall: true);
    tree(w * 0.2, h * 0.08, back);
    tree(w * 0.55, h * 0.07, back);

    // lapisan depan
    tree(w * 0.05, h * 0.09, front);
    house(w * 0.1, w * 0.13, h * 0.45, front);
    house(w * 0.27, w * 0.15, h * 0.58, front);
    house(w * 0.46, w * 0.11, h * 0.36, front);
    house(w * 0.6, w * 0.16, h * 0.52, front, tall: true);
    house(w * 0.8, w * 0.14, h * 0.42, front);
    tree(w * 0.97, h * 0.08, front);

    // tiang & bendera merah putih
    final px = w * 0.57;
    canvas.drawRect(Rect.fromLTWH(px, ground - h * 0.95, 2.5, h * 0.95), front);
    final fx = px + 2.5, fy = ground - h * 0.95, fw = w * 0.1, fh = h * 0.14;
    Path half(double y0, double y1) => Path()
      ..moveTo(fx, y0)
      ..quadraticBezierTo(fx + fw * 0.5, y0 - fh * 0.15, fx + fw, y0 + fh * 0.05)
      ..lineTo(fx + fw, y1 + fh * 0.05)
      ..quadraticBezierTo(fx + fw * 0.5, y1 - fh * 0.15, fx, y1)
      ..close();
    canvas.drawPath(half(fy, fy + fh / 2), Paint()..color = PK.red.withValues(alpha: dark ? 0.6 : 0.75));
    canvas.drawPath(half(fy + fh / 2, fy + fh), Paint()..color = (dark ? const Color(0xFF94A3B8) : Colors.white));
    canvas.drawPath(
      half(fy, fy + fh),
      Paint()
        ..color = front.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    canvas.drawRect(Rect.fromLTWH(0, ground, w, h - ground), front);
  }

  @override
  bool shouldRepaint(_SkylinePainter old) => old.dark != dark || old.grey != grey;
}
