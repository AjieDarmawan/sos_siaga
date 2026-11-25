import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';
import '../widgets/ui.dart';
import 'login_screen.dart';

/// Splash (mockup A1): navy radial, lambang emas dalam lingkaran putus-putus berputar, "POLMAS / DIGITAL",
/// motto, bilah muat emas, strip merah-putih di bawah. Pindah ke login ±1,8 dtk; sentuh untuk melewati.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late final _spin = AnimationController(vsync: this, duration: const Duration(seconds: 30))..repeat();
  late final _load = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..forward();
  bool _left = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1800), _go);
  }

  void _go() {
    if (_left || !mounted) return;
    _left = true;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: PK.splashOut,
        pageBuilder: (_, _, _) => const LoginScreen(),
        transitionsBuilder: (context, a, _, child) => FadeTransition(opacity: CurvedAnimation(parent: a, curve: Curves.easeOut), child: child),
      ),
    );
  }

  @override
  void dispose() {
    _spin.dispose();
    _load.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = context.reduceMotion;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: GestureDetector(
        onTap: _go,
        child: Scaffold(
          body: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.28),
                radius: 1.1,
                colors: [Color(0xFF1C4BB0), PK.navy, Color(0xFF041030)],
                stops: [0, 0.46, 1],
              ),
            ),
            child: Stack(
              children: [
                Positioned.fill(child: CustomPaint(painter: _Stripes())),
                Column(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 180,
                            height: 180,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Container(
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: RadialGradient(colors: [Color(0x47D4A82A), Color(0x00D4A82A)], stops: [0, 0.66]),
                                  ),
                                ),
                                RotationTransition(
                                  turns: reduce ? const AlwaysStoppedAnimation(0) : _spin,
                                  child: Padding(
                                    padding: const EdgeInsets.all(6),
                                    child: CustomPaint(size: const Size.square(168), painter: _DashedCircle()),
                                  ),
                                ),
                                const PolmasEmblem(size: 98),
                              ],
                            ),
                          ),
                          const SizedBox(height: 22),
                          const Text(
                            'POLMAS',
                            style: TextStyle(color: Colors.white, fontSize: 31, fontWeight: FontWeight.w800, letterSpacing: 5),
                          ),
                          const SizedBox(height: 4),
                          const Padding(
                            padding: EdgeInsets.only(left: 8),
                            child: Text(
                              'DIGITAL',
                              style: TextStyle(color: PK.gold2, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 8),
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'Melindungi · Mengayomi · Melayani',
                            style: TextStyle(color: PK.headerMute, fontSize: 12.5, letterSpacing: 0.6),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(52, 0, 52, 46 + MediaQuery.of(context).padding.bottom),
                      child: Column(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: AnimatedBuilder(
                              animation: _load,
                              builder: (_, _) => LinearProgressIndicator(
                                value: reduce ? null : 0.08 + _load.value * 0.84,
                                minHeight: 4,
                                backgroundColor: Colors.white.withValues(alpha: 0.15),
                                valueColor: const AlwaysStoppedAnimation(PK.gold),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text('Menyiapkan sistem keamanan…', style: TextStyle(color: PK.headerMute, fontSize: 12)),
                          const SizedBox(height: 24),
                          Text('v2.0 · Didukung SiagaSOS', style: TextStyle(color: PK.headerMute.withValues(alpha: 0.55), fontSize: 11)),
                        ],
                      ),
                    ),
                  ],
                ),
                const Positioned(left: 0, right: 0, bottom: 0, child: MerahPutih(height: 6)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Strip merah-putih tipis di tepi bawah.
class MerahPutih extends StatelessWidget {
  const MerahPutih({super.key, this.height = 6});
  final double height;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Column(
      children: [
        Container(height: height / 2, color: const Color(0xFFE11D2E)),
        Container(height: height / 2, color: Colors.white),
      ],
    ),
  );
}

class _Stripes extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0x09FFFFFF)
      ..strokeWidth = 2;
    for (double x = -size.height; x < size.width; x += 14) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), p);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

class _DashedCircle extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0x80D4A82A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final r = Rect.fromLTWH(0, 0, size.width, size.height);
    const n = 72;
    for (var i = 0; i < n; i++) {
      canvas.drawArc(r, i * 2 * 3.14159 / n, 3.14159 / n, false, p);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}
