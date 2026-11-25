import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import 'incident_screen.dart';

/// Panggilan SOS masuk (FR-04): layar penuh merah tua, cincin berdenyut, ikon sirene bergoyang ±8°, bunyi & getar.
/// Terima → membuka detail insiden (petugas: status otomatis "Diterima"). Abaikan → tidak berdering lagi di perangkat ini.
class SosCallScreen extends StatefulWidget {
  const SosCallScreen({super.key, required this.report});
  final Report report;
  @override
  State<SosCallScreen> createState() => _SosCallScreenState();
}

class _SosCallScreenState extends State<SosCallScreen> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(vsync: this, duration: PK.sosPulse)..repeat();
  final _player = AudioPlayer();
  Timer? _vibe;
  Timer? _timeout;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _ring();
    // Berhenti berdering setelah 60 dtk; SOS tetap ada di daftar & notifikasi.
    _timeout = Timer(const Duration(seconds: 60), _stopRing);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final r = widget.report;
      SemanticsService.sendAnnouncement(
        View.of(context),
        'Peringatan! Panggilan SOS masuk dari ${r.reporterName}, ${r.sourceLabel}',
        TextDirection.ltr,
        assertiveness: Assertiveness.assertive,
      );
    });
  }

  Future<void> _ring() async {
    // Notifikasi dimatikan di Profil: layar panggilan tetap tampil, tanpa sirene & getar.
    if (!AppScope.read(context).notifSound) return;
    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            usageType: AndroidUsageType.alarm,
            contentType: AndroidContentType.sonification,
            audioFocus: AndroidAudioFocus.gainTransient,
            stayAwake: true,
          ),
          iOS: AudioContextIOS(category: AVAudioSessionCategory.playback),
        ),
      );
      await _player.play(AssetSource('sounds/sos_siren.mp3'), volume: 1);
    } catch (_) {
      // Bunyi gagal tidak boleh menghalangi layar panggilan.
    }
    _vibe = Timer.periodic(const Duration(milliseconds: 900), (_) => HapticFeedback.heavyImpact());
  }

  void _stopRing() {
    _vibe?.cancel();
    _player.stop();
  }

  Future<void> _answer(bool accept) async {
    if (_busy) return;
    setState(() => _busy = true);
    _stopRing();
    final state = AppScope.read(context);
    final nav = Navigator.of(context);
    try {
      await state.api.post('/reports/${widget.report.id}/call', {'action': accept ? 'accepted' : 'ignored'});
      if (accept && state.me?.canRespond == true) {
        await state.api.post('/reports/${widget.report.id}/responses', {'action': 'terima'}).catchError((_) => null);
      }
      state.bump();
    } on ApiException catch (e) {
      if (mounted && !e.isNetwork) showToast(context, e.message, error: true);
    }
    if (!mounted) return;
    if (accept) {
      nav.pushReplacement(MaterialPageRoute(builder: (_) => IncidentScreen(id: widget.report.id)));
    } else {
      nav.pop();
    }
  }

  @override
  void dispose() {
    _stopRing();
    _timeout?.cancel();
    _player.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.report;
    final reduce = context.reduceMotion;
    final dist = r.distanceFrom(AppScope.of(context).here);
    const white = Colors.white;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: PK.redDark,
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFC8141B), PK.redDark, Color(0xFF8E0B10)]),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.notifications_active_rounded, color: white, size: 28),
                      const SizedBox(width: 10),
                      const Text(
                        'SOS Masuk',
                        style: TextStyle(color: white, fontSize: 26, fontWeight: FontWeight.w800),
                      ),
                      if (r.isDemo) ...[const SizedBox(width: 10), const DemoTag()],
                    ],
                  ),
                  const Spacer(),
                  // lingkaran berdenyut + ikon sirene bergoyang ±8°
                  SizedBox(
                    width: 250,
                    height: 250,
                    child: AnimatedBuilder(
                      animation: _pulse,
                      builder: (_, _) {
                        final v = reduce ? 0.0 : _pulse.value;
                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: 230 + 20 * v,
                              height: 230 + 20 * v,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: white.withValues(alpha: 0.07 * (1 - v) + 0.04),
                              ),
                            ),
                            Container(
                              width: 180,
                              height: 180,
                              decoration: BoxDecoration(shape: BoxShape.circle, color: white.withValues(alpha: 0.12)),
                            ),
                            Container(
                              width: 132,
                              height: 132,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF04A4F), PK.red]),
                                border: Border.all(color: white.withValues(alpha: 0.35), width: 3),
                                boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 10))],
                              ),
                              child: Transform.rotate(
                                angle: reduce ? 0 : math.sin(_pulse.value * math.pi * 4) * 8 * math.pi / 180,
                                child: const Icon(Icons.notifications_active_rounded, size: 70, color: white, semanticLabel: 'Sirene'),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    r.reporterName,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: const TextStyle(color: white, fontSize: 32, fontWeight: FontWeight.w800, height: 1.15),
                  ),
                  const SizedBox(height: 12),
                  _Line(icon: Icons.person_rounded, text: [r.sourceLabel, ?r.sourcePlace].join(' · ')),
                  const SizedBox(height: 6),
                  _Line(icon: Icons.location_on_rounded, text: r.placeLine.isEmpty ? 'Lokasi sedang dibaca…' : r.placeLine),
                  if (r.message != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      '"${r.message}"',
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: white.withValues(alpha: 0.9), fontSize: 15, fontStyle: FontStyle.italic),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(color: white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(999)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(dist != null ? Icons.near_me_rounded : Icons.schedule_rounded, color: white, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          dist?.replaceFirst('± ', '') ?? fmtRelative(r.createdAt),
                          style: const TextStyle(color: white, fontSize: 18, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  _CallButton(
                    label: 'Terima',
                    icon: Icons.check_rounded,
                    color: const Color(0xFF22B24C),
                    loading: _busy,
                    onTap: _busy ? null : () => _answer(true),
                  ),
                  const SizedBox(height: 14),
                  _CallButton(label: 'Abaikan', icon: Icons.close_rounded, color: const Color(0xFF8C93A1), onTap: _busy ? null : () => _answer(false)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(icon, color: Colors.white, size: 22),
      const SizedBox(width: 8),
      Flexible(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w500),
        ),
      ),
    ],
  );
}

/// Tombol panggilan lebar penuh, tinggi 60, radius 18.
class _CallButton extends StatelessWidget {
  const _CallButton({required this.label, required this.icon, required this.color, this.onTap, this.loading = false});
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final bool loading;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    child: SizedBox(
      height: 60,
      width: double.infinity,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          disabledBackgroundColor: color.withValues(alpha: 0.6),
          elevation: 4,
          shadowColor: Colors.black38,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        child: loading
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: Colors.white, size: 28),
                  const SizedBox(width: 10),
                  Text(
                    label,
                    style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
      ),
    ),
  );
}
