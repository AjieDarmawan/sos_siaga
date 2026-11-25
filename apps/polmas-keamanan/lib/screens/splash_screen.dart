import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../widgets/brand.dart';
import 'login_screen.dart';

/// Splash: latar putih, bendera merah putih berkibar di belakang logo perisai, "Polmas Keamanan",
/// "Aman bersama masyarakat", siluet kota abu-abu di bawah. Pindah ke login setelah ±1,5 dtk; sentuh untuk melewati.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late final _wave = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat();
  late final _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..forward();
  bool _left = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1500), _go);
  }

  void _go() {
    if (_left || !mounted) return;
    _left = true;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: PK.splashOut,
        pageBuilder: (_, _, _) => const LoginScreen(),
        transitionsBuilder: (context, a, _, child) {
          final c = CurvedAnimation(parent: a, curve: Curves.easeOut);
          if (context.reduceMotion) return FadeTransition(opacity: c, child: child);
          return FadeTransition(
            opacity: c,
            child: SlideTransition(
              position: Tween(begin: const Offset(0, 0.08), end: Offset.zero).animate(c),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _wave.dispose();
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = context.reduceMotion;
    final size = MediaQuery.of(context).size;
    return GestureDetector(
      onTap: _go,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          children: [
            // bendera berkibar melintang di belakang logo
            Positioned(
              top: size.height * 0.08,
              left: -size.width * 0.1,
              right: -size.width * 0.1,
              height: size.height * 0.3,
              child: ExcludeSemantics(
                child: Transform.rotate(
                  angle: -0.12,
                  child: AnimatedBuilder(
                    animation: _wave,
                    builder: (_, _) => CustomPaint(painter: _BigFlagPainter(reduce ? 0 : _wave.value)),
                  ),
                ),
              ),
            ),
            const Positioned(left: 0, right: 0, bottom: 0, child: SkylineIllustration(height: 170, grey: true)),
            SafeArea(
              child: Column(
                children: [
                  SizedBox(height: size.height * 0.16),
                  FadeTransition(
                    opacity: CurvedAnimation(parent: _intro, curve: Curves.easeOut),
                    child: ScaleTransition(
                      scale: Tween(begin: reduce ? 1.0 : 0.88, end: 1.0).animate(CurvedAnimation(parent: _intro, curve: Curves.easeOutBack)),
                      child: Column(
                        children: [
                          const PolmasLogo(size: 150),
                          const SizedBox(height: 18),
                          const Text(
                            'Polmas',
                            style: TextStyle(fontSize: 46, height: 1.05, fontWeight: FontWeight.w900, color: PK.navy),
                          ),
                          const Text(
                            'Keamanan',
                            style: TextStyle(fontSize: 46, height: 1.05, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic, color: PK.red),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Aman bersama masyarakat',
                            style: TextStyle(fontSize: 18, color: PK.text.withValues(alpha: 0.85), fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  // indikator memuat (pil merah + titik abu)
                  ExcludeSemantics(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 28,
                          height: 6,
                          decoration: BoxDecoration(color: PK.red, borderRadius: BorderRadius.circular(3)),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          width: 14,
                          height: 6,
                          decoration: BoxDecoration(color: const Color(0xFFCBD2DC), borderRadius: BorderRadius.circular(3)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bendera lebar berkibar: pita merah di atas, putih di bawah, gelombang sinus + bayangan lipatan.
class _BigFlagPainter extends CustomPainter {
  _BigFlagPainter(this.t);
  final double t;
  @override
  void paint(Canvas canvas, Size s) {
    const steps = 48;
    double wave(double u) => math.sin(u * math.pi * 2.2 - t * math.pi * 2) * s.height * 0.07;
    Path band(double top, double bottom) {
      final p = Path();
      for (var i = 0; i <= steps; i++) {
        final x = s.width * i / steps;
        i == 0 ? p.moveTo(x, top + wave(i / steps)) : p.lineTo(x, top + wave(i / steps));
      }
      for (var i = steps; i >= 0; i--) {
        p.lineTo(s.width * i / steps, bottom + wave(i / steps));
      }
      return p..close();
    }

    canvas.drawPath(
      band(s.height * 0.1, s.height * 0.48),
      Paint()..shader = const LinearGradient(colors: [PK.redDark, PK.red, Color(0xFFE53935)]).createShader(Offset.zero & s),
    );
    canvas.drawPath(band(s.height * 0.48, s.height * 0.86), Paint()..color = const Color(0xFFF3F4F7));
    for (var i = 0; i < steps; i++) {
      final shade = math.sin((i / steps) * math.pi * 2.2 - t * math.pi * 2);
      if (shade > 0) continue;
      final x = s.width * i / steps;
      canvas.drawRect(
        Rect.fromLTWH(x, s.height * 0.1 + wave(i / steps), s.width / steps + 1, s.height * 0.76),
        Paint()..color = Colors.black.withValues(alpha: -shade * 0.05),
      );
    }
  }

  @override
  bool shouldRepaint(_BigFlagPainter old) => old.t != t;
}
