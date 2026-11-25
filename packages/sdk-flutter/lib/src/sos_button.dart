import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'client.dart';
import 'models.dart';

/// Tombol SOS siap pakai: tahan [holdSeconds] detik (default dari portal) untuk mengirim,
/// cincin progres, getar saat terkirim, dan teks status laporan.
///
/// ```dart
/// SOSButton(client: sos, category: 'kriminal', onSent: (r) => ...)
/// ```
class SOSButton extends StatefulWidget {
  const SOSButton({
    super.key,
    required this.client,
    this.category = 'general',
    this.message,
    this.holdSeconds,
    this.size = 180,
    this.color = const Color(0xFFDC2626),
    this.label,
    this.onSent,
    this.onError,
    this.onCallFallback,
  });

  final SiagaSOS client;
  final String category;
  final String? message;

  /// Override durasi tahan; null = ikut pengaturan app di portal.
  final int? holdSeconds;
  final double size;
  final Color color;
  final String? label;
  final void Function(ActiveReport report)? onSent;
  final void Function(SiagaSOSError error)? onError;

  /// Dipanggil saat pengguna menekan "Telepon `nomor`" (mis. pakai url_launcher `tel:`).
  final void Function(String phone)? onCallFallback;

  @override
  State<SOSButton> createState() => _SOSButtonState();
}

class _SOSButtonState extends State<SOSButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _hold = AnimationController(vsync: this);
  SdkConfig? _cfg;
  ActiveReport? _report;
  bool _sending = false;
  StreamSubscription<ActiveReport>? _sub;

  @override
  void initState() {
    super.initState();
    widget.client
        .getConfig()
        .then((c) => mounted ? setState(() => _cfg = c) : null)
        .catchError((_) {});
    _sub = widget.client.status.listen((r) {
      if (mounted && (_report == null || _report!.localId == r.localId))
        setState(() => _report = r);
    });
    _hold.addStatusListener((s) {
      if (s == AnimationStatus.completed) _fire();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _hold.dispose();
    super.dispose();
  }

  int get _seconds => widget.holdSeconds ?? _cfg?.holdSeconds ?? 3;
  bool get _active => _report != null && !_report!.status.isTerminal;

  Future<void> _fire() async {
    setState(() => _sending = true);
    try {
      final r = await widget.client
          .trigger(category: widget.category, message: widget.message);
      HapticFeedback.heavyImpact();
      if (mounted) setState(() => _report = r);
      if (r.id != null) widget.onSent?.call(r);
    } on SiagaSOSError catch (e) {
      widget.onError?.call(e);
    } finally {
      if (mounted) setState(() => _sending = false);
      _hold.reset();
    }
  }

  void _down() {
    if (_active || _sending) return;
    HapticFeedback.selectionClick();
    _hold.duration = Duration(seconds: _seconds);
    _hold.forward(from: 0);
  }

  void _up() {
    if (_hold.isAnimating) _hold.reverse();
  }

  String get _statusText {
    if (_sending) return 'Mengirim…';
    final r = _report;
    if (r == null) return 'Tahan $_seconds detik';
    return r.statusMessage ??
        switch (r.status) {
          SosStatus.queued => 'Menunggu sinyal…',
          SosStatus.open => 'Terkirim. Menunggu petugas…',
          SosStatus.acknowledged => 'Petugas menerima laporan',
          SosStatus.inProgress => 'Petugas sedang menangani',
          SosStatus.resolved => 'Selesai ditangani',
          SosStatus.cancelled => 'Dibatalkan',
          SosStatus.falseAlarm => 'Ditandai alarm palsu',
        };
  }

  @override
  Widget build(BuildContext context) {
    final cfg = _cfg;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Semantics(
        button: true,
        label:
            'Tombol darurat. Tahan $_seconds detik untuk mengirim laporan SOS.',
        value: _statusText,
        child: GestureDetector(
          onTapDown: (_) => _down(),
          onTapUp: (_) => _up(),
          onTapCancel: _up,
          child: AnimatedBuilder(
            animation: _hold,
            builder: (context, _) => SizedBox.square(
              dimension: widget.size,
              child: CustomPaint(
                painter:
                    _RingPainter(progress: _hold.value, color: widget.color),
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: widget.size * (0.78 - _hold.value * 0.05),
                    height: widget.size * (0.78 - _hold.value * 0.05),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _active ? const Color(0xFF475569) : widget.color,
                      boxShadow: [
                        BoxShadow(
                            color: widget.color.withValues(alpha: 0.45),
                            blurRadius: 24,
                            spreadRadius: 2)
                      ],
                    ),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(16),
                    child: _sending
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(
                            _active
                                ? _statusText
                                : (widget.label ?? cfg?.buttonText ?? 'SOS'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: _active ? 15 : widget.size * 0.17),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 10),
      if (!_active)
        Text(_statusText, style: Theme.of(context).textTheme.bodyMedium),
      if (widget.client.mode == SosMode.test)
        Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('MODE TEST',
                style: TextStyle(
                    color: Colors.amber.shade800,
                    fontWeight: FontWeight.w700,
                    fontSize: 11))),
      if (_report?.status == SosStatus.open)
        TextButton(
            onPressed: () =>
                widget.client.cancel(_report!.localId, reason: 'Salah tekan'),
            child: const Text('Batalkan (salah tekan)')),
      if (cfg != null && cfg.recipientText.isNotEmpty)
        Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(cfg.recipientText,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall)),
      if (cfg != null && widget.onCallFallback != null)
        TextButton(
            onPressed: () => widget.onCallFallback!(cfg.fallbackPhone),
            child: Text('Darurat polisi? Telepon ${cfg.fallbackPhone}')),
    ]);
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.color});
  final double progress;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 5;
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = color.withValues(alpha: 0.18)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8);
    if (progress > 0) {
      canvas.drawArc(
          Rect.fromCircle(center: c, radius: r),
          -math.pi / 2,
          2 * math.pi * progress,
          false,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 8
            ..strokeCap = StrokeCap.round);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color;
}
