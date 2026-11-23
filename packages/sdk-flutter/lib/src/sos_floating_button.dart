import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'client.dart';
import 'models.dart';

/// Hasil rekaman TKP dari app host (kamera/mikrofon disediakan app, SDK tidak membawa plugin).
class CapturedMedia {
  const CapturedMedia({required this.bytes, required this.contentType, this.durationS});
  final Uint8List bytes;
  final String contentType;
  final double? durationS;
}

/// Dipanggil saat pengguna menekan Foto / Video / Suara setelah SOS terkirim.
/// Kembalikan null bila pengguna membatalkan.
typedef MediaCapture = Future<CapturedMedia?> Function(BuildContext context, MediaKind kind);

/// Tombol SOS kecil yang melayang di atas semua halaman.
///
/// Ketuk → 4 aksi bertumpuk: **Kirim SOS** (tahan N detik), **Telepon 110**, **Telepon 112**,
/// dan **Laporan pengaduan** (form non-darurat: kategori, uraian, foto opsional → [SiagaSOS.complain]).
///
/// Pasang sekali di root app:
/// ```dart
/// MaterialApp(
///   builder: (context, child) => SOSFloatingButton(
///     client: sos,
///     onCall: (phone) => launchUrl(Uri(scheme: 'tel', path: phone)),
///     onCapture: (context, kind) => pickMedia(kind), // opsional, mis. image_picker
///     child: child!,
///   ),
/// )
/// ```
/// Tombol bisa digeser, menempel ke tepi kiri/kanan, dan posisinya diingat.
/// Area di luar tombol tidak menangkap sentuhan.
class SOSFloatingButton extends StatefulWidget {
  const SOSFloatingButton({
    super.key,
    required this.client,
    required this.child,
    this.category = 'general',
    this.message,
    this.holdSeconds,
    this.onCall,
    this.secondaryPhone = '112',
    this.onCapture,
    this.onSent,
    this.onError,
    this.size = 48,
    this.color = const Color(0xFFDC2626),
    this.visible = true,
    this.positionKey = 'siagasos.fab.position',
    this.complaint = true,
    this.onComplaintSent,
    this.captureKinds = MediaKind.values,
    this.sosLabel,
    this.sosColors,
    this.callLabel = 'Telepon',
    this.history = true,
  });

  final SiagaSOS client;
  final Widget child;
  final String category;
  final String? message;
  /// Override durasi tahan; null = ikut pengaturan app di portal.
  final int? holdSeconds;
  /// Menelepon nomor darurat (mis. url_launcher `tel:`). Null = tombol telepon disembunyikan.
  final void Function(String phone)? onCall;
  /// Nomor darurat kedua di menu. Nomor pertama memakai `fallback_phone` dari portal (default 110).
  final String? secondaryPhone;
  /// Rekam TKP. Null = tombol Foto / Video / Suara disembunyikan.
  final MediaCapture? onCapture;
  final void Function(ActiveReport report)? onSent;
  final void Function(SiagaSOSError error)? onError;
  final double size;
  final Color color;
  /// false = tombol disembunyikan (mis. di halaman login) tanpa melepas widget.
  final bool visible;
  /// Kunci SharedPreferences untuk posisi tombol.
  final String positionKey;
  /// Tampilkan menu "Laporan pengaduan". Kategori dari `complaint_categories` di portal.
  final bool complaint;
  final void Function(ActiveReport report)? onComplaintSent;
  /// Jenis lampiran yang ditawarkan setelah SOS terkirim (mis. tanpa [MediaKind.audio] bila app tidak punya perekam).
  final List<MediaKind> captureKinds;
  /// Label tombol kirim SOS di menu (mis. 'EWS Alert'). Null = "Kirim `button_text` portal".
  final String? sosLabel;
  /// Gradien tombol kirim SOS di menu (mis. kuning EWS). Null = turunan [color].
  final List<Color>? sosColors;
  /// Awalan tombol telepon: `"$callLabel 110"` (mis. 'Call').
  final String callLabel;
  /// Tampilkan menu "Riwayat laporan" (status SOS & pengaduan yang pernah dikirim dari perangkat ini).
  final bool history;

  @override
  State<SOSFloatingButton> createState() => _SOSFloatingButtonState();
}

const double _kEdge = 12;
const double _kPanelWidth = 248;
const double _kActionWidth = 196;

class _SOSFloatingButtonState extends State<SOSFloatingButton> with SingleTickerProviderStateMixin {
  late final AnimationController _hold = AnimationController(vsync: this);

  /// Sisi tempel: false = kanan, true = kiri. [_yFrac] = posisi vertikal 0 (atas) .. 1 (bawah).
  bool _left = false;
  double _yFrac = 1;
  Offset? _dragPos;

  bool _open = false;
  bool _sending = false;
  SdkConfig? _cfg;
  ActiveReport? _report;
  StreamSubscription<ActiveReport>? _sub;
  MediaKind? _uploading;
  double _uploadRatio = 0;
  final _attached = <MediaKind, int>{};
  String? _notice;
  /// Lembar dari bawah (pengaduan / riwayat).
  OverlayEntry? _sheet;

  @override
  void initState() {
    super.initState();
    widget.client.getConfig().then((c) => mounted ? setState(() => _cfg = c) : null).catchError((_) {});
    _sub = widget.client.status.listen((r) {
      if (!mounted || r.kind != ReportKind.sos) return;
      if (_report == null || _report!.localId == r.localId) setState(() => _report = r);
    });
    _hold.addStatusListener((s) {
      if (s == AnimationStatus.completed) _fire();
    });
    _loadPosition();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _hold.dispose();
    super.dispose();
  }

  Future<void> _loadPosition() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(widget.positionKey);
      if (raw == null || !mounted) return;
      final parts = raw.split(',');
      setState(() {
        _left = parts[0] == 'L';
        _yFrac = (double.tryParse(parts[1]) ?? 1).clamp(0.0, 1.0);
      });
    } catch (_) {}
  }

  Future<void> _savePosition() async {
    try {
      await (await SharedPreferences.getInstance()).setString(widget.positionKey, '${_left ? 'L' : 'R'},${_yFrac.toStringAsFixed(4)}');
    } catch (_) {}
  }

  int get _seconds => widget.holdSeconds ?? _cfg?.holdSeconds ?? 3;
  bool get _active => _report != null && !_report!.status.isTerminal;

  Future<void> _fire() async {
    setState(() => _sending = true);
    try {
      final r = await widget.client.trigger(category: widget.category, message: widget.message);
      HapticFeedback.heavyImpact();
      if (mounted) setState(() => _report = r);
      if (r.id != null) widget.onSent?.call(r);
    } on SiagaSOSError catch (e) {
      if (mounted) setState(() => _notice = e.message);
      widget.onError?.call(e);
    } finally {
      if (mounted) setState(() => _sending = false);
      _hold.reset();
    }
  }

  Future<void> _capture(MediaKind kind) async {
    final r = _report;
    final capture = widget.onCapture;
    if (r == null || capture == null || _uploading != null) return;
    final media = await capture(context, kind);
    if (media == null || !mounted) return;
    setState(() {
      _uploading = kind;
      _uploadRatio = 0;
      _notice = null;
    });
    try {
      await widget.client.attach(r.id ?? r.localId, media.bytes,
          contentType: media.contentType,
          durationS: media.durationS,
          onProgress: (p) => mounted ? setState(() => _uploadRatio = p) : null);
      if (mounted) setState(() => _attached[kind] = (_attached[kind] ?? 0) + 1);
    } on SiagaSOSError catch (e) {
      if (mounted) setState(() => _notice = e.message);
      widget.onError?.call(e);
    } catch (_) {
      if (mounted) setState(() => _notice = 'Lampiran gagal diunggah. Coba lagi.');
    } finally {
      if (mounted) setState(() => _uploading = null);
    }
  }

  String get _statusText {
    if (_sending) return 'Mengirim…';
    final r = _report;
    if (r == null) return 'Tahan $_seconds detik';
    return r.statusMessage ??
        switch (r.status) {
          SosStatus.queued => 'Menunggu sinyal, akan terkirim otomatis',
          SosStatus.open => 'Terkirim. Menunggu petugas…',
          SosStatus.acknowledged => 'Petugas menerima laporan',
          SosStatus.inProgress => 'Petugas sedang menangani',
          SosStatus.resolved => 'Selesai ditangani',
          SosStatus.cancelled => 'Dibatalkan',
          SosStatus.falseAlarm => 'Ditandai alarm palsu',
        };
  }

  void _openSheet(Widget Function() builder) {
    HapticFeedback.selectionClick();
    setState(() {
      _open = false;
      _sheet = OverlayEntry(builder: (_) => builder());
    });
  }

  void _openComplaint() => _openSheet(() => _ComplaintSheet(
        client: widget.client,
        categories: _cfg?.complaintCategories ?? complaintCategoryLabels.keys.toList(),
        onCapture: widget.onCapture,
        onClose: _closeSheet,
        onSent: widget.onComplaintSent,
        onError: widget.onError,
      ));

  void _openHistory() => _openSheet(() => _HistorySheet(client: widget.client, onClose: _closeSheet));

  void _closeSheet() {
    if (mounted) setState(() => _sheet = null);
  }

  void _toggle() {
    HapticFeedback.selectionClick();
    setState(() {
      _open = !_open;
      _notice = null;
      // laporan yang sudah selesai tidak perlu ditampilkan lagi saat menu dibuka ulang
      if (_open && _report != null && _report!.status.isTerminal) {
        _report = null;
        _attached.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      widget.child,
      if (widget.visible)
        Positioned.fill(
          child: LayoutBuilder(builder: (context, box) {
            final pad = MediaQuery.maybePaddingOf(context) ?? EdgeInsets.zero;
            final minY = pad.top + _kEdge;
            final maxY = (box.maxHeight - pad.bottom - _kEdge - widget.size).clamp(minY, double.infinity);
            final restX = _left ? _kEdge : box.maxWidth - _kEdge - widget.size;
            final restY = minY + (maxY - minY) * _yFrac;
            final pos = _dragPos ?? Offset(restX, restY);
            final onLeft = pos.dx + widget.size / 2 < box.maxWidth / 2;
            final openUp = pos.dy + widget.size / 2 > box.maxHeight / 2;
            final idle = _report == null;

            // Dipasang di MaterialApp.builder (di atas Navigator, tanpa Scaffold): tanpa Material,
            // teks jatuh ke gaya darurat Flutter (monospace + garis bawah kuning). Transparan = sentuhan
            // di area kosong tetap tembus ke halaman.
            return Material(
              type: MaterialType.transparency,
              child: Stack(clipBehavior: Clip.none, children: [
              if (_open)
                Positioned(
                  left: onLeft ? _kEdge : null,
                  right: onLeft ? null : _kEdge,
                  top: openUp ? null : pos.dy + widget.size + 10,
                  bottom: openUp ? box.maxHeight - pos.dy + 10 : null,
                  width: (box.maxWidth - _kEdge * 2).clamp(0, idle ? _kActionWidth : _kPanelWidth),
                  child: idle ? _actions(context, onLeft: onLeft, openUp: openUp) : _panel(context),
                ),
              AnimatedPositioned(
                duration: _dragPos == null ? const Duration(milliseconds: 220) : Duration.zero,
                curve: Curves.easeOutCubic,
                left: pos.dx,
                top: pos.dy,
                child: GestureDetector(
                  key: const ValueKey('siagasos-fab'),
                  onPanStart: (_) => setState(() => _dragPos = pos),
                  onPanUpdate: (d) => setState(() {
                    final p = (_dragPos ?? pos) + d.delta;
                    _dragPos = Offset(p.dx.clamp(_kEdge, box.maxWidth - _kEdge - widget.size), p.dy.clamp(minY, maxY));
                  }),
                  onPanEnd: (_) {
                    final p = _dragPos ?? pos;
                    setState(() {
                      _left = p.dx + widget.size / 2 < box.maxWidth / 2;
                      _yFrac = maxY > minY ? ((p.dy - minY) / (maxY - minY)).clamp(0.0, 1.0) : 1;
                      _dragPos = null;
                    });
                    _savePosition();
                  },
                  child: _fab(),
                ),
              ),
            ]),
            );
          }),
        ),
      // Lembar punya Overlay sendiri: tombol ini dipasang di MaterialApp.builder (di atas Navigator),
      // sementara TextField butuh Overlay untuk handle seleksi.
      if (_sheet != null) Positioned.fill(child: Overlay(key: ObjectKey(_sheet), initialEntries: [_sheet!])),
    ]);
  }

  Widget _fab() {
    final busy = _sending || _uploading != null;
    final colors = _active ? const [Color(0xFF64748B), Color(0xFF334155)] : [widget.color, Color.lerp(widget.color, Colors.black, 0.28)!];
    return Semantics(
      button: true,
      label: _open ? 'Tutup menu darurat' : 'Menu darurat SOS',
      value: _report != null ? _statusText : null,
      child: AnimatedScale(
        scale: _dragPos != null ? 1.08 : 1,
        duration: const Duration(milliseconds: 150),
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: [BoxShadow(color: colors.last.withValues(alpha: 0.42), blurRadius: 12, offset: const Offset(0, 5))],
          ),
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _toggle,
              child: Center(
                child: busy
                    ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                    : Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(_open ? Icons.close_rounded : (_active ? Icons.support_agent_rounded : Icons.notifications_active_rounded),
                            color: Colors.white, size: widget.size * 0.4),
                        SizedBox(height: widget.size * 0.02),
                        Text(_open ? 'TUTUP' : (_active ? 'AKTIF' : 'SOS'),
                            style: TextStyle(
                                color: Colors.white, fontSize: widget.size * 0.156, fontWeight: FontWeight.w800, letterSpacing: 0.4, height: 1)),
                      ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Menu awal ala speed-dial (gaya `DraggableSosMenu` tata-warga). Urutan dari tombol bulat ke luar:
  /// telepon kedua, telepon pertama, kirim SOS, lalu pengaduan & riwayat yang tidak darurat di ujung.
  Widget _actions(BuildContext context, {required bool onLeft, required bool openUp}) {
    final cfg = _cfg;
    final first = cfg?.fallbackPhone ?? '110';
    final second = widget.secondaryPhone != null && widget.secondaryPhone != first ? widget.secondaryPhone : null;
    final items = <Widget>[
      if (widget.onCall != null) ...[
        if (second != null)
          _ActionButton(
            label: '${widget.callLabel} $second',
            icon: Icons.emergency_rounded,
            colors: const [Color(0xFF6EE7B7), Color(0xFF34D399), Color(0xFF059669)],
            onTap: () => widget.onCall!(second),
          ),
        _ActionButton(
          label: '${widget.callLabel} $first',
          icon: Icons.local_police_rounded,
          colors: const [Color(0xFF818CF8), Color(0xFF6366F1), Color(0xFF4F46E5)],
          onTap: () => widget.onCall!(first),
        ),
      ],
      _HoldToSend(
        hold: _hold,
        seconds: _seconds,
        colors: widget.sosColors ?? [Color.lerp(widget.color, Colors.white, 0.12)!, Color.lerp(widget.color, Colors.black, 0.3)!],
        sending: _sending,
        label: widget.sosLabel ?? (cfg?.buttonText.isNotEmpty == true ? 'Kirim ${cfg!.buttonText}' : 'Kirim SOS'),
      ),
      if (widget.complaint)
        _ActionButton(
          key: const ValueKey('siagasos-complaint'),
          label: 'Pengaduan',
          icon: Icons.campaign_rounded,
          colors: const [Color(0xFFFDBA74), Color(0xFFFB923C), Color(0xFFEA580C)],
          onTap: _openComplaint,
        ),
      if (widget.history)
        _ActionButton(
          key: const ValueKey('siagasos-history'),
          label: 'Riwayat laporan',
          icon: Icons.history_rounded,
          colors: const [Color(0xFF94A3B8), Color(0xFF64748B), Color(0xFF475569)],
          onTap: _openHistory,
        ),
    ];
    final note = <String>[
      if (_notice != null) _notice!,
      if (cfg != null && cfg.recipientText.isNotEmpty) cfg.recipientText,
      if (widget.client.mode == SosMode.test) 'MODE TEST',
    ];
    final ordered = openUp ? items.reversed.toList() : items;
    final caption = note.isEmpty
        ? null
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(color: const Color(0xE6111827), borderRadius: BorderRadius.circular(10)),
            child: Text(note.join(' · '),
                style: TextStyle(color: _notice != null ? const Color(0xFFFCA5A5) : Colors.white, fontSize: 11.5, height: 1.3)),
          );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: onLeft ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      children: [
        if (openUp && caption != null) ...[caption, const SizedBox(height: 8)],
        for (var i = 0; i < ordered.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _Pop(index: openUp ? ordered.length - 1 - i : i, child: ordered[i]),
        ],
        if (!openUp && caption != null) ...[const SizedBox(height: 8), caption],
      ],
    );
  }

  /// Panel status setelah SOS terkirim: status, batal, rekam TKP, telepon.
  Widget _panel(BuildContext context) {
    final theme = Theme.of(context);
    final r = _report!;
    final cfg = _cfg;
    final children = <Widget>[
      Row(children: [
        Icon(r.status.isTerminal ? Icons.check_circle_rounded : Icons.radio_button_checked_rounded,
            color: r.status.isTerminal ? const Color(0xFF16A34A) : widget.color, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text(_statusText, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
      ]),
    ];
    if (r.status == SosStatus.open) {
      children.add(Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: () => widget.client.cancel(r.localId, reason: 'Salah tekan'),
          child: const Text('Batalkan (salah tekan)'),
        ),
      ));
    }
    if (widget.onCapture != null && widget.captureKinds.isNotEmpty && !r.status.isTerminal) {
      children.add(Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Text('Kirim bukti ke petugas', style: theme.textTheme.labelMedium),
      ));
      children.add(Row(children: [
        for (final k in widget.captureKinds) ...[
          if (k != widget.captureKinds.first) const SizedBox(width: 6),
          Expanded(child: _mediaButton(k)),
        ],
      ]));
      if (_uploading != null) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 8),
          child: LinearProgressIndicator(value: _uploadRatio, color: widget.color),
        ));
      }
    }
    if (_notice != null) {
      children.add(Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(_notice!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
      ));
    }
    if (widget.onCall != null) {
      final phones = <String>{cfg?.fallbackPhone ?? '110', if (widget.secondaryPhone != null) widget.secondaryPhone!};
      children.add(const Divider(height: 20));
      for (final p in phones) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 4),
          child: FilledButton.tonalIcon(
            onPressed: () => widget.onCall?.call(p),
            icon: const Icon(Icons.call_rounded),
            label: Text('Telepon $p'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
          ),
        ));
      }
    }
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      ),
    );
  }

  Widget _mediaButton(MediaKind k) {
    final (icon, label) = switch (k) {
      MediaKind.image => (Icons.photo_camera_rounded, 'Foto'),
      MediaKind.video => (Icons.videocam_rounded, 'Video'),
      MediaKind.audio => (Icons.mic_rounded, 'Suara'),
    };
    final n = _attached[k] ?? 0;
    return OutlinedButton(
      onPressed: _uploading == null ? () => _capture(k) : null,
      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 10), minimumSize: const Size(0, 48)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(n > 0 ? Icons.check_rounded : icon, size: 20),
        Text(n > 1 ? '$label ($n)' : label, style: const TextStyle(fontSize: 12)),
      ]),
    );
  }
}

const _kActionHeight = 48.0;
const _kActionRadius = 12.0;
const _kActionText = TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600);

BoxDecoration _actionDecoration(List<Color> colors) => BoxDecoration(
      gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
      borderRadius: BorderRadius.circular(_kActionRadius),
      border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 6, offset: const Offset(0, 2))],
    );

/// Muncul bertahap saat menu dibuka.
class _Pop extends StatelessWidget {
  const _Pop({required this.index, required this.child});
  final int index;
  final Widget child;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 180 + index * 50),
        curve: Curves.easeOutBack,
        builder: (context, t, c) => Opacity(opacity: t.clamp(0.0, 1.0), child: Transform.scale(scale: 0.85 + 0.15 * t, child: c)),
        child: child,
      );
}

/// Tombol aksi gradien (gaya menu SOS tata-warga).
class _ActionButton extends StatelessWidget {
  const _ActionButton({super.key, required this.label, required this.icon, required this.colors, required this.onTap});
  final String label;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: _kActionWidth,
        height: _kActionHeight,
        child: DecoratedBox(
          decoration: _actionDecoration(colors),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(_kActionRadius),
            child: InkWell(
              borderRadius: BorderRadius.circular(_kActionRadius),
              onTap: () {
                HapticFeedback.lightImpact();
                onTap();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(children: [
                  Icon(icon, color: Colors.white, size: 22),
                  const SizedBox(width: 8),
                  Expanded(child: Text(label, overflow: TextOverflow.ellipsis, style: _kActionText)),
                ]),
              ),
            ),
          ),
        ),
      );
}

/// Bilah "tahan untuk kirim" di dalam menu melayang.
class _HoldToSend extends StatelessWidget {
  const _HoldToSend({required this.hold, required this.seconds, required this.colors, required this.sending, required this.label});
  final AnimationController hold;
  final int seconds;
  final List<Color> colors;
  final bool sending;
  final String label;

  @override
  Widget build(BuildContext context) {
    void down() {
      if (sending) return;
      HapticFeedback.selectionClick();
      hold.duration = Duration(seconds: seconds);
      hold.forward(from: 0);
    }

    void up() {
      if (hold.isAnimating) hold.reverse();
    }

    return Semantics(
      button: true,
      label: '$label. Tahan $seconds detik untuk mengirim laporan darurat.',
      child: GestureDetector(
        key: const ValueKey('siagasos-hold'),
        onTapDown: (_) => down(),
        onTapUp: (_) => up(),
        onTapCancel: up,
        child: AnimatedBuilder(
          animation: hold,
          builder: (context, _) => Container(
            width: _kActionWidth,
            height: _kActionHeight,
            decoration: _actionDecoration(colors),
            clipBehavior: Clip.antiAlias,
            child: Stack(children: [
              FractionallySizedBox(widthFactor: hold.value, child: Container(color: Colors.black.withValues(alpha: 0.22))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(children: [
                  sending
                      ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                      : const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      sending ? 'Mengirim…' : hold.value > 0 ? 'Tahan… ${(seconds * (1 - hold.value)).ceil()}' : label,
                      overflow: TextOverflow.ellipsis,
                      style: _kActionText.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (!sending && hold.value == 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(6)),
                      child: Text('tahan ${seconds}d', style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700)),
                    ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Form "Laporan pengaduan" (non-darurat): kategori, uraian, foto opsional. Lembar dari bawah layar.
class _ComplaintSheet extends StatefulWidget {
  const _ComplaintSheet({
    required this.client,
    required this.categories,
    required this.onCapture,
    required this.onClose,
    this.onSent,
    this.onError,
  });
  final SiagaSOS client;
  final List<String> categories;
  final MediaCapture? onCapture;
  final VoidCallback onClose;
  final void Function(ActiveReport report)? onSent;
  final void Function(SiagaSOSError error)? onError;

  @override
  State<_ComplaintSheet> createState() => _ComplaintSheetState();
}

class _ComplaintSheetState extends State<_ComplaintSheet> {
  static const _amber = Color(0xFFD97706);
  late String _category = widget.categories.isNotEmpty ? widget.categories.first : 'lainnya';
  final _text = TextEditingController();
  CapturedMedia? _photo;
  bool _sending = false;
  ActiveReport? _report;
  double? _upload; // null = tidak ada unggahan berjalan
  bool _photoSent = false;
  String? _error;
  StreamSubscription<ActiveReport>? _sub;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
    _sub = widget.client.status.listen((r) {
      if (mounted && _report?.localId == r.localId) setState(() => _report = r);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _text.dispose();
    super.dispose();
  }

  bool get _valid => _text.text.trim().length >= 5;

  Future<void> _pickPhoto() async {
    final m = await widget.onCapture?.call(context, MediaKind.image);
    if (m != null && mounted) setState(() => _photo = m);
  }

  Future<void> _send() async {
    if (!_valid || _sending) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final r = await widget.client.complain(category: _category, message: _text.text);
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      setState(() => _report = r);
      if (r.id != null) widget.onSent?.call(r);
      final photo = _photo;
      if (photo != null) {
        setState(() => _upload = 0);
        try {
          await widget.client.attach(r.localId, photo.bytes,
              contentType: photo.contentType, onProgress: (p) => mounted ? setState(() => _upload = p) : null);
          if (mounted) setState(() => _photoSent = true);
        } on SiagaSOSError catch (e) {
          if (mounted) setState(() => _error = 'Pengaduan terkirim, tetapi foto gagal diunggah: ${e.message}');
        } finally {
          if (mounted) setState(() => _upload = null);
        }
      }
    } on SiagaSOSError catch (e) {
      if (mounted) setState(() => _error = e.message);
      widget.onError?.call(e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String get _statusText {
    final r = _report!;
    return switch (r.status) {
      SosStatus.queued => 'Belum ada sinyal. Pengaduan disimpan dan dikirim otomatis.',
      SosStatus.open => 'Pengaduan terkirim. Petugas akan menindaklanjuti.',
      SosStatus.acknowledged => 'Pengaduan diterima petugas.',
      SosStatus.inProgress => 'Pengaduan sedang ditindaklanjuti.',
      SosStatus.resolved => 'Pengaduan selesai ditindaklanjuti.',
      SosStatus.cancelled => 'Pengaduan dibatalkan.',
      SosStatus.falseAlarm => 'Pengaduan ditutup petugas.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _SheetFrame(
      sheetKey: const ValueKey('siagasos-complaint-sheet'),
      onDismiss: _sending ? null : widget.onClose,
      child: _report == null ? _form(theme) : _done(theme),
    );
  }

  Widget _grip(ThemeData theme) => _Grip(theme);

  Widget _form(ThemeData theme) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        _grip(theme),
        Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFFFBBF24), _amber]),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.campaign_rounded, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Laporan pengaduan', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              Text('Bukan untuk keadaan darurat', style: theme.textTheme.bodySmall),
            ]),
          ),
          IconButton(onPressed: _sending ? null : widget.onClose, icon: const Icon(Icons.close_rounded), tooltip: 'Tutup'),
        ]),
        const SizedBox(height: 16),
        Text('Jenis pengaduan', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final c in widget.categories)
            ChoiceChip(
              label: Text(complaintCategoryLabel(c)),
              selected: _category == c,
              onSelected: _sending ? null : (_) => setState(() => _category = c),
              selectedColor: const Color(0xFFFDE68A),
              showCheckmark: false,
            ),
        ]),
        const SizedBox(height: 16),
        TextField(
          key: const ValueKey('siagasos-complaint-text'),
          controller: _text,
          enabled: !_sending,
          minLines: 3,
          maxLines: 6,
          maxLength: 1000,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: 'Uraian',
            hintText: 'Apa yang terjadi, di mana, sejak kapan?',
            alignLabelWithHint: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        if (widget.onCapture != null) ...[
          const SizedBox(height: 4),
          _photo == null
              ? OutlinedButton.icon(
                  onPressed: _sending ? null : _pickPhoto,
                  icon: const Icon(Icons.add_a_photo_rounded),
                  label: const Text('Lampirkan foto (opsional)'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                )
              : Row(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(_photo!.bytes, width: 56, height: 56, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(width: 56, height: 56, color: theme.colorScheme.surfaceContainerHighest, child: const Icon(Icons.image_rounded))),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(child: Text('Foto terlampir')),
                  TextButton(onPressed: _sending ? null : () => setState(() => _photo = null), child: const Text('Hapus')),
                ]),
        ],
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const ValueKey('siagasos-complaint-send'),
          onPressed: _valid && !_sending ? _send : null,
          icon: _sending
              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
              : const Icon(Icons.send_rounded),
          label: Text(_sending ? 'Mengirim…' : 'Kirim pengaduan'),
          style: FilledButton.styleFrom(backgroundColor: _amber, minimumSize: const Size.fromHeight(52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
        ),
        if (widget.client.mode == SosMode.test)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('MODE TEST', textAlign: TextAlign.center, style: TextStyle(color: Colors.amber.shade800, fontWeight: FontWeight.w700, fontSize: 11)),
          ),
      ]);

  Widget _done(ThemeData theme) {
    final r = _report!;
    final queued = r.status == SosStatus.queued;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      _grip(theme),
      Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(shape: BoxShape.circle, color: (queued ? _amber : const Color(0xFF16A34A)).withValues(alpha: 0.12)),
        child: Icon(queued ? Icons.schedule_send_rounded : Icons.check_circle_rounded, size: 36, color: queued ? _amber : const Color(0xFF16A34A)),
      ),
      const SizedBox(height: 12),
      Text(queued ? 'Pengaduan disimpan' : 'Pengaduan terkirim', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      Text(_statusText, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
      if (r.id != null) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
          child: Text('No. ${(r.id!.length > 8 ? r.id!.substring(0, 8) : r.id!).toUpperCase()} · ${complaintCategoryLabel(r.category)}',
              style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
        ),
      ],
      if (_upload != null) ...[
        const SizedBox(height: 14),
        Text('Mengunggah foto…', style: theme.textTheme.bodySmall),
        const SizedBox(height: 6),
        LinearProgressIndicator(value: _upload, color: _amber),
      ] else if (_photoSent) ...[
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.check_rounded, size: 18, color: Color(0xFF16A34A)),
          const SizedBox(width: 4),
          Text('Foto terlampir', style: theme.textTheme.bodySmall),
        ]),
      ],
      if (_error != null) ...[
        const SizedBox(height: 10),
        Text(_error!, textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
      ],
      const SizedBox(height: 18),
      FilledButton(
        onPressed: _upload != null ? null : widget.onClose,
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        child: const Text('Tutup'),
      ),
    ]);
  }
}

class _Grip extends StatelessWidget {
  const _Grip(this.theme);
  final ThemeData theme;
  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 40,
          height: 4,
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(color: theme.colorScheme.outlineVariant, borderRadius: BorderRadius.circular(2)),
        ),
      );
}

/// Latar gelap + lembar yang naik dari bawah layar (dipakai form pengaduan dan riwayat).
class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.sheetKey, required this.onDismiss, required this.child, this.scroll = true});
  final Key sheetKey;
  /// Null = ketuk latar tidak menutup (mis. sedang mengirim).
  final VoidCallback? onDismiss;
  final Widget child;
  /// false = [child] mengatur scroll sendiri (mis. daftar).
  final bool scroll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inset = MediaQuery.maybeViewInsetsOf(context)?.bottom ?? 0;
    final safe = MediaQuery.maybePaddingOf(context)?.bottom ?? 0;
    final padding = EdgeInsets.fromLTRB(20, 10, 20, 16 + (inset > 0 ? 0 : safe));
    return Stack(children: [
      Positioned.fill(
        child: GestureDetector(
          onTap: onDismiss,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 200),
            builder: (_, t, __) => ColoredBox(color: Colors.black.withValues(alpha: 0.45 * t)),
          ),
        ),
      ),
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 1, end: 0),
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          builder: (_, t, c) => FractionalTranslation(translation: Offset(0, t), child: c),
          child: Padding(
            padding: EdgeInsets.only(bottom: inset),
            child: Material(
              key: sheetKey,
              color: theme.colorScheme.surface,
              elevation: 12,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
                child: scroll ? SingleChildScrollView(padding: padding, child: child) : Padding(padding: padding, child: child),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

/// "Riwayat laporan": SOS & pengaduan yang pernah dikirim dari perangkat ini, dengan status terbaru dari server.
class _HistorySheet extends StatefulWidget {
  const _HistorySheet({required this.client, required this.onClose});
  final SiagaSOS client;
  final VoidCallback onClose;

  @override
  State<_HistorySheet> createState() => _HistorySheetState();
}

class _HistorySheetState extends State<_HistorySheet> {
  List<ReportRecord>? _items;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // Tampilkan simpanan lokal dulu (instan), lalu perbarui status dari server.
    widget.client.history(refresh: false).then((l) => mounted && _items == null ? setState(() => _items = l) : null);
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final l = await widget.client.history();
    if (mounted) {
      setState(() {
        _items = l;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = _items;
    return _SheetFrame(
      sheetKey: const ValueKey('siagasos-history-sheet'),
      onDismiss: widget.onClose,
      scroll: false,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _Grip(theme),
        Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF94A3B8), Color(0xFF475569)]),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.history_rounded, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Riwayat laporan', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              Text('SOS & pengaduan dari perangkat ini', style: theme.textTheme.bodySmall),
            ]),
          ),
          _loading
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.2)),
                )
              : IconButton(onPressed: _reload, icon: const Icon(Icons.refresh_rounded), tooltip: 'Muat ulang'),
          IconButton(onPressed: widget.onClose, icon: const Icon(Icons.close_rounded), tooltip: 'Tutup'),
        ]),
        const SizedBox(height: 12),
        if (items == null)
          const SizedBox(height: 120)
        else if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 36),
            child: Column(children: [
              Icon(Icons.inbox_rounded, size: 40, color: theme.colorScheme.outline),
              const SizedBox(height: 8),
              Text('Belum ada laporan', style: theme.textTheme.titleSmall),
              const SizedBox(height: 2),
              Text('SOS dan pengaduan yang kamu kirim akan muncul di sini.',
                  textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
            ]),
          )
        else
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _HistoryTile(items[i]),
            ),
          ),
      ]),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile(this.r);
  final ReportRecord r;

  static (String, Color) _status(SosStatus s) => switch (s) {
        SosStatus.queued => ('Menunggu sinyal', const Color(0xFF6B7280)),
        SosStatus.open => ('Terkirim', const Color(0xFFDC2626)),
        SosStatus.acknowledged => ('Diterima petugas', const Color(0xFFD97706)),
        SosStatus.inProgress => ('Ditangani', const Color(0xFFD97706)),
        SosStatus.resolved => ('Selesai', const Color(0xFF16A34A)),
        SosStatus.cancelled => ('Dibatalkan', const Color(0xFF6B7280)),
        SosStatus.falseAlarm => ('Ditutup', const Color(0xFF6B7280)),
      };

  static String _when(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
    return '${d.day} ${months[d.month - 1]} ${d.year} · ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sos = r.kind == ReportKind.sos;
    final (label, color) = _status(r.status);
    final title = sos ? 'SOS darurat' : complaintCategoryLabel(r.category);
    final done = r.resolvedAt ?? r.acknowledgedAt;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: (sos ? const Color(0xFFDC2626) : const Color(0xFFEA580C)).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(sos ? Icons.notifications_active_rounded : Icons.campaign_rounded,
              size: 20, color: sos ? const Color(0xFFDC2626) : const Color(0xFFEA580C)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(title,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ]),
            if (r.message != null && r.message!.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(r.message!.trim(), maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
            ],
            if (r.statusMessage != null && r.statusMessage!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(r.statusMessage!, style: theme.textTheme.bodySmall?.copyWith(color: color, fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 6),
            Text(
              'No. ${(r.id.length > 8 ? r.id.substring(0, 8) : r.id).toUpperCase()} · ${_when(r.createdAt)}'
              '${done != null && r.status.isTerminal ? ' · selesai ${_when(done)}' : ''}',
              style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline),
            ),
          ]),
        ),
      ]),
    );
  }
}
