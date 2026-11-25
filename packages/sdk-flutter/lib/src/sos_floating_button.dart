import 'dart:async';
import 'dart:math' show min;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'client.dart';
import 'models.dart';

/// Hasil rekaman TKP dari app host (kamera/mikrofon disediakan app, SDK tidak membawa plugin).
class CapturedMedia {
  const CapturedMedia(
      {required this.bytes, required this.contentType, this.durationS});
  final Uint8List bytes;
  final String contentType;
  final double? durationS;
}

/// Sumber lampiran yang dipilih pengguna di form pengaduan: galeri (foto/video yang sudah ada) atau kamera.
enum MediaSource { gallery, camera }

/// Dipanggil saat pengguna memilih Foto / Video (dan sumbernya) setelah SOS terkirim.
/// Kembalikan null bila pengguna membatalkan. [source] selalu [MediaSource.camera] untuk rekam TKP.
typedef MediaCapture = Future<CapturedMedia?> Function(
    BuildContext context, MediaKind kind, MediaSource source);

/// Sirene panik di HP pelapor. Suara diputar app host (SDK tanpa plugin audio).
/// SDK memanggil [start] saat SOS ditekan; selama [active] true tombol bulat menjadi "SENYAP" ([stop]).
abstract class SosSiren {
  ValueListenable<bool> get active;
  void start();
  void stop();
}

/// Label bawaan tombol kirim SOS di menu bila host tidak mengisi `sosLabel`.
///
/// Server selalu mengirim `button_text` ('SOS' bila "Teks tombol" di portal kosong), jadi
/// nilai bawaan 'SOS' diperlakukan sama dengan kosong → 'Emergency'. Teks lain dari portal
/// tetap dipakai sebagai `Kirim {teks}`.
String defaultSosMenuLabel(String? buttonText) {
  final t = buttonText?.trim() ?? '';
  if (t.isEmpty || t.toUpperCase() == 'SOS') return 'Emergency';
  return 'Kirim $t';
}

/// Tombol SOS kecil yang melayang di atas semua halaman.
///
/// Ketuk → 4 aksi bertumpuk (gaya `DraggableSosMenu` tata-warga): **Emergency** (tahan N detik, atau sekali
/// ketuk; `holdSeconds: N` untuk tahan N detik), **Telepon 110**, **Telepon 112**, dan **Laporan** → sub-menu Pengaduan
/// ([SiagaSOS.complain]) / Riwayat laporan ([SiagaSOS.history]).
///
/// Setelah SOS terkirim: [siren] berbunyi (tombol bulat jadi "SENYAP"), lalu popup "Rekam kondisi TKP?" →
/// [onCapture] video → catatan → video + [SiagaSOS.addNote] ke petugas. Selama SOS belum selesai menu tetap sama
/// (seperti tata-warga): status tampil di keterangan menu + titik kecil di tombol bulat, batal lewat Riwayat laporan.
///
/// Pasang sekali di root app:
/// ```dart
/// MaterialApp(
///   builder: (context, child) => SOSFloatingButton(
///     client: sos,
///     onCall: (phone) => launchUrl(Uri(scheme: 'tel', path: phone)),
///     onCapture: (context, kind, source) => pickMedia(kind, source), // opsional, mis. image_picker
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
    this.holdSeconds = 0,
    this.onCall,
    this.secondaryPhone,
    this.onCapture,
    this.onSent,
    this.onError,
    this.size = 48,
    this.color = const Color(0xFFDC2626),
    this.visible = true,
    this.positionKey = 'siagasos.fab.position',
    this.complaint = true,
    this.complaintLabel = 'Buat Laporan',
    this.onComplaintSent,
    this.captureKinds = MediaKind.values,
    this.sosLabel,
    this.sosColors = const [
      Color(0xFFFF7058),
      Color(0xFFEB334C),
      Color(0xFFD72242)
    ],
    this.callLabel = 'Call',
    this.callColors = const [
      Color(0xFF60A5FA),
      Color(0xFF3B82F6),
      Color(0xFF2563EB)
    ],
    this.firstCallLabel,
    this.firstCallImage =
        const AssetImage('packages/siagasos/assets/police.png'),
    this.compact = true,
    this.contactsLabel = 'Input Nomor',
    this.reportLabel = 'Laporan Kejadian',
    this.history = true,
    @Deprecated(
        'Sirene lokal tidak dibunyikan lagi; penerima mendapat push + sirene di app Polmas Keamanan.')
    this.siren,
    this.tkpPrompt = true,
    this.tkpSeconds = 5,
    this.emergencyContacts = true,
    this.contactRoles = defaultEmergencyContactRoles,
    this.areaContactRoles = defaultAreaContactRoles,
    this.onOpenUrl,
    this.videoPlayerBuilder,
  });

  final SiagaSOS client;
  final Widget child;
  final String category;
  final String? message;

  /// Default 0 = sekali ketuk langsung kirim (seperti EWS tata-warga). N > 0 = tahan N detik (cegah salah tekan);
  /// null = ikut `hold_seconds` dari portal.
  final int? holdSeconds;

  /// Menelepon nomor darurat (mis. url_launcher `tel:`). Null = tombol telepon disembunyikan.
  final void Function(String phone)? onCall;

  /// Nomor darurat kedua di menu. Nomor pertama memakai `fallback_phone` dari portal (default 110).
  final String? secondaryPhone;

  /// Kamera/mikrofon app host: video TKP setelah SOS terkirim, foto lampiran pengaduan. Null = tanpa lampiran.
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

  /// Judul menu & form pengaduan (mis. 'Pengaduan 110'). Default 'Pengaduan'.
  final String complaintLabel;
  final void Function(ActiveReport report)? onComplaintSent;

  /// Jenis lampiran yang ditawarkan setelah SOS terkirim (mis. tanpa [MediaKind.audio] bila app tidak punya perekam).
  final List<MediaKind> captureKinds;

  /// Label tombol kirim SOS di menu (mis. 'EWS Alert'). Null = [defaultSosMenuLabel]:
  /// 'Emergency', atau "Kirim `button_text`" bila "Teks tombol" di portal diisi selain 'SOS'.
  final String? sosLabel;

  /// Gradien tombol kirim SOS di menu (mis. kuning EWS). Null = turunan [color].
  final List<Color>? sosColors;

  /// Awalan tombol telepon: `"$callLabel 110"` (mis. 'Call').
  final String callLabel;

  /// Gradien tombol telepon pertama (110). Null = default SDK (indigo).
  final List<Color>? callColors;

  /// Label lengkap tombol telepon pertama (mis. 'Call 110 Polri'). Null = `"$callLabel $first"`.
  final String? firstCallLabel;

  /// Tombol menu lebih kecil dan padat (tinggi 34, ikon kecil). Default false = ukuran standar.
  final bool compact;

  /// Gambar pengganti ikon tombol telepon pertama (mode compact), mis. ilustrasi polisi.
  final ImageProvider? firstCallImage;

  /// Label menu & judul sheet "Nomor darurat". Default 'Nomor darurat'.
  final String contactsLabel;

  /// Label tombol menu laporan dan judul sub-menunya. Default 'Laporan'.
  final String reportLabel;

  /// Tampilkan menu "Riwayat laporan" (status SOS & pengaduan yang pernah dikirim dari perangkat ini).
  final bool history;

  /// Sirene di HP pelapor saat SOS ditekan (opsional).
  final SosSiren? siren;

  /// Setelah SOS terkirim, tawarkan "Rekam kondisi TKP?" (video + catatan) seperti tata-warga.
  /// Butuh [onCapture] dan [MediaKind.video] di [captureKinds]; false = panel status biasa.
  final bool tkpPrompt;

  /// Batas durasi video TKP yang ditampilkan di ajakan rekam (kamera tetap diatur app host).
  final int tkpSeconds;

  /// Menu "Nomor darurat" (Laporan → Nomor darurat): maks. 3 nomor WhatsApp pribadi yang ikut dikabari saat SOS.
  final bool emergencyContacts;

  /// Pilihan dropdown "Status" di Input Nomor (mis. RT, RW, Satpam, Bhabinkamtibmas). "Lainnya" selalu ditambahkan
  /// di akhir untuk isian bebas.
  final List<String> contactRoles;

  /// Status yang wajib mengisi wilayah tugas (provinsi → desa), diisi otomatis dari lokasi bila bisa.
  final Set<String> areaContactRoles;

  /// Membuka tautan di luar app (peta lokasi) dari detail riwayat, mis. url_launcher.
  /// Null = tombol "Buka peta" disembunyikan.
  final void Function(String url)? onOpenUrl;

  /// Pemutar video untuk lampiran di detail riwayat (diputar di dalam app, tidak pindah ke browser).
  /// Host menyediakan widget pemutar, mis. `video_player`. Null = video tidak bisa diputar.
  /// Foto selalu bisa dibuka di dalam app (layar penuh, bisa di-zoom).
  final Widget Function(String url)? videoPlayerBuilder;

  @override
  State<SOSFloatingButton> createState() => _SOSFloatingButtonState();
}

const double _kEdge = 12;

class _SOSFloatingButtonState extends State<SOSFloatingButton>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _hold = AnimationController(vsync: this);

  /// Sisi tempel: false = kanan, true = kiri. [_yFrac] = posisi vertikal 0 (atas) .. 1 (bawah).
  bool _left = false;
  double _yFrac = 1;
  Offset? _dragPos;

  bool _open = false;

  /// Sub-menu "Laporan" (Pengaduan / Riwayat) sedang terbuka.
  bool _reportMenu = false;
  bool _sending = false;
  SdkConfig? _cfg;

  /// Sirene lokal di HP pelapor DIMATIKAN sejak Polmas Keamanan (docs/POLMAS_KEAMANAN.md §9): yang berbunyi adalah HP
  /// penerima (push FCM). Parameter `siren` tetap diterima supaya app host lama tetap terkompilasi, tapi diabaikan.
  SosSiren? get _siren => null;

  /// Jabatan Nomor Darurat: daftar dari app host bila diberikan, selain itu daftar per pilar dari server.
  List<String> get _contactRoles {
    final server = _cfg?.contactRoles ?? const <String>[];
    if (!identical(widget.contactRoles, defaultEmergencyContactRoles) ||
        server.isEmpty) return widget.contactRoles;
    return server;
  }

  ActiveReport? _report;
  StreamSubscription<ActiveReport>? _sub;
  String? _notice;

  /// Lembar dari bawah (pengaduan / riwayat / rekam TKP).
  OverlayEntry? _sheet;

  /// Navigator lokal di dalam lembar (dibutuhkan date/time picker). Dipakai untuk tombol back.
  final _sheetNavKey = GlobalKey<NavigatorState>();

  /// App host sedang membuka layar kamera (halaman di Navigator, di BAWAH lapisan ini): tombol & lembar
  /// disembunyikan sementara tanpa kehilangan state.
  bool _capturing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.client
        .getConfig()
        .then((c) => mounted ? setState(() => _cfg = c) : null)
        .catchError((_) {});
    _sub = widget.client.status.listen((r) {
      if (!mounted || r.kind != ReportKind.sos) return;
      if (_report == null || _report!.localId == r.localId)
        setState(() => _report = r);
    });
    _hold.addStatusListener((s) {
      if (s == AnimationStatus.completed) _fire();
    });
    _loadPosition();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _hold.dispose();
    super.dispose();
  }

  /// Tombol back Android: saat lembar terbuka, tutup dialog tanggal/jam dulu, lalu lembarnya —
  /// jangan langsung keluar dari app. Saat kamera host terbuka (lembar disembunyikan), biarkan app yang menangani.
  @override
  Future<bool> didPopRoute() async {
    if (_sheet == null || _capturing) return false;
    final nav = _sheetNavKey.currentState;
    if (nav != null && await nav.maybePop()) return true;
    _closeSheet();
    return true;
  }

  Future<void> _loadPosition() async {
    try {
      final raw =
          (await SharedPreferences.getInstance()).getString(widget.positionKey);
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
      await (await SharedPreferences.getInstance()).setString(
          widget.positionKey,
          '${_left ? 'L' : 'R'},${_yFrac.toStringAsFixed(4)}');
    } catch (_) {}
  }

  int get _seconds => widget.holdSeconds ?? _cfg?.holdSeconds ?? 3;
  bool get _active => _report != null && !_report!.status.isTerminal;

  bool get _tkp =>
      widget.tkpPrompt &&
      widget.onCapture != null &&
      widget.captureKinds.contains(MediaKind.video);

  Future<void> _fire() async {
    if (_sending) return;
    HapticFeedback.mediumImpact();
    // Alarm panik dimulai tanpa menunggu server (jeda/durasi diatur app host).
    _siren?.start();
    setState(() => _sending = true);
    try {
      final r = await widget.client
          .trigger(category: widget.category, message: widget.message);
      HapticFeedback.heavyImpact();
      if (mounted) setState(() => _report = r);
      if (r.id != null) widget.onSent?.call(r);
      if (mounted && _tkp) _openTkp(r);
    } on SiagaSOSError catch (e) {
      _siren?.stop(); // SOS tidak terkirim: sirene menyesatkan
      if (mounted) setState(() => _notice = e.message);
      widget.onError?.call(e);
    } finally {
      if (mounted) setState(() => _sending = false);
      _hold.reset();
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
      _reportMenu = false;
      // Lembar dipasang di atas Navigator app (MaterialApp.builder), jadi tidak ada Navigator di atasnya.
      // showDatePicker/showTimePicker butuh Navigator → beri Navigator lokal (transparan, tanpa animasi)
      // supaya dialog tanggal/jam bisa dibuka dari dalam lembar.
      // HeroControllerScope.none: HeroController milik MaterialApp sudah dipakai Navigator app; dibagi ke
      // Navigator kedua → assert "A HeroController can not be shared by multiple Navigators".
      _sheet = OverlayEntry(
          builder: (_) => HeroControllerScope.none(
                child: Navigator(
                  key: _sheetNavKey,
                  onGenerateRoute: (_) => PageRouteBuilder<void>(
                    opaque: false,
                    transitionDuration: Duration.zero,
                    reverseTransitionDuration: Duration.zero,
                    pageBuilder: (_, __, ___) => builder(),
                  ),
                ),
              ));
    });
  }

  void _openComplaint() => _openSheet(() => _ComplaintSheet(
        client: widget.client,
        label: widget.complaintLabel,
        categories:
            _cfg?.complaintCategories ?? complaintCategoryLabels.keys.toList(),
        onCapture: widget.onCapture,
        // Saat app host membuka galeri/kamera (halaman di atas), lembar ini disembunyikan sementara
        // (state tetap) supaya ketukan di balik lembar tidak menutup form dan lampiran tidak hilang.
        onCapturing: (v) => mounted ? setState(() => _capturing = v) : null,
        onClose: _closeSheet,
        onSent: widget.onComplaintSent,
        onError: widget.onError,
      ));

  void _openTkp(ActiveReport r) => _openSheet(() => _TkpSheet(
        client: widget.client,
        report: r,
        recipientText: _cfg?.recipientText,
        siren: _siren,
        onCapture: widget.onCapture!,
        maxSeconds: widget.tkpSeconds,
        color: widget.color,
        onCapturing: (v) => mounted ? setState(() => _capturing = v) : null,
        onClose: _closeSheet,
        onError: widget.onError,
      ));

  void _openHistory() => _openSheet(() => _HistorySheet(
      client: widget.client,
      onClose: _closeSheet,
      onOpenUrl: widget.onOpenUrl,
      videoPlayerBuilder: widget.videoPlayerBuilder));

  void _openContacts() => _openSheet(() => _ContactsSheet(
      client: widget.client,
      title: widget.contactsLabel,
      roles: _contactRoles,
      pillarLabel: _cfg?.pillarLabel,
      areaRoles: widget.areaContactRoles,
      onClose: _closeSheet));

  void _closeSheet() {
    if (mounted) setState(() => _sheet = null);
  }

  void _toggle() {
    HapticFeedback.selectionClick();
    setState(() {
      _open = !_open;
      _reportMenu = false;
      _notice = null;
      // laporan yang sudah selesai tidak perlu ditampilkan lagi saat menu dibuka ulang
      if (_open && _report != null && _report!.status.isTerminal) {
        _report = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      widget.child,
      // Lapisan selalu ada di Stack (hanya disembunyikan): menghapusnya menggeser posisi lapisan lembar, sehingga
      // Overlay-nya dibuat ulang padahal entry masih di Overlay lama ("entry is already present in a different Overlay").
      Positioned.fill(
        key: const ValueKey('siagasos-layer-fab'),
        child: Offstage(
          offstage: !widget.visible || _capturing,
          child: LayoutBuilder(builder: (context, box) {
            final pad = MediaQuery.maybePaddingOf(context) ?? EdgeInsets.zero;
            final minY = pad.top + _kEdge;
            final maxY = (box.maxHeight - pad.bottom - _kEdge - widget.size)
                .clamp(minY, double.infinity);
            final restX = _left ? _kEdge : box.maxWidth - _kEdge - widget.size;
            final restY = minY + (maxY - minY) * _yFrac;
            final pos = _dragPos ?? Offset(restX, restY);
            final onLeft = pos.dx + widget.size / 2 < box.maxWidth / 2;
            final openUp = pos.dy + widget.size / 2 > box.maxHeight / 2;

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
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                          maxWidth: (box.maxWidth - _kEdge * 2)
                              .clamp(0, double.infinity)),
                      child: _actions(context, onLeft: onLeft, openUp: openUp),
                    ),
                  ),
                AnimatedPositioned(
                  duration: _dragPos == null
                      ? const Duration(milliseconds: 220)
                      : Duration.zero,
                  curve: Curves.easeOutCubic,
                  left: pos.dx,
                  top: pos.dy,
                  child: GestureDetector(
                    key: const ValueKey('siagasos-fab'),
                    onPanStart: (_) => setState(() => _dragPos = pos),
                    onPanUpdate: (d) => setState(() {
                      final p = (_dragPos ?? pos) + d.delta;
                      _dragPos = Offset(
                          p.dx.clamp(
                              _kEdge, box.maxWidth - _kEdge - widget.size),
                          p.dy.clamp(minY, maxY));
                    }),
                    onPanEnd: (_) {
                      final p = _dragPos ?? pos;
                      setState(() {
                        _left = p.dx + widget.size / 2 < box.maxWidth / 2;
                        _yFrac = maxY > minY
                            ? ((p.dy - minY) / (maxY - minY)).clamp(0.0, 1.0)
                            : 1;
                        _dragPos = null;
                      });
                      _savePosition();
                    },
                    child: _siren == null
                        ? _fab(false)
                        : ValueListenableBuilder<bool>(
                            valueListenable: _siren!.active,
                            builder: (_, on, __) => _fab(on)),
                  ),
                ),
              ]),
            );
          }),
        ),
      ),
      // Lembar punya Overlay sendiri: tombol ini dipasang di MaterialApp.builder (di atas Navigator),
      // sementara TextField butuh Overlay untuk handle seleksi.
      if (_sheet != null)
        Positioned.fill(
          key: const ValueKey('siagasos-layer-sheet'),
          child: Offstage(
              offstage: _capturing,
              child:
                  Overlay(key: ObjectKey(_sheet), initialEntries: [_sheet!])),
        ),
    ]);
  }

  /// [sirenOn] = sirene berbunyi: tombol menjadi "SENYAP" (ketuk = matikan), seperti tata-warga.
  Widget _fab(bool sirenOn) {
    final busy = !sirenOn && _sending;
    final colors = [
      widget.color,
      Color.lerp(widget.color, Colors.black, 0.28)!
    ];
    return Semantics(
      button: true,
      label: sirenOn
          ? 'Matikan sirene'
          : (_open ? 'Tutup menu darurat' : 'Menu darurat SOS'),
      value: _report != null ? _statusText : null,
      child: AnimatedScale(
        scale: _dragPos != null ? 1.08 : 1,
        duration: const Duration(milliseconds: 150),
        child: Stack(clipBehavior: Clip.none, children: [
          Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                  colors: colors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: [
                BoxShadow(
                    color: colors.last.withValues(alpha: 0.42),
                    blurRadius: 12,
                    offset: const Offset(0, 5))
              ],
            ),
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: sirenOn
                    ? () {
                        HapticFeedback.selectionClick();
                        _siren!.stop();
                      }
                    : _toggle,
                child: Center(
                  child: busy
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.4, color: Colors.white))
                      : Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(
                              sirenOn
                                  ? Icons.volume_off_rounded
                                  : (_open
                                      ? Icons.close_rounded
                                      : Icons.notifications_active_rounded),
                              color: Colors.white,
                              size: widget.size * 0.4),
                          SizedBox(height: widget.size * 0.02),
                          Text(sirenOn ? 'SENYAP' : (_open ? 'TUTUP' : 'SOS'),
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: widget.size * 0.156,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.4,
                                  height: 1)),
                        ]),
                ),
              ),
            ),
          ),
          // Titik kecil = ada SOS yang belum selesai (menu tetap sama seperti tata-warga; status di keterangan menu).
          if (_active && !sirenOn)
            Positioned(
              right: -1,
              top: -1,
              child: Container(
                key: const ValueKey('siagasos-fab-active'),
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
        ]),
      ),
    );
  }

  /// Menu awal ala speed-dial (gaya `DraggableSosMenu` tata-warga). Dari atas ke tombol bulat:
  /// kirim SOS (EWS), telepon pertama, telepon kedua, lalu **Laporan** yang membuka sub-menu
  /// Pengaduan / Riwayat laporan (non-darurat, sengaja satu ketukan lebih jauh).
  Widget _actions(BuildContext context,
      {required bool onLeft, required bool openUp}) {
    final cfg = _cfg;
    final first = cfg?.fallbackPhone ?? '110';
    final second =
        widget.secondaryPhone != null && widget.secondaryPhone != first
            ? widget.secondaryPhone
            : null;
    final complaint = widget.complaint;
    final history = widget.history;
    final contacts = widget.emergencyContacts;
    final subOptions = [
      if (contacts) _openContacts,
      if (history) _openHistory,
      if (complaint) _openComplaint
    ];
    if (_reportMenu) {
      return _Pop(
        key: const ValueKey('siagasos-report-panel'),
        index: 0,
        child: _ReportPanel(
          label: widget.reportLabel,
          onBack: () => setState(() => _reportMenu = false),
          rows: [
            if (complaint)
              _PanelRow(ValueKey('siagasos-complaint'), widget.complaintLabel,
                  Icons.campaign_rounded, const Color(0xFFEA580C)),
            if (history)
              const _PanelRow(ValueKey('siagasos-history'), 'Riwayat laporan',
                  Icons.history_rounded, Color(0xFF475569)),
            if (contacts)
              _PanelRow(ValueKey('siagasos-contacts'), widget.contactsLabel,
                  Icons.contact_phone_rounded, Color(0xFF2563EB)),
          ],
          onTap: (key) => switch (key) {
            const ValueKey('siagasos-complaint') => _openComplaint(),
            const ValueKey('siagasos-history') => _openHistory(),
            _ => _openContacts(),
          },
        ),
      );
    }
    // Urutan daftar = dari tombol bulat ke luar (dibalik saat menu membuka ke atas).
    final items = <Widget>[
      if (subOptions.isNotEmpty)
        _ActionButton(
          key: const ValueKey('siagasos-report'),
          label: widget.reportLabel,
          compact: widget.compact,
          icon: Icons.assignment_rounded,
          colors: const [
            Color(0xFFFDBA74),
            Color(0xFFFB923C),
            Color(0xFFEA580C)
          ],
          // Hanya satu pilihan yang aktif → langsung buka tanpa sub-menu.
          onTap: subOptions.length > 1
              ? () => setState(() => _reportMenu = true)
              : subOptions.first,
        ),
      if (widget.onCall != null) ...[
        if (second != null)
          _ActionButton(
            label: '${widget.callLabel} $second',
            compact: widget.compact,
            icon: Icons.emergency_rounded,
            colors: const [
              Color(0xFF6EE7B7),
              Color(0xFF34D399),
              Color(0xFF059669)
            ],
            onTap: () => widget.onCall!(second),
          ),
        _ActionButton(
          label: widget.firstCallLabel ??
              '${widget.callLabel} $first${first == '110' ? ' Polri' : ''}',
          compact: widget.compact,
          image: widget.firstCallImage,
          icon: Icons.local_police_rounded,
          colors: widget.callColors ??
              const [Color(0xFF818CF8), Color(0xFF6366F1), Color(0xFF4F46E5)],
          onTap: () => widget.onCall!(first),
        ),
      ],
      _HoldToSend(
        hold: _hold,
        seconds: _seconds,
        colors: widget.sosColors ??
            [
              Color.lerp(widget.color, Colors.white, 0.12)!,
              Color.lerp(widget.color, Colors.black, 0.3)!
            ],
        sending: _sending,
        compact: widget.compact,
        onTap: _fire,
        label: widget.sosLabel ?? defaultSosMenuLabel(cfg?.buttonText),
      ),
    ];
    // Hanya pesan penting: status SOS aktif cukup ditandai titik di tombol bulat.
    final note = <String>[
      if (_notice != null) _notice!,
      if (widget.client.mode == SosMode.test) 'MODE TEST',
    ];
    final ordered = openUp ? items.reversed.toList() : items;
    final caption = note.isEmpty
        ? null
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
                color: const Color(0xE6111827),
                borderRadius: BorderRadius.circular(10)),
            child: Text(note.join(' · '),
                style: TextStyle(
                    color: _notice != null
                        ? const Color(0xFFFCA5A5)
                        : Colors.white,
                    fontSize: 11.5,
                    height: 1.3)),
          );
    // Lebar = label terpanjang (tanpa ruang kosong), semua tombol sama lebar supaya rapi.
    // Keterangan (error / MODE TEST) di luar IntrinsicWidth supaya tidak ikut melebarkan tombol.
    final buttons = IntrinsicWidth(
      key: const ValueKey('siagasos-actions'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < ordered.length; i++) ...[
            if (i > 0) const SizedBox(height: 6),
            _Pop(index: openUp ? ordered.length - 1 - i : i, child: ordered[i]),
          ],
        ],
      ),
    );
    if (caption == null) return buttons;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          onLeft ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      children: [
        if (openUp) ...[
          ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220), child: caption),
          const SizedBox(height: 8)
        ],
        buttons,
        if (!openUp) ...[
          const SizedBox(height: 8),
          ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220), child: caption)
        ],
      ],
    );
  }
}

const _kActionHeight = 42.0;
const _kCompactHeight = 40.0;
const _kActionRadius = 11.0;
const _kActionText =
    TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600);

const _kCompactRadius = 20.0;

BoxDecoration _actionDecoration(List<Color> colors,
        {double radius = _kActionRadius, Color? border}) =>
    BoxDecoration(
      gradient: LinearGradient(
          colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
      borderRadius: BorderRadius.circular(radius),
      border: border != null
          ? Border.all(color: border, width: 1.5)
          : Border.all(color: Colors.white.withValues(alpha: 0.25)),
      boxShadow: [
        BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 6,
            offset: const Offset(0, 2))
      ],
    );

/// Muncul bertahap saat menu dibuka.
class _Pop extends StatelessWidget {
  const _Pop({super.key, required this.index, required this.child});
  final int index;
  final Widget child;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 180 + index * 50),
        curve: Curves.easeOutBack,
        builder: (context, t, c) => Opacity(
            opacity: t.clamp(0.0, 1.0),
            child: Transform.scale(scale: 0.85 + 0.15 * t, child: c)),
        child: child,
      );
}

/// Lingkaran putih transparan di belakang ikon tombol aksi.
class _IconChip extends StatelessWidget {
  const _IconChip(this.icon, {this.size = 30, this.solid = false, this.accent});
  final IconData icon;
  final double size;

  /// Lingkaran putih solid dengan ikon berwarna [accent] (mode compact).
  final bool solid;
  final Color? accent;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
            color: solid ? Colors.white : Colors.white.withValues(alpha: 0.22),
            shape: BoxShape.circle,
            border: solid ? Border.all(color: Colors.black, width: 1.5) : null),
        child: Icon(icon,
            color: solid ? (accent ?? Colors.white) : Colors.white,
            size: size * 17 / 30),
      );
}

class _PanelRow {
  const _PanelRow(this.key, this.label, this.icon, this.color);
  final ValueKey<String> key;
  final String label;
  final IconData icon;
  final Color color;
}

/// Sub-menu "Laporan": satu kartu putih ringkas (judul ← Laporan, lalu baris pilihan), lebar mengikuti isi.
class _ReportPanel extends StatelessWidget {
  const _ReportPanel(
      {required this.label,
      required this.onBack,
      required this.rows,
      required this.onTap});
  final String label;
  final VoidCallback onBack;
  final List<_PanelRow> rows;
  final void Function(ValueKey<String> key) onTap;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF1F2937);
    Widget row(
            {Key? key,
            required Widget leading,
            required String label,
            required VoidCallback onTap,
            TextStyle? style}) =>
        InkWell(
          key: key,
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 18, 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              leading,
              const SizedBox(width: 10),
              Flexible(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: style)),
            ]),
          ),
        );
    return IntrinsicWidth(
      child: Material(
        color: Colors.white,
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              row(
                key: const ValueKey('siagasos-back'),
                leading: const SizedBox(
                    width: 30,
                    child:
                        Icon(Icons.arrow_back_rounded, size: 20, color: ink)),
                label: label,
                onTap: onBack,
                style: const TextStyle(
                    color: ink, fontSize: 14, fontWeight: FontWeight.w800),
              ),
              const Divider(height: 1, thickness: 1, color: Color(0xFFE5E7EB)),
              for (final r in rows)
                row(
                  key: r.key,
                  leading: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                        color: r.color.withValues(alpha: 0.12),
                        shape: BoxShape.circle),
                    child: Icon(r.icon, size: 17, color: r.color),
                  ),
                  label: r.label,
                  onTap: () => onTap(r.key),
                  style: const TextStyle(
                      color: ink, fontSize: 14, fontWeight: FontWeight.w600),
                ),
              const SizedBox(height: 4),
            ]),
      ),
    );
  }
}

/// Tombol aksi gradien (gaya menu SOS tata-warga).
class _ActionButton extends StatelessWidget {
  const _ActionButton(
      {super.key,
      required this.label,
      required this.icon,
      required this.colors,
      required this.onTap,
      this.compact = false,
      this.image});
  final String label;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback onTap;
  final bool compact;

  /// Gambar pengganti ikon (mode compact). Null = pakai [icon].
  final ImageProvider? image;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: compact ? _kCompactHeight : _kActionHeight,
        child: DecoratedBox(
          decoration: _actionDecoration(colors,
              radius: compact ? _kCompactRadius : _kActionRadius,
              border: compact ? Colors.black : null),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(
                compact ? _kCompactRadius : _kActionRadius),
            child: InkWell(
              borderRadius: BorderRadius.circular(
                  compact ? _kCompactRadius : _kActionRadius),
              onTap: () {
                HapticFeedback.lightImpact();
                onTap();
              },
              child: Padding(
                padding: EdgeInsets.fromLTRB(compact ? 7 : 6, 0, 16, 0),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (compact && image != null)
                    Container(
                        width: 30,
                        height: 30,
                        decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.fromBorderSide(
                                BorderSide(color: Colors.black, width: 1.5))),
                        child: ClipOval(
                            child: Image(image: image!, width: 30, height: 30)))
                  else
                    _IconChip(icon,
                        size: 30, solid: compact, accent: colors.last),
                  SizedBox(width: compact ? 12 : 10),
                  Flexible(
                      child: Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: compact
                              ? _kActionText.copyWith(
                                  fontSize: 16,
                                  color: Colors.black,
                                  fontWeight: FontWeight.w700)
                              : _kActionText)),
                ]),
              ),
            ),
          ),
        ),
      );
}

/// Bilah "tahan untuk kirim" di dalam menu melayang.
class _HoldToSend extends StatelessWidget {
  const _HoldToSend({
    required this.hold,
    required this.seconds,
    required this.colors,
    required this.sending,
    required this.label,
    required this.onTap,
    this.compact = false,
  });
  final bool compact;
  final AnimationController hold;
  final int seconds;
  final List<Color> colors;
  final bool sending;

  /// Dipakai bila [seconds] = 0: sekali ketuk langsung kirim (gaya EWS tata-warga).
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    final tap = seconds <= 0;
    void down() {
      if (sending || tap) return;
      HapticFeedback.selectionClick();
      hold.duration = Duration(seconds: seconds);
      hold.forward(from: 0);
    }

    void up() {
      if (hold.isAnimating) hold.reverse();
    }

    return Semantics(
      button: true,
      label: tap
          ? '$label. Ketuk untuk mengirim laporan darurat.'
          : '$label. Tahan $seconds detik untuk mengirim laporan darurat.',
      child: GestureDetector(
        key: const ValueKey('siagasos-hold'),
        onTapDown: (_) => down(),
        onTapUp: (_) => tap ? (sending ? null : onTap()) : up(),
        onTapCancel: up,
        child: AnimatedBuilder(
          animation: hold,
          builder: (context, _) => Container(
            height: compact ? _kCompactHeight : _kActionHeight,
            decoration: _actionDecoration(colors,
                radius: compact ? _kCompactRadius : _kActionRadius,
                border: compact ? Colors.black : null),
            clipBehavior: Clip.antiAlias,
            child: Stack(alignment: Alignment.centerLeft, children: [
              // Positioned: lapisan progres tidak ikut menentukan lebar tombol (IntrinsicWidth di menu).
              Positioned.fill(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                      widthFactor: hold.value,
                      heightFactor: 1,
                      child: Container(
                          color: Colors.black.withValues(alpha: 0.22))),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(compact ? 7 : 6, 0, 16, 0),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  sending
                      ? const SizedBox.square(
                          dimension: 30,
                          child: Padding(
                              padding: EdgeInsets.all(6),
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.2, color: Colors.white)),
                        )
                      : _IconChip(Icons.warning_amber_rounded,
                          size: 30, solid: compact, accent: colors.last),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      sending
                          ? 'Mengirim…'
                          : hold.value > 0
                              ? 'Tahan… ${(seconds * (1 - hold.value)).ceil()}'
                              : label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _kActionText.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: compact ? 16 : 14,
                          color: compact ? Colors.black : Colors.white),
                    ),
                  ),
                  if (!sending && !tap && hold.value == 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(6)),
                      child: Text('tahan ${seconds}d',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700)),
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

/// Form "Pengaduan" (non-darurat), disamakan dengan Lapor Keamanan tata-warga: foto/video bukti (min. 1),
/// jenis, judul, kronologi, lokasi & waktu kejadian, ciri pelaku, dan saksi. Tampilan: kartu per bagian.
class _ComplaintSheet extends StatefulWidget {
  const _ComplaintSheet({
    required this.client,
    required this.label,
    required this.categories,
    required this.onCapture,
    required this.onCapturing,
    required this.onClose,
    this.onSent,
    this.onError,
  });
  final SiagaSOS client;

  /// Judul sheet & menu (mis. 'Pengaduan 110').
  final String label;
  final List<String> categories;
  final MediaCapture? onCapture;
  final ValueChanged<bool> onCapturing;
  final VoidCallback onClose;
  final void Function(ActiveReport report)? onSent;
  final void Function(SiagaSOSError error)? onError;

  @override
  State<_ComplaintSheet> createState() => _ComplaintSheetState();
}

class _ComplaintSheetState extends State<_ComplaintSheet> {
  static const _amber = Color(0xFFD97706);
  static const _amberSoft = Color(0xFFFFFBEB);
  static const _amberBorder = Color(0xFFFDE68A);
  static const _ink = Color(0xFF111827);
  static const _muted = Color(0xFF6B7280);
  static const _line = Color(0xFFE5E7EB);
  static const _green = Color(0xFF16A34A);
  // Batas sama dengan Lapor Keamanan tata-warga (MEDIA_LIMITS: foto 5, video 2, video maks. 5 dtk).
  static const _maxImages = 5;
  static const _maxVideos = 2;
  static const _minDescription = 5;
  static const _maxDaysBack = 30;
  // Sama dengan batas server (config.media.maxBytes): ditolak di awal, bukan setelah laporan terkirim.
  static const _maxImageBytes = 10 * 1024 * 1024;
  static const _maxVideoBytes = 60 * 1024 * 1024;
  static const _uploadConcurrency = 3;
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Agu',
    'Sep',
    'Okt',
    'Nov',
    'Des'
  ];

  late String _category =
      widget.categories.isNotEmpty ? widget.categories.first : 'lainnya';
  bool _categoryOpen = false;
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _location = TextEditingController();
  final _suspect = TextEditingController();
  final _witness = TextEditingController();
  // Default: waktu sekarang (saat lembar dibuka). null = saat laporan dikirim (lewat tombol hapus).
  DateTime? _occurredAt = DateTime.now();
  final List<CapturedMedia> _media = [];
  bool _sending = false;
  ActiveReport? _report;
  double?
      _upload; // progres gabungan semua unggahan (0..1); null = tidak ada unggahan berjalan
  int _uploadTotal = 0;
  int _mediaSent = 0;
  List<CapturedMedia> _failed =
      const []; // lampiran yang gagal diunggah, bisa dicoba ulang
  String? _error;
  StreamSubscription<ActiveReport>? _sub;

  @override
  void initState() {
    super.initState();
    for (final c in [_title, _description, _location, _suspect, _witness]) {
      c.addListener(() => setState(() {}));
    }
    _sub = widget.client.status.listen((r) {
      if (mounted && _report?.localId == r.localId) setState(() => _report = r);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    for (final c in [_title, _description, _location, _suspect, _witness]) {
      c.dispose();
    }
    super.dispose();
  }

  int get _imageCount => _media.where((m) => !_isVideo(m)).length;
  int get _videoCount => _media.where(_isVideo).length;
  static bool _isVideo(CapturedMedia m) => m.contentType.startsWith('video/');

  bool get _valid =>
      _category.isNotEmpty &&
      _title.text.trim().isNotEmpty &&
      _title.text.trim().length <= 120 &&
      _description.text.trim().length >= _minDescription &&
      _media.isNotEmpty;

  /// Jenis lampiran yang sedang menunggu pilihan sumber (Galeri / Kamera); null = tidak ada.
  MediaKind? _choosing;

  void _startPick(MediaKind kind) {
    final limitReached = kind == MediaKind.video
        ? _videoCount >= _maxVideos
        : _imageCount >= _maxImages;
    if (limitReached || _sending) return;
    setState(() => _choosing = _choosing == kind ? null : kind);
  }

  Future<void> _addMedia(MediaKind kind, MediaSource source) async {
    setState(() => _choosing = null);
    if (_sending) return;
    CapturedMedia? m;
    widget.onCapturing(true);
    try {
      m = await widget.onCapture?.call(context, kind, source);
    } catch (_) {
      m = null;
    } finally {
      widget.onCapturing(false);
    }
    if (m == null || !mounted) return;
    final max = _isVideo(m) ? _maxVideoBytes : _maxImageBytes;
    if (m.bytes.length > max) {
      setState(() => _error =
          '${_isVideo(m!) ? 'Video' : 'Foto'} terlalu besar (${(m.bytes.length / 1024 / 1024).toStringAsFixed(1)} MB). '
              'Maksimal ${max ~/ (1024 * 1024)} MB.');
      return;
    }
    setState(() {
      _error = null;
      _media.add(m!);
    });
  }

  Widget _sourceChooser(ThemeData theme, MediaKind kind) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(
          kind == MediaKind.video
              ? 'Pilih video dari mana?'
              : 'Pilih foto dari mana?',
          style: theme.textTheme.labelLarge?.copyWith(color: _ink)),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            key: const ValueKey('siagasos-complaint-source-gallery'),
            onPressed: () => _addMedia(kind, MediaSource.gallery),
            icon: const Icon(Icons.photo_library_rounded, size: 18),
            label: const Text('Galeri'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            key: const ValueKey('siagasos-complaint-source-camera'),
            onPressed: () => _addMedia(kind, MediaSource.camera),
            icon: const Icon(Icons.photo_camera_rounded, size: 18),
            label: Text(kind == MediaKind.video ? 'Kamera (5 dtk)' : 'Kamera'),
          ),
        ),
        IconButton(
          onPressed: () => setState(() => _choosing = null),
          icon: const Icon(Icons.close_rounded),
          tooltip: 'Batal',
        ),
      ]),
    ]);
  }

  Future<void> _pickOccurredAt() async {
    final now = DateTime.now();
    final initial = _occurredAt ?? now;
    final date = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(now) ? now : initial,
      firstDate: now.subtract(const Duration(days: _maxDaysBack)),
      lastDate: now,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (time == null || !mounted) return;
    var picked =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (picked.isAfter(DateTime.now())) picked = DateTime.now();
    setState(() => _occurredAt = picked);
  }

  String _fmtOccurredAt(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final l = d.toLocal();
    return '${l.day} ${_months[l.month - 1]} ${l.year}, ${two(l.hour)}.${two(l.minute)}';
  }

  ComplaintDetails _details() => ComplaintDetails(
        title: _title.text,
        description: _description.text,
        locationText: _location.text,
        occurredAt: _occurredAt,
        suspect: _suspect.text,
        witness: _witness.text,
      );

  Future<void> _send() async {
    if (!_valid || _sending) return;
    FocusScope.of(context).unfocus();
    final media = List<CapturedMedia>.of(_media);
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final r = await widget.client.complain(
          category: _category, message: _description.text, details: _details());
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      setState(() => _report = r);
      if (r.id != null) widget.onSent?.call(r);
      await _uploadAll(r, media);
    } on SiagaSOSError catch (e) {
      if (mounted) setState(() => _error = e.message);
      widget.onError?.call(e);
    } catch (e) {
      final err =
          SiagaSOSError(0, 'unexpected', 'Gagal mengirim pengaduan: $e');
      if (mounted) setState(() => _error = err.message);
      widget.onError?.call(err);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Unggah lampiran paralel (maks. [_uploadConcurrency] sekaligus). Satu lampiran gagal tidak menghentikan
  /// yang lain; yang gagal disimpan di [_failed] untuk tombol "Unggah ulang".
  Future<void> _uploadAll(ActiveReport r, List<CapturedMedia> media) async {
    if (media.isEmpty) return;
    final total = media.fold<int>(0, (n, m) => n + m.bytes.length);
    final progress = List<double>.filled(media.length, 0);
    final failed = <CapturedMedia>[];
    String? firstError;
    setState(() {
      _upload = 0;
      _uploadTotal = media.length;
      _failed = const [];
      _error = null;
    });
    void report() {
      if (!mounted) return;
      var done = 0.0;
      for (var i = 0; i < media.length; i++) {
        done += progress[i] * media[i].bytes.length;
      }
      setState(() => _upload = total == 0 ? 1 : done / total);
    }

    var next = 0;
    Future<void> worker() async {
      while (next < media.length) {
        final i = next++;
        final m = media[i];
        try {
          await widget.client.attach(r.localId, m.bytes,
              contentType: m.contentType,
              durationS: m.durationS, onProgress: (p) {
            progress[i] = p;
            report();
          });
          if (mounted) setState(() => _mediaSent++);
        } catch (e) {
          failed.add(m);
          firstError ??= e is SiagaSOSError ? e.message : '$e';
          progress[i] = 1;
          report();
        }
      }
    }

    await Future.wait(
        List.generate(min(_uploadConcurrency, media.length), (_) => worker()));
    if (!mounted) return;
    setState(() {
      _upload = null;
      _failed = failed;
      if (failed.isNotEmpty) {
        _error =
            'Pengaduan terkirim, tetapi ${failed.length} dari ${media.length} lampiran gagal diunggah: $firstError';
      }
    });
  }

  Future<void> _retryFailed() async {
    final r = _report;
    if (r == null || _failed.isEmpty || _sending) return;
    final media = List<CapturedMedia>.of(_failed);
    setState(() => _sending = true);
    try {
      await _uploadAll(r, media);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String get _statusText {
    final r = _report!;
    return switch (r.status) {
      SosStatus.queued =>
        'Belum ada sinyal. Pengaduan disimpan dan dikirim otomatis.',
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

  // ---------- komponen tampilan ----------

  /// Kartu satu bagian: ikon + judul di kepala, lalu isi. [required] menambah tanda * dan [trailing] di kanan.
  Widget _card(ThemeData theme,
      {required IconData icon,
      required String title,
      required Widget child,
      bool required = false,
      Widget? trailing}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _line),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
                color: _amberSoft, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 17, color: _amber),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(TextSpan(
              text: title,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700, color: _ink),
              children: [
                if (required)
                  const TextSpan(
                      text: ' *', style: TextStyle(color: Color(0xFFDC2626))),
              ],
            )),
          ),
          if (trailing != null) trailing,
        ]),
        const SizedBox(height: 12),
        child,
      ]),
    );
  }

  InputDecoration _deco(ThemeData theme, String hint, {IconData? icon}) =>
      InputDecoration(
        hintText: hint,
        hintStyle:
            theme.textTheme.bodySmall?.copyWith(color: const Color(0xFF9CA3AF)),
        prefixIcon: icon == null ? null : Icon(icon, size: 19, color: _muted),
        filled: true,
        fillColor: const Color(0xFFF9FAFB),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _line)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _line)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _amber, width: 1.4)),
      );

  Widget _counter(ThemeData theme, int n, int max) => Text('$n/$max',
      style: theme.textTheme.labelSmall?.copyWith(
          color: n > max ? const Color(0xFFDC2626) : _muted,
          fontWeight: FontWeight.w600));

  /// Header gradien kuning-jingga (ikon, judul, catatan non-darurat, tutup).
  Widget _header(ThemeData theme) => Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xFFFBBF24), _amber],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.campaign_rounded,
                color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.label,
                  style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800, color: Colors.white)),
              Text('Laporkan masalah lingkungan. Bukan untuk keadaan darurat.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: Colors.white.withValues(alpha: 0.92))),
            ]),
          ),
          IconButton(
            onPressed: _sending ? null : widget.onClose,
            icon: const Icon(Icons.close_rounded, color: Colors.white),
            tooltip: 'Tutup',
          ),
        ]),
      );

  Widget _form(ThemeData theme) {
    final mediaFull = _imageCount >= _maxImages && _videoCount >= _maxVideos;
    final desc = _description.text.trim().length;
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _grip(theme),
          _header(theme),
          const SizedBox(height: 12),
          // Bukti: kartu pertama, paling penting.
          _card(
            theme,
            icon: Icons.perm_media_rounded,
            title: 'Foto / Video kejadian',
            required: true,
            trailing: _pill(theme, '${_imageCount + _videoCount} bukti',
                ok: _media.isNotEmpty),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  'Minimal 1 bukti. Foto maks. $_maxImages, video maks. $_maxVideos (5 detik).',
                  style: theme.textTheme.bodySmall?.copyWith(color: _muted)),
              const SizedBox(height: 10),
              Wrap(spacing: 10, runSpacing: 10, children: [
                for (var i = 0; i < _media.length; i++) _mediaTile(theme, i),
                if (!mediaFull &&
                    widget.onCapture != null &&
                    _choosing == null) ...[
                  if (_imageCount < _maxImages)
                    _addTile(theme, Icons.add_a_photo_rounded, 'Foto',
                        _sending ? null : () => _startPick(MediaKind.image)),
                  if (_videoCount < _maxVideos)
                    _addTile(theme, Icons.videocam_rounded, 'Video',
                        _sending ? null : () => _startPick(MediaKind.video)),
                ],
              ]),
              if (_choosing != null) ...[
                const SizedBox(height: 12),
                _sourceChooser(theme, _choosing!),
              ],
            ]),
          ),
          const SizedBox(height: 12),
          _card(
            theme,
            icon: Icons.category_rounded,
            title: 'Jenis pengaduan',
            required: true,
            child: _categoryDropdown(theme),
          ),
          const SizedBox(height: 12),
          _card(
            theme,
            icon: Icons.title_rounded,
            title: 'Judul pengaduan',
            required: true,
            trailing: _counter(theme, _title.text.trim().length, 120),
            child: TextField(
              key: const ValueKey('siagasos-complaint-title'),
              controller: _title,
              enabled: !_sending,
              maxLength: 120,
              buildCounter: (_,
                      {required currentLength,
                      required isFocused,
                      maxLength}) =>
                  const SizedBox.shrink(),
              textCapitalization: TextCapitalization.sentences,
              decoration:
                  _deco(theme, 'Contoh: Motor parkir menutup gang Mawar'),
            ),
          ),
          const SizedBox(height: 12),
          _card(
            theme,
            icon: Icons.notes_rounded,
            title: 'Kronologi',
            required: true,
            trailing: _counter(theme, desc, 1000),
            child: TextField(
              key: const ValueKey('siagasos-complaint-text'),
              controller: _description,
              enabled: !_sending,
              minLines: 3,
              maxLines: 6,
              maxLength: 1000,
              buildCounter: (_,
                      {required currentLength,
                      required isFocused,
                      maxLength}) =>
                  const SizedBox.shrink(),
              textCapitalization: TextCapitalization.sentences,
              decoration: _deco(theme,
                  'Ceritakan apa yang terjadi, urutannya, dan sejak kapan...'),
            ),
          ),
          const SizedBox(height: 12),
          _card(
            theme,
            icon: Icons.place_rounded,
            title: 'Lokasi & waktu kejadian',
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    key: const ValueKey('siagasos-complaint-location'),
                    controller: _location,
                    enabled: !_sending,
                    maxLength: 200,
                    buildCounter: (_,
                            {required currentLength,
                            required isFocused,
                            maxLength}) =>
                        const SizedBox.shrink(),
                    textCapitalization: TextCapitalization.sentences,
                    decoration: _deco(theme, 'Mis. Pos ronda Blok C',
                        icon: Icons.location_on_outlined),
                  ),
                  const SizedBox(height: 10),
                  InkWell(
                    key: const ValueKey('siagasos-complaint-time'),
                    borderRadius: BorderRadius.circular(14),
                    onTap: _sending ? null : _pickOccurredAt,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _line),
                      ),
                      child: Row(children: [
                        const Icon(Icons.schedule_rounded,
                            size: 19, color: _muted),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _occurredAt == null
                                ? 'Waktu kejadian: saat laporan dikirim'
                                : 'Waktu kejadian: ${_fmtOccurredAt(_occurredAt!)}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                                color: _occurredAt == null ? _muted : _ink),
                          ),
                        ),
                        if (_occurredAt != null)
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Hapus waktu kejadian',
                            onPressed: _sending
                                ? null
                                : () => setState(() => _occurredAt = null),
                            icon: const Icon(Icons.close_rounded, size: 18),
                          )
                        else
                          const Icon(Icons.edit_calendar_rounded,
                              size: 18, color: _amber),
                      ]),
                    ),
                  ),
                ]),
          ),
          const SizedBox(height: 12),
          _card(
            theme,
            icon: Icons.person_search_rounded,
            title: 'Ciri pelaku & saksi',
            trailing: Text('opsional',
                style: theme.textTheme.labelSmall?.copyWith(color: _muted)),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    key: const ValueKey('siagasos-complaint-suspect'),
                    controller: _suspect,
                    enabled: !_sending,
                    minLines: 2,
                    maxLines: 4,
                    maxLength: 500,
                    buildCounter: (_,
                            {required currentLength,
                            required isFocused,
                            maxLength}) =>
                        const SizedBox.shrink(),
                    textCapitalization: TextCapitalization.sentences,
                    decoration: _deco(theme,
                        'Ciri orang, pakaian, kendaraan, pelat nomor...'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const ValueKey('siagasos-complaint-witness'),
                    controller: _witness,
                    enabled: !_sending,
                    maxLength: 300,
                    buildCounter: (_,
                            {required currentLength,
                            required isFocused,
                            maxLength}) =>
                        const SizedBox.shrink(),
                    textCapitalization: TextCapitalization.words,
                    decoration: _deco(theme, 'Nama / nomor HP saksi',
                        icon: Icons.groups_2_outlined),
                  ),
                ]),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            _notice(theme, _error!, error: true),
          ],
          const SizedBox(height: 16),
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: _valid && !_sending
                  ? const LinearGradient(colors: [Color(0xFFFBBF24), _amber])
                  : null,
              color: _valid && !_sending ? null : const Color(0xFFE5E7EB),
            ),
            child: FilledButton.icon(
              key: const ValueKey('siagasos-complaint-send'),
              onPressed: _valid && !_sending ? _send : null,
              icon: _sending
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.2, color: Colors.white))
                  : const Icon(Icons.send_rounded),
              label: Text(_sending ? 'Mengirim…' : 'Kirim pengaduan',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.transparent,
                disabledBackgroundColor: Colors.transparent,
                foregroundColor: Colors.white,
                disabledForegroundColor: _muted,
                minimumSize: const Size.fromHeight(54),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
          if (!_valid && !_sending)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_hint(),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: _muted)),
            ),
          if (widget.client.mode == SosMode.test)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('MODE TEST',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.amber.shade800,
                      fontWeight: FontWeight.w700,
                      fontSize: 11)),
            ),
        ]);
  }

  /// Penjelasan singkat apa yang belum lengkap (muncul di bawah tombol kirim).
  String _hint() {
    if (_media.isEmpty) return 'Tambahkan minimal 1 foto atau video';
    if (_title.text.trim().isEmpty) return 'Isi judul pengaduan';
    if (_description.text.trim().length < _minDescription)
      return 'Kronologi minimal $_minDescription karakter';
    return '';
  }

  Widget _pill(ThemeData theme, String text, {required bool ok}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: ok ? const Color(0xFFDCFCE7) : const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(text,
            style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700, color: ok ? _green : _muted)),
      );

  /// Ikon per kategori bawaan; slug kustom dari portal memakai ikon umum.
  static IconData _categoryIcon(String slug) => switch (slug) {
        'ketertiban' => Icons.gavel_rounded,
        'kebisingan' => Icons.volume_up_rounded,
        'parkir_liar' => Icons.local_parking_rounded,
        'pungli' => Icons.money_off_rounded,
        'kehilangan' => Icons.search_off_rounded,
        'patroli' => Icons.local_police_rounded,
        _ => Icons.label_rounded,
      };

  /// Dropdown jenis pengaduan. Sengaja bukan DropdownButton: tombol SOS dipasang di MaterialApp.builder
  /// (di atas Navigator), sedangkan menu DropdownButton butuh Navigator → crash. Daftar dibuka inline.
  Widget _categoryDropdown(ThemeData theme) {
    final items =
        widget.categories.isNotEmpty ? widget.categories : const ['lainnya'];
    final value = items.contains(_category) ? _category : items.first;
    final open = _categoryOpen && !_sending;

    Widget badge(String c) => Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
              color: _amberSoft, borderRadius: BorderRadius.circular(9)),
          child: Icon(_categoryIcon(c), size: 17, color: _amber),
        );

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: open ? _amber : _line, width: open ? 1.4 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                button: true,
                expanded: open,
                label: 'Jenis pengaduan: ${complaintCategoryLabel(value)}',
                child: InkWell(
                  key: const ValueKey('siagasos-complaint-category'),
                  onTap: _sending
                      ? null
                      : () => setState(() => _categoryOpen = !_categoryOpen),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
                    child: Row(children: [
                      badge(value),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(complaintCategoryLabel(value),
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                                color: _ink, fontWeight: FontWeight.w700)),
                      ),
                      AnimatedRotation(
                        turns: open ? 0.5 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: Icon(Icons.keyboard_arrow_down_rounded,
                            color: _sending ? _muted : _amber),
                      ),
                    ]),
                  ),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: !open
                    ? const SizedBox(width: double.infinity)
                    : Container(
                        color: Colors.white,
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          const Divider(height: 1, color: _line),
                          for (final c in items)
                            InkWell(
                              onTap: () => setState(() {
                                _category = c;
                                _categoryOpen = false;
                              }),
                              child: Container(
                                color: c == value ? _amberSoft : null,
                                padding:
                                    const EdgeInsets.fromLTRB(10, 8, 12, 8),
                                child: Row(children: [
                                  badge(c),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(complaintCategoryLabel(c),
                                        style: theme
                                            .textTheme.bodyMedium
                                            ?.copyWith(
                                                color: c ==
                                                        value
                                                    ? const Color(0xFF92400E)
                                                    : _ink,
                                                fontWeight: c == value
                                                    ? FontWeight.w700
                                                    : FontWeight.w500)),
                                  ),
                                  if (c == value)
                                    const Icon(Icons.check_rounded,
                                        size: 18, color: _amber),
                                ]),
                              ),
                            ),
                        ]),
                      ),
              ),
            ]),
      ),
    );
  }

  Widget _notice(ThemeData theme, String text, {bool error = false}) =>
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: error ? const Color(0xFFFEF2F2) : _amberSoft,
          borderRadius: BorderRadius.circular(14),
          border:
              Border.all(color: error ? const Color(0xFFFECACA) : _amberBorder),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(error ? Icons.error_outline_rounded : Icons.info_outline_rounded,
              size: 18, color: error ? theme.colorScheme.error : _amber),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text,
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: error ? theme.colorScheme.error : _ink))),
        ]),
      );

  Widget _addTile(
          ThemeData theme, IconData icon, String label, VoidCallback? onTap) =>
      Semantics(
        button: true,
        label: 'Tambah $label',
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              color: _amberSoft,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _amberBorder, width: 1.4),
            ),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: onTap == null ? _muted : _amber, size: 26),
                  const SizedBox(height: 6),
                  Text('+ $label',
                      style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: onTap == null
                              ? _muted
                              : const Color(0xFF92400E))),
                ]),
          ),
        ),
      );

  Widget _mediaTile(ThemeData theme, int i) {
    final m = _media[i];
    final video = _isVideo(m);
    return SizedBox(
      width: 92,
      height: 92,
      child: Stack(fit: StackFit.expand, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: video
              ? Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                        colors: [Color(0xFF374151), Color(0xFF111827)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.play_circle_fill_rounded,
                      color: Colors.white, size: 34),
                )
              : Image.memory(m.bytes,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.image_rounded))),
        ),
        Positioned(
          left: 6,
          bottom: 6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
                color: const Color(0xB3111827),
                borderRadius: BorderRadius.circular(6)),
            child: Text(video ? 'VIDEO' : 'FOTO',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4)),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: Semantics(
            button: true,
            label: 'Hapus bukti',
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _sending ? null : () => setState(() => _media.removeAt(i)),
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                    color: Color(0xE6111827), shape: BoxShape.circle),
                child: const Icon(Icons.close_rounded,
                    size: 14, color: Colors.white),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _done(ThemeData theme) {
    final r = _report!;
    final queued = r.status == SosStatus.queued;
    final tone = queued ? _amber : _green;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      _grip(theme),
      Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
            shape: BoxShape.circle, color: tone.withValues(alpha: 0.12)),
        child: Icon(
            queued ? Icons.schedule_send_rounded : Icons.check_circle_rounded,
            size: 40,
            color: tone),
      ),
      const SizedBox(height: 14),
      Text(queued ? 'Pengaduan disimpan' : 'Pengaduan terkirim',
          style: theme.textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      Text(_statusText,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: _muted)),
      if (r.id != null) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(10)),
          child: Text(
              'No. ${(r.id!.length > 8 ? r.id!.substring(0, 8) : r.id!).toUpperCase()} · ${complaintCategoryLabel(r.category)}',
              style: theme.textTheme.labelMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
        ),
      ],
      if (_upload != null) ...[
        const SizedBox(height: 16),
        Text(
            r.id == null
                ? 'Menunggu sinyal untuk mengunggah $_uploadTotal bukti…'
                : 'Mengunggah $_uploadTotal bukti… ${((_upload ?? 0) * 100).round()}%',
            style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
              value: r.id == null ? null : _upload,
              color: _amber,
              backgroundColor: _amberSoft,
              minHeight: 6),
        ),
      ] else if (_mediaSent > 0) ...[
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.check_rounded, size: 18, color: _green),
          const SizedBox(width: 4),
          Text('$_mediaSent bukti terlampir', style: theme.textTheme.bodySmall),
        ]),
      ],
      if (_error != null) ...[
        const SizedBox(height: 12),
        _notice(theme, _error!, error: true),
      ],
      if (_failed.isNotEmpty && _upload == null) ...[
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const ValueKey('siagasos-complaint-retry-media'),
          onPressed: _sending ? null : _retryFailed,
          icon: const Icon(Icons.refresh_rounded),
          label: Text('Unggah ulang ${_failed.length} bukti'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(46),
            foregroundColor: _amber,
            side: const BorderSide(color: _amber),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ],
      const SizedBox(height: 18),
      FilledButton(
        onPressed: _upload != null ? null : widget.onClose,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          backgroundColor: _amber,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child:
            const Text('Tutup', style: TextStyle(fontWeight: FontWeight.w700)),
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
          decoration: BoxDecoration(
              color: theme.colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2)),
        ),
      );
}

/// Latar gelap + lembar yang naik dari bawah layar (dipakai form pengaduan dan riwayat).
class _SheetFrame extends StatelessWidget {
  const _SheetFrame(
      {required this.sheetKey,
      required this.onDismiss,
      required this.child,
      this.scroll = true});
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
    final padding =
        EdgeInsets.fromLTRB(20, 10, 20, 16 + (inset > 0 ? 0 : safe));
    return Stack(children: [
      Positioned.fill(
        child: GestureDetector(
          onTap: onDismiss,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 200),
            builder: (_, t, __) =>
                ColoredBox(color: Colors.black.withValues(alpha: 0.45 * t)),
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
          builder: (_, t, c) =>
              FractionalTranslation(translation: Offset(0, t), child: c),
          child: Padding(
            padding: EdgeInsets.only(bottom: inset),
            child: Material(
              key: sheetKey,
              color: theme.colorScheme.surface,
              elevation: 12,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.85),
                child: scroll
                    ? SingleChildScrollView(padding: padding, child: child)
                    : Padding(padding: padding, child: child),
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
  const _HistorySheet(
      {required this.client,
      required this.onClose,
      this.onOpenUrl,
      this.videoPlayerBuilder});
  final SiagaSOS client;
  final VoidCallback onClose;
  final void Function(String url)? onOpenUrl;
  final Widget Function(String url)? videoPlayerBuilder;

  @override
  State<_HistorySheet> createState() => _HistorySheetState();
}

class _HistorySheetState extends State<_HistorySheet> {
  List<ReportRecord>? _items;
  bool _loading = true;
  String? _cancelling; // id laporan yang sedang dibatalkan
  String? _error;

  /// Laporan yang sedang dibuka detailnya (null = daftar).
  ReportRecord? _open;

  @override
  void initState() {
    super.initState();
    // Tampilkan simpanan lokal dulu (instan), lalu perbarui status dari server.
    widget.client.history(refresh: false).then(
        (l) => mounted && _items == null ? setState(() => _items = l) : null);
    _reload();
  }

  /// Batalkan SOS salah tekan (hanya selama status `open`; server menolak bila petugas sudah merespons).
  Future<void> _cancel(ReportRecord r) async {
    HapticFeedback.selectionClick();
    setState(() {
      _cancelling = r.id;
      _error = null;
    });
    try {
      await widget.client.cancel(r.id, reason: 'Salah tekan');
    } on SiagaSOSError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted)
        setState(() =>
            _error = 'Gagal membatalkan. Periksa koneksi lalu coba lagi.');
    }
    if (!mounted) return;
    setState(() => _cancelling = null);
    await _reload();
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
    final open = _open;
    if (open != null) {
      return _SheetFrame(
        sheetKey: const ValueKey('siagasos-history-sheet'),
        onDismiss: widget.onClose,
        scroll: false,
        child: _ReportDetailView(
          key: ValueKey(open.id),
          client: widget.client,
          record: open,
          onBack: () {
            setState(() => _open = null);
            _reload();
          },
          onClose: widget.onClose,
          onOpenUrl: widget.onOpenUrl,
          videoPlayerBuilder: widget.videoPlayerBuilder,
        ),
      );
    }
    return _SheetFrame(
      sheetKey: const ValueKey('siagasos-history-sheet'),
      onDismiss: widget.onClose,
      scroll: false,
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Grip(theme),
            Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFF94A3B8), Color(0xFF475569)]),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.history_rounded, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Riwayat laporan',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      Text('SOS & pengaduan dari perangkat ini',
                          style: theme.textTheme.bodySmall),
                    ]),
              ),
              _loading
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.2)),
                    )
                  : IconButton(
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh_rounded),
                      tooltip: 'Muat ulang'),
              IconButton(
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Tutup'),
            ]),
            const SizedBox(height: 12),
            if (_error != null) ...[
              Text(_error!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error)),
              const SizedBox(height: 8),
            ],
            if (items == null)
              const SizedBox(height: 120)
            else if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 36),
                child: Column(children: [
                  Icon(Icons.inbox_rounded,
                      size: 40, color: theme.colorScheme.outline),
                  const SizedBox(height: 8),
                  Text('Belum ada laporan', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text('SOS dan pengaduan yang kamu kirim akan muncul di sini.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall),
                ]),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final r = items[i];
                    final cancellable =
                        r.kind == ReportKind.sos && r.status == SosStatus.open;
                    return _HistoryTile(
                      r,
                      onTap: () => setState(() => _open = r),
                      cancelling: _cancelling == r.id,
                      onCancel: cancellable && _cancelling == null
                          ? () => _cancel(r)
                          : null,
                    );
                  },
                ),
              ),
          ]),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile(this.r,
      {this.onCancel, this.onTap, this.cancelling = false});
  final ReportRecord r;

  /// Buka detail laporan.
  final VoidCallback? onTap;

  /// Null = tidak bisa dibatalkan (sudah ditangani / pengaduan).
  final VoidCallback? onCancel;
  final bool cancelling;

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
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'Mei',
      'Jun',
      'Jul',
      'Agu',
      'Sep',
      'Okt',
      'Nov',
      'Des'
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year} · ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sos = r.kind == ReportKind.sos;
    final (label, color) = _status(r.status);
    final title = sos ? 'SOS darurat' : complaintCategoryLabel(r.category);
    final done = r.resolvedAt ?? r.acknowledgedAt;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('siagasos-history-item-${r.id}'),
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
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
                color: (sos ? const Color(0xFFDC2626) : const Color(0xFFEA580C))
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                  sos
                      ? Icons.notifications_active_rounded
                      : Icons.campaign_rounded,
                  size: 20,
                  color:
                      sos ? const Color(0xFFDC2626) : const Color(0xFFEA580C)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text(title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20)),
                        child: Text(label,
                            style: TextStyle(
                                color: color,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ),
                    ]),
                    if (r.message != null && r.message!.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(r.message!.trim(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall),
                    ],
                    if (r.statusMessage != null &&
                        r.statusMessage!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(r.statusMessage!,
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: color, fontWeight: FontWeight.w600)),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      'No. ${(r.id.length > 8 ? r.id.substring(0, 8) : r.id).toUpperCase()} · ${_when(r.createdAt)}'
                      '${done != null && r.status.isTerminal ? ' · selesai ${_when(done)}' : ''}',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                    if (onCancel != null || cancelling)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          key: ValueKey('siagasos-cancel-${r.id}'),
                          onPressed: onCancel,
                          style: TextButton.styleFrom(
                            foregroundColor: theme.colorScheme.error,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            visualDensity: VisualDensity.compact,
                          ),
                          icon: cancelling
                              ? const SizedBox.square(
                                  dimension: 14,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.cancel_outlined, size: 16),
                          label: const Text('Batalkan (salah tekan)'),
                        ),
                      ),
                  ]),
            ),
            if (onTap != null)
              Padding(
                padding: const EdgeInsets.only(left: 4, top: 8),
                child: Icon(Icons.chevron_right_rounded,
                    color: theme.colorScheme.outline),
              ),
          ]),
        ),
      ),
    );
  }
}

enum _TkpPhase { prompt, note, sending, done }

/// Setelah SOS terkirim (alur tata-warga): "SOS terkirim" + ajakan "Rekam kondisi TKP?" → kamera app host →
/// catatan singkat → video + catatan dikirim ke petugas.
class _TkpSheet extends StatefulWidget {
  const _TkpSheet({
    required this.client,
    required this.report,
    required this.recipientText,
    required this.siren,
    required this.onCapture,
    required this.maxSeconds,
    required this.color,
    required this.onCapturing,
    required this.onClose,
    this.onError,
  });
  final SiagaSOS client;
  final ActiveReport report;
  final String? recipientText;
  final SosSiren? siren;
  final MediaCapture onCapture;
  final int maxSeconds;
  final Color color;
  final ValueChanged<bool> onCapturing;
  final VoidCallback onClose;
  final void Function(SiagaSOSError error)? onError;

  @override
  State<_TkpSheet> createState() => _TkpSheetState();
}

class _TkpSheetState extends State<_TkpSheet> {
  static const _green = Color(0xFF16A34A);
  static const _amber = Color(0xFFD97706);

  _TkpPhase _phase = _TkpPhase.prompt;
  CapturedMedia? _video;
  bool _uploaded =
      false; // video sudah masuk; percobaan ulang cukup kirim catatan
  final _note = TextEditingController();
  double _progress = 0;
  String? _error;
  bool _confirmCancel = false;
  late ActiveReport _report = widget.report;
  StreamSubscription<ActiveReport>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.client.status.listen((r) {
      if (mounted && r.localId == _report.localId) setState(() => _report = r);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _note.dispose();
    super.dispose();
  }

  Future<void> _record() async {
    widget.onCapturing(true);
    CapturedMedia? m;
    try {
      m = await widget.onCapture(context, MediaKind.video, MediaSource.camera);
    } catch (_) {
      m = null;
    } finally {
      widget.onCapturing(false);
    }
    if (!mounted || m == null) return;
    setState(() {
      _video = m;
      _uploaded = false;
      _phase = _TkpPhase.note;
      _error = null;
      _confirmCancel = false;
    });
  }

  Future<void> _send() async {
    final v = _video;
    if (v == null) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _phase = _TkpPhase.sending;
      _progress = 0;
      _error = null;
    });
    try {
      if (!_uploaded) {
        await widget.client.attach(_report.localId, v.bytes,
            contentType: v.contentType,
            durationS: v.durationS,
            onProgress: (p) => mounted ? setState(() => _progress = p) : null);
        _uploaded = true;
      }
      final note = _note.text.trim();
      if (note.isNotEmpty) await widget.client.addNote(_report.localId, note);
      HapticFeedback.mediumImpact();
      if (mounted) setState(() => _phase = _TkpPhase.done);
    } on SiagaSOSError catch (e) {
      widget.onError?.call(e);
      if (mounted) {
        setState(() {
          _phase = _TkpPhase.note;
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _phase = _TkpPhase.note;
          _error = 'Rekaman gagal dikirim. Periksa koneksi lalu coba lagi.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inset = MediaQuery.maybeViewInsetsOf(context)?.bottom ?? 0;
    return Stack(children: [
      Positioned.fill(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 200),
          builder: (_, t, __) =>
              ColoredBox(color: Colors.black.withValues(alpha: 0.55 * t)),
        ),
      ),
      Positioned.fill(
        child: Padding(
          padding: EdgeInsets.only(bottom: inset),
          child: Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.96, end: 1),
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              builder: (_, t, c) => Transform.scale(scale: t, child: c),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                      maxWidth: 420,
                      maxHeight: MediaQuery.sizeOf(context).height * 0.85),
                  child: Material(
                    key: const ValueKey('siagasos-tkp'),
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(24),
                    clipBehavior: Clip.antiAlias,
                    child: SingleChildScrollView(
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_phase != _TkpPhase.done) _header(theme),
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(20, 20, 20, 12),
                              child: switch (_phase) {
                                _TkpPhase.prompt => _prompt(theme),
                                _TkpPhase.note ||
                                _TkpPhase.sending =>
                                  _noteStep(theme),
                                _TkpPhase.done => _done(theme),
                              },
                            ),
                          ]),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ]);
  }

  /// Bilah hijau "SOS terkirim" (kuning bila masih di antrian offline) + tombol matikan sirene.
  Widget _header(ThemeData theme) {
    final queued = _report.status == SosStatus.queued;
    final c = queued ? _amber : _green;
    final siren = widget.siren;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: c.withValues(alpha: 0.08),
      child: Row(children: [
        Icon(queued ? Icons.schedule_send_rounded : Icons.check_circle_rounded,
            color: c, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(queued ? 'SOS disimpan' : 'SOS terkirim',
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: Color.lerp(c, Colors.black, 0.45))),
            Text(
              queued
                  ? 'Belum ada sinyal, terkirim otomatis'
                  : (widget.recipientText?.isNotEmpty == true
                      ? widget.recipientText!
                      : 'Petugas keamanan sudah diberi tahu'),
              style: TextStyle(
                  fontSize: 11.5, color: Color.lerp(c, Colors.black, 0.3)),
            ),
          ]),
        ),
        if (siren != null)
          ValueListenableBuilder<bool>(
            valueListenable: siren.active,
            builder: (_, on, __) => !on
                ? const SizedBox.shrink()
                : Material(
                    color: const Color(0xFFDC2626),
                    borderRadius: BorderRadius.circular(999),
                    child: InkWell(
                      key: const ValueKey('siagasos-tkp-mute'),
                      borderRadius: BorderRadius.circular(999),
                      onTap: () {
                        HapticFeedback.selectionClick();
                        siren.stop();
                      },
                      child: const Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.volume_off_rounded,
                              size: 14, color: Colors.white),
                          SizedBox(width: 4),
                          Text('Matikan sirene',
                              style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white)),
                        ]),
                      ),
                    ),
                  ),
          ),
      ]),
    );
  }

  Widget _prompt(ThemeData theme) {
    final brand = widget.color;
    return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: brand.withValues(alpha: 0.08),
                border:
                    Border.all(color: brand.withValues(alpha: 0.15), width: 6),
              ),
              child: Icon(Icons.videocam_rounded, color: brand, size: 32),
            ),
          ),
          const SizedBox(height: 14),
          Text('Rekam kondisi TKP?',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
              'Video singkat membantu petugas memahami situasi sebelum tiba di lokasi.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(height: 1.4)),
          const SizedBox(height: 14),
          Wrap(
              alignment: WrapAlignment.center,
              spacing: 6,
              runSpacing: 6,
              children: [
                _chip(theme, Icons.timer_outlined,
                    'Maks. ${widget.maxSeconds} detik'),
                _chip(theme, Icons.place_outlined, 'Lokasi otomatis'),
                _chip(theme, Icons.edit_outlined, 'Catatan singkat'),
              ]),
          const SizedBox(height: 18),
          _gradientButton(
            key: const ValueKey('siagasos-tkp-record'),
            label: 'Ya, Rekam Sekarang',
            icon: Icons.photo_camera_rounded,
            onTap: _record,
          ),
          const SizedBox(height: 4),
          TextButton(
            key: const ValueKey('siagasos-tkp-skip'),
            onPressed: widget.onClose,
            child: Text('Tidak, nanti saja',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.outline)),
          ),
        ]);
  }

  Widget _noteStep(ThemeData theme) {
    final sending = _phase == _TkpPhase.sending;
    final secs = _video?.durationS?.round();
    return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  color: _green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.videocam_rounded, color: _green),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(secs != null ? 'Video $secs detik' : 'Video TKP',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    Text('Rekaman siap dikirim',
                        style: theme.textTheme.bodySmall),
                  ]),
            ),
            TextButton(
                onPressed: sending ? null : _record,
                child: const Text('Rekam ulang')),
          ]),
          const SizedBox(height: 14),
          TextField(
            key: const ValueKey('siagasos-tkp-note'),
            controller: _note,
            enabled: !sending,
            minLines: 3,
            maxLines: 5,
            maxLength: 500,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Catatan kejadian',
              hintText: 'Contoh: 2 orang mencurigakan di depan toko',
              alignLabelWithHint: true,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 4),
            Text(_error!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 12),
          if (sending) ...[
            Text(
                _uploaded
                    ? 'Menyimpan catatan…'
                    : 'Mengirim rekaman… ${(_progress * 100).round()}%',
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            LinearProgressIndicator(
                value: _uploaded ? null : _progress, color: widget.color),
            const SizedBox(height: 12),
          ] else if (_confirmCancel) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(12)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Batalkan rekaman?',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF78350F))),
                    const SizedBox(height: 2),
                    const Text(
                        'Rekaman TKP belum dikirim. SOS tetap sudah terkirim ke petugas.',
                        style: TextStyle(
                            fontSize: 12.5, color: Color(0xFF92400E))),
                    const SizedBox(height: 8),
                    Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      TextButton(
                          onPressed: () =>
                              setState(() => _confirmCancel = false),
                          child: const Text('Lanjut kirim')),
                      TextButton(
                        onPressed: widget.onClose,
                        style: TextButton.styleFrom(
                            foregroundColor: theme.colorScheme.error),
                        child: const Text('Ya, batalkan'),
                      ),
                    ]),
                  ]),
            ),
            const SizedBox(height: 12),
          ] else ...[
            _gradientButton(
              key: const ValueKey('siagasos-tkp-send'),
              label: 'Kirim ke Petugas',
              icon: Icons.send_rounded,
              onTap: _send,
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => setState(() => _confirmCancel = true),
              child: Text('Batal',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.outline)),
            ),
          ],
        ]);
  }

  Widget _done(ThemeData theme) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Center(
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _green.withValues(alpha: 0.12)),
                child: const Icon(Icons.check_circle_rounded,
                    size: 40, color: _green),
              ),
            ),
            const SizedBox(height: 14),
            Text('Rekaman TKP terkirim',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('Video dan catatanmu sudah diterima petugas keamanan.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(height: 1.4)),
            const SizedBox(height: 18),
            FilledButton(
              key: const ValueKey('siagasos-tkp-close'),
              onPressed: widget.onClose,
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14))),
              child: const Text('Tutup'),
            ),
            const SizedBox(height: 8),
          ]);

  Widget _chip(ThemeData theme, IconData icon, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(text,
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant)),
        ]),
      );

  Widget _gradientButton(
      {required Key key,
      required String label,
      required IconData icon,
      required VoidCallback onTap}) {
    final c = widget.color;
    return SizedBox(
      height: 50,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [
            Color.lerp(c, Colors.white, 0.12)!,
            Color.lerp(c, Colors.black, 0.25)!
          ]),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: c.withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, 4))
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            key: key,
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// "Input Nomor": nomor WhatsApp (keluarga, RT/RW, satpam, Bhabinkamtibmas, …) yang ikut dikabari setiap SOS dari
/// perangkat ini. Status dipilih dari dropdown; status berwilayah (Bhabinkamtibmas) mengisi provinsi → desa,
/// otomatis dari lokasi bila bisa, tetap bisa dipilih ulang.
class _ContactsSheet extends StatefulWidget {
  const _ContactsSheet(
      {required this.client,
      required this.title,
      required this.roles,
      required this.areaRoles,
      required this.onClose,
      this.pillarLabel});
  final SiagaSOS client;
  final String title;
  final List<String> roles;

  /// Pilar app (UMKM, Lingkungan, …) dari /v1/sdk/config, ditampilkan di label Jabatan.
  final String? pillarLabel;
  final Set<String> areaRoles;
  final VoidCallback onClose;

  @override
  State<_ContactsSheet> createState() => _ContactsSheetState();
}

/// Level wilayah di isian: 0 provinsi, 1 kabupaten/kota, 2 kecamatan, 3 desa/kelurahan.
const _areaLevelLabels = [
  'Provinsi',
  'Kabupaten/Kota',
  'Kecamatan',
  'Desa/Kelurahan'
];

class _ContactsSheetState extends State<_ContactsSheet> {
  static const _green = Color(0xFF16A34A);
  static const _other = 'Lainnya';
  List<EmergencyContact>? _items;
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _customRole = TextEditingController();
  String? _role;
  String? _error;
  bool _saving = false;

  /// Wilayah terpilih per level (provinsi, kab/kota, kecamatan, desa).
  final List<Region?> _area = List.filled(4, null);
  bool _locating = false;
  String? _areaNote;

  /// Level yang sedang dipilih di daftar (null = form).
  int? _picking;

  /// Hanya jabatan dari pilar app (tanpa "Lainnya"/isian bebas: keputusan user 2026-11-25).
  List<String> get _roleOptions => [
        for (final r in widget.roles)
          if (r != _other) r,
      ];
  bool get _needsArea => _role != null && widget.areaRoles.contains(_role);
  String? get _roleValue {
    if (_role == null) return null;
    if (_role == _other) {
      final t = _customRole.text.trim();
      return t.isEmpty ? null : t;
    }
    return _role;
  }

  @override
  void initState() {
    super.initState();
    widget.client
        .emergencyContacts()
        .then((l) => mounted ? setState(() => _items = l) : null);
    _name.addListener(() => setState(() {}));
    _phone.addListener(() => setState(() {}));
    _customRole.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _customRole.dispose();
    super.dispose();
  }

  Future<void> _save(List<EmergencyContact> next) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.client.setEmergencyContacts(next);
      final fresh = await widget.client.emergencyContacts();
      if (mounted) setState(() => _items = fresh);
    } on ArgumentError catch (e) {
      if (mounted) setState(() => _error = '${e.message}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _setRole(String? r) {
    setState(() {
      _role = r;
      _error = null;
    });
    // Pertama kali memilih status berwilayah: coba isi otomatis dari lokasi.
    if (_needsArea && _area.every((a) => a == null)) _locate();
  }

  Future<void> _locate() async {
    setState(() {
      _locating = true;
      _areaNote = null;
    });
    final a = await widget.client.regionFromLocation();
    if (!mounted) return;
    setState(() {
      _locating = false;
      if (a == null || a.province == null) {
        _areaNote = 'Lokasi belum bisa dibaca. Pilih wilayah secara manual.';
        return;
      }
      _area
        ..[0] = a.province
        ..[1] = a.regency
        ..[2] = a.district
        ..[3] = a.village;
      _areaNote = a.village == null
          ? 'Sebagian wilayah terisi dari lokasi. Lengkapi sisanya.'
          : 'Terisi dari lokasi kamu. Ketuk untuk mengubah.';
    });
  }

  void _pick(int level, Region r) {
    setState(() {
      if (_area[level] != r) {
        _area[level] = r;
        for (var i = level + 1; i < 4; i++) {
          _area[i] = null;
        }
      }
      _picking = null;
      _areaNote = null;
    });
  }

  Future<void> _add() async {
    final items = _items ?? const [];
    final phone = toWhatsAppNumber(_phone.text);
    if (phone == null) {
      setState(() => _error = 'Nomor HP tidak valid. Contoh: 0812 3456 7890');
      return;
    }
    if (items.any((c) => c.phone == phone)) {
      setState(() => _error = 'Nomor ini sudah ada di daftar.');
      return;
    }
    if (_role == null) {
      setState(() => _error = 'Pilih jabatan kontak.');
      return;
    }
    if (_role == _other && _roleValue == null) {
      setState(() => _error = 'Tulis jabatan kontak (mis. Ketua Paguyuban).');
      return;
    }
    if (_needsArea && _area.any((a) => a == null)) {
      setState(() => _error =
          'Lengkapi wilayah tugas $_role (provinsi sampai desa/kelurahan).');
      return;
    }
    FocusScope.of(context).unfocus();
    final role = _roleValue;
    await _save([
      ...items,
      EmergencyContact(
          name: _name.text.trim().isEmpty
              ? (role ?? 'Kontak darurat')
              : _name.text.trim(),
          phone: phone,
          role: role,
          area: _needsArea
              ? RegionArea(
                  province: _area[0],
                  regency: _area[1],
                  district: _area[2],
                  village: _area[3])
              : null)
    ]);
    if (_error == null && mounted) {
      _name.clear();
      _phone.clear();
      _customRole.clear();
      setState(() {
        _role = null;
        _area.fillRange(0, 4, null);
        _areaNote = null;
      });
    }
  }

  InputDecoration _deco(String label, {String? hint, Widget? suffix}) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        suffixIcon: suffix,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      );

  Widget _areaField(ThemeData theme, int level) {
    final enabled = !_saving && (level == 0 || _area[level - 1] != null);
    final value = _area[level];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        key: ValueKey('siagasos-contact-area-$level'),
        borderRadius: BorderRadius.circular(14),
        onTap: enabled ? () => setState(() => _picking = level) : null,
        child: InputDecorator(
          isEmpty: value == null,
          decoration: _deco(_areaLevelLabels[level],
                  hint: 'Pilih ${_areaLevelLabels[level].toLowerCase()}',
                  suffix: const Icon(Icons.keyboard_arrow_down_rounded))
              .copyWith(enabled: enabled),
          child: Text(value?.name ?? '',
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyLarge),
        ),
      ),
    );
  }

  Widget _areaSection(ThemeData theme) => Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFBFDBFE))),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon(Icons.map_rounded, size: 18, color: Color(0xFF1D4ED8)),
            const SizedBox(width: 6),
            Expanded(
                child: Text('Wilayah tugas $_role',
                    style: theme.textTheme.labelLarge
                        ?.copyWith(fontWeight: FontWeight.w700))),
            TextButton.icon(
              key: const ValueKey('siagasos-contact-locate'),
              onPressed: _saving || _locating ? null : _locate,
              icon: _locating
                  ? const SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.my_location_rounded, size: 18),
              label: Text(_locating ? 'Membaca…' : 'Lokasi saya'),
            ),
          ]),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('SOS dari wilayah ini juga masuk ke $_role tersebut.',
                style: theme.textTheme.bodySmall),
          ),
          if (_areaNote != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_areaNote!,
                  key: const ValueKey('siagasos-contact-area-note'),
                  style: theme.textTheme.bodySmall),
            ),
          for (var i = 0; i < 4; i++) _areaField(theme, i),
        ]),
      );

  Widget _form(ThemeData theme, bool full) {
    final items = _items;
    return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Grip(theme),
          Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF4ADE80), Color(0xFF15803D)]),
                borderRadius: BorderRadius.circular(14),
              ),
              child:
                  const Icon(Icons.contact_phone_rounded, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    Text('Dapat panggilan SOS di aplikasi Polmas Keamanan',
                        style: theme.textTheme.bodySmall),
                  ]),
            ),
            IconButton(
                onPressed: _saving ? null : widget.onClose,
                icon: const Icon(Icons.close_rounded),
                tooltip: 'Tutup'),
          ]),
          const SizedBox(height: 14),
          if (items == null)
            const SizedBox(height: 80)
          else if (items.isEmpty)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14)),
              child: Text(
                  'Belum ada nomor darurat. Tambahkan pemilik, satpam, RT/RW, atau Bhabinkamtibmas. Saat kamu menekan SOS, mereka mendapat panggilan + sirene di aplikasi Polmas Keamanan.',
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.4)),
            )
          else
            for (final c in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                  decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border:
                          Border.all(color: theme.colorScheme.outlineVariant)),
                  child: Row(children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                          color: _green.withValues(alpha: 0.12),
                          shape: BoxShape.circle),
                      child: const Icon(Icons.person_rounded,
                          size: 20, color: _green),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                c.role == null
                                    ? c.name
                                    : '${c.name} · ${c.role}',
                                style: theme.textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w700)),
                            Text(
                                c.active
                                    ? '+${c.phone}'
                                    : '+${c.phone} · nonaktif',
                                style: theme.textTheme.bodySmall),
                            if (c.area != null)
                              Text(c.area!.label,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.outline)),
                          ]),
                    ),
                    IconButton(
                      key: ValueKey('siagasos-contact-del-${c.phone}'),
                      onPressed: _saving
                          ? null
                          : () => _save(
                              items.where((o) => o.phone != c.phone).toList()),
                      icon: Icon(Icons.delete_outline_rounded,
                          color: theme.colorScheme.error),
                      tooltip: 'Hapus',
                    ),
                  ]),
                ),
              ),
          if (items != null && !full) ...[
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('siagasos-contact-name'),
              controller: _name,
              enabled: !_saving,
              textCapitalization: TextCapitalization.words,
              decoration: _deco('Nama', hint: 'Mis. Pak Budi'),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('siagasos-contact-phone'),
              controller: _phone,
              enabled: !_saving,
              keyboardType: TextInputType.phone,
              decoration: _deco('Nomor HP', hint: '0812 3456 7890'),
            ),
            const SizedBox(height: 10),
            // InputDecorator + DropdownButton (bukan DropdownButtonFormField): `initialValue` belum ada di Flutter
            // 3.32 yang dipakai app host, sedangkan `value` di FormField sudah usang di versi baru.
            InputDecorator(
              isEmpty: _role == null,
              decoration: _deco(
                      widget.pillarLabel == null
                          ? 'Jabatan'
                          : 'Jabatan · ${widget.pillarLabel}',
                      hint: 'Pilih jabatan')
                  .copyWith(
                      contentPadding: const EdgeInsets.fromLTRB(12, 4, 8, 4)),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  key: const ValueKey('siagasos-contact-role'),
                  value: _role,
                  isExpanded: true,
                  isDense: true,
                  borderRadius: BorderRadius.circular(14),
                  items: [
                    for (final r in _roleOptions)
                      DropdownMenuItem(value: r, child: Text(r)),
                  ],
                  onChanged: _saving ? null : _setRole,
                ),
              ),
            ),
            if (_role == _other) ...[
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('siagasos-contact-role-custom'),
                controller: _customRole,
                enabled: !_saving,
                maxLength: 40,
                textCapitalization: TextCapitalization.words,
                decoration:
                    _deco('Jabatan lainnya', hint: 'Mis. Ketua Paguyuban'),
              ),
            ],
            if (_needsArea) _areaSection(theme),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const ValueKey('siagasos-contact-add'),
              onPressed: _saving || _phone.text.trim().isEmpty ? null : _add,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.2, color: Colors.white))
                  : const Icon(Icons.add_rounded),
              label: const Text('Tambah nomor'),
              style: FilledButton.styleFrom(
                backgroundColor: _green,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
          if (full)
            Text(
                'Maksimal $maxActiveEmergencyContacts nomor aktif. Hapus atau nonaktifkan salah satu untuk mengganti.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                key: const ValueKey('siagasos-contact-error'),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 8),
          Text(
              'Nomor di atas bisa masuk ke aplikasi Polmas Keamanan dengan nomornya sendiri untuk menerima SOS, melihat lokasi & bukti, lalu menindaklanjuti.',
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.outline)),
        ]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = _items;
    final full = (items?.where((c) => c.active).length ?? 0) >=
            maxActiveEmergencyContacts ||
        (items?.length ?? 0) >= maxEmergencyContacts;
    final level = _picking;
    return _SheetFrame(
      sheetKey: const ValueKey('siagasos-contacts-sheet'),
      onDismiss: _saving ? null : widget.onClose,
      scroll: level == null,
      child: level == null
          ? _form(theme, full)
          : _RegionPicker(
              key: ValueKey('siagasos-region-picker-$level'),
              client: widget.client,
              title: _areaLevelLabels[level],
              parent: level == 0 ? null : _area[level - 1]!.code,
              selected: _area[level],
              onPick: (r) => _pick(level, r),
              onBack: () => setState(() => _picking = null),
            ),
    );
  }
}

/// Daftar wilayah satu level (dengan pencarian) di dalam lembar Input Nomor.
class _RegionPicker extends StatefulWidget {
  const _RegionPicker(
      {super.key,
      required this.client,
      required this.title,
      required this.parent,
      required this.selected,
      required this.onPick,
      required this.onBack});
  final SiagaSOS client;
  final String title;
  final String? parent;
  final Region? selected;
  final ValueChanged<Region> onPick;
  final VoidCallback onBack;

  @override
  State<_RegionPicker> createState() => _RegionPickerState();
}

class _RegionPickerState extends State<_RegionPicker> {
  final _q = TextEditingController();
  List<Region>? _all;
  String? _error;

  @override
  void initState() {
    super.initState();
    _q.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final l = await widget.client.regions(widget.parent);
      if (mounted) setState(() => _all = l);
    } catch (_) {
      if (mounted) {
        setState(() =>
            _error = 'Daftar wilayah belum bisa dimuat. Periksa koneksi.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = _q.text.trim().toLowerCase();
    final list = _all
        ?.where((r) => q.isEmpty || r.name.toLowerCase().contains(q))
        .toList();
    return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Grip(theme),
          Row(children: [
            IconButton(
                key: const ValueKey('siagasos-region-back'),
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: 'Kembali'),
            Expanded(
                child: Text('Pilih ${widget.title}',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 6),
          TextField(
            key: const ValueKey('siagasos-region-search'),
            controller: _q,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: 'Cari ${widget.title.toLowerCase()}',
              isDense: true,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 8),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(children: [
                Text(_error!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error)),
                TextButton(onPressed: _load, child: const Text('Coba lagi')),
              ]),
            )
          else if (list == null)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Tidak ditemukan.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final r = list[i];
                  final sel = r.code == widget.selected?.code;
                  return ListTile(
                    key: ValueKey('siagasos-region-${r.code}'),
                    dense: true,
                    title: Text(r.name,
                        style: TextStyle(
                            fontWeight:
                                sel ? FontWeight.w700 : FontWeight.w500)),
                    trailing: sel
                        ? const Icon(Icons.check_rounded,
                            color: Color(0xFF16A34A))
                        : null,
                    onTap: () => widget.onPick(r),
                  );
                },
              ),
            ),
        ]);
  }
}

/// Detail satu laporan di "Riwayat laporan": status, waktu, uraian, lokasi, lampiran, riwayat status.
class _ReportDetailView extends StatefulWidget {
  const _ReportDetailView({
    super.key,
    required this.client,
    required this.record,
    required this.onBack,
    required this.onClose,
    this.onOpenUrl,
    this.videoPlayerBuilder,
  });
  final SiagaSOS client;
  final ReportRecord record;
  final VoidCallback onBack;
  final VoidCallback onClose;
  final void Function(String url)? onOpenUrl;
  final Widget Function(String url)? videoPlayerBuilder;

  @override
  State<_ReportDetailView> createState() => _ReportDetailViewState();
}

class _ReportDetailViewState extends State<_ReportDetailView> {
  ReportDetail? _d;
  String? _error;
  bool _loading = true;
  bool _cancelling = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await widget.client.reportDetail(widget.record.id);
      if (mounted) setState(() => _d = d);
    } on SiagaSOSError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted)
        setState(() => _error =
            'Detail belum bisa dimuat. Periksa koneksi lalu coba lagi.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _cancel() async {
    HapticFeedback.selectionClick();
    setState(() => _cancelling = true);
    try {
      await widget.client.cancel(widget.record.id, reason: 'Salah tekan');
    } on SiagaSOSError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted)
        setState(() =>
            _error = 'Gagal membatalkan. Periksa koneksi lalu coba lagi.');
    }
    if (mounted) setState(() => _cancelling = false);
    await _load();
  }

  static String _timelineLabel(ReportTimelineEntry e) => switch (e.type) {
        'created' => 'Laporan dikirim',
        'status_changed' => e.toStatus == null
            ? 'Status diperbarui'
            : _HistoryTile._status(e.toStatus!).$1,
        'cancelled' => 'Dibatalkan',
        'note' => 'Catatan',
        'media' => 'Lampiran',
        'whatsapp' => 'WhatsApp',
        _ => e.type,
      };

  static IconData _timelineIcon(ReportTimelineEntry e) => switch (e.type) {
        'created' => Icons.send_rounded,
        'status_changed' => switch (e.toStatus) {
            SosStatus.resolved => Icons.check_circle_rounded,
            SosStatus.falseAlarm => Icons.block_rounded,
            _ => Icons.support_agent_rounded,
          },
        'cancelled' => Icons.cancel_rounded,
        'note' => Icons.sticky_note_2_rounded,
        'media' => Icons.attach_file_rounded,
        'whatsapp' => Icons.chat_rounded,
        _ => Icons.circle,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = _d;
    final r = widget.record;
    final status = d?.status ?? r.status;
    final (label, color) = _HistoryTile._status(status);
    final sos = (d?.kind ?? r.kind) == ReportKind.sos;
    final title =
        sos ? 'SOS darurat' : complaintCategoryLabel(d?.category ?? r.category);
    final muted =
        theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline);
    final section =
        theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700);

    Widget info(String k, String v) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 92, child: Text(k, style: muted)),
            Expanded(
                child: Text(v,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(fontWeight: FontWeight.w600))),
          ]),
        );

    return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Grip(theme),
          Row(children: [
            IconButton(
                key: const ValueKey('siagasos-detail-back'),
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: 'Kembali'),
            Expanded(
                child: Text('Detail laporan',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700))),
            _loading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.2)))
                : IconButton(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh_rounded),
                    tooltip: 'Muat ulang'),
            IconButton(
                onPressed: widget.onClose,
                icon: const Icon(Icons.close_rounded),
                tooltip: 'Tutup'),
          ]),
          Flexible(
            child:
                ListView(shrinkWrap: true, padding: EdgeInsets.zero, children: [
              // Status
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16)),
                child: Row(children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        shape: BoxShape.circle),
                    child: Icon(
                        sos
                            ? Icons.notifications_active_rounded
                            : Icons.campaign_rounded,
                        color: color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              style: theme.textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 2),
                          Text(label,
                              key: const ValueKey('siagasos-detail-status'),
                              style: TextStyle(
                                  color: color, fontWeight: FontWeight.w800)),
                          if ((d?.statusMessage ?? r.statusMessage)
                                  ?.isNotEmpty ==
                              true)
                            Text((d?.statusMessage ?? r.statusMessage)!,
                                style: theme.textTheme.bodySmall),
                        ]),
                  ),
                ]),
              ),
              const SizedBox(height: 14),
              info(
                  'No. laporan',
                  (r.id.length > 8 ? r.id.substring(0, 8) : r.id)
                      .toUpperCase()),
              info('Dikirim', _HistoryTile._when(d?.createdAt ?? r.createdAt)),
              if ((d?.acknowledgedAt ?? r.acknowledgedAt) != null)
                info(
                    'Diterima',
                    _HistoryTile._when(
                        (d?.acknowledgedAt ?? r.acknowledgedAt)!)),
              if ((d?.resolvedAt ?? r.resolvedAt) != null)
                info(status == SosStatus.cancelled ? 'Dibatalkan' : 'Selesai',
                    _HistoryTile._when((d?.resolvedAt ?? r.resolvedAt)!)),
              if (!sos)
                info(
                    'Jenis', complaintCategoryLabel(d?.category ?? r.category)),
              if ((d?.message ?? r.message)?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 10),
                Text('Uraian', style: section),
                const SizedBox(height: 4),
                Text((d?.message ?? r.message)!.trim(),
                    style: theme.textTheme.bodyMedium),
              ],
              if (d?.location != null) ...[
                const SizedBox(height: 14),
                Text('Lokasi', style: section),
                const SizedBox(height: 4),
                Row(children: [
                  Icon(Icons.place_rounded,
                      size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${d!.location!.lat.toStringAsFixed(5)}, ${d.location!.lng.toStringAsFixed(5)}'
                      '${d.location!.accuracyM != null ? ' (±${d.location!.accuracyM!.round()} m)' : ''}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  if (widget.onOpenUrl != null)
                    TextButton(
                      key: const ValueKey('siagasos-detail-map'),
                      onPressed: () => widget.onOpenUrl!(
                          'https://www.google.com/maps?q=${d.location!.lat},${d.location!.lng}'),
                      child: const Text('Buka peta'),
                    ),
                ]),
              ],
              if (d != null && d.media.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text('Lampiran (${d.media.length})', style: section),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final m in d.media)
                    _MediaThumb(m,
                        videoPlayerBuilder: widget.videoPlayerBuilder)
                ]),
              ],
              if (d != null && d.timeline.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text('Riwayat status', style: section),
                const SizedBox(height: 8),
                for (var i = 0; i < d.timeline.length; i++)
                  _TimelineRow(
                    icon: _timelineIcon(d.timeline[i]),
                    title: _timelineLabel(d.timeline[i]),
                    meta:
                        '${d.timeline[i].actor} · ${_HistoryTile._when(d.timeline[i].createdAt)}',
                    note: d.timeline[i].type == 'created'
                        ? null
                        : d.timeline[i].note,
                    last: i == d.timeline.length - 1,
                    color: i == d.timeline.length - 1
                        ? color
                        : theme.colorScheme.outline,
                  ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error)),
              ],
              if (sos && status == SosStatus.open) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const ValueKey('siagasos-detail-cancel'),
                  onPressed: _cancelling ? null : _cancel,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                    side: BorderSide(
                        color: theme.colorScheme.error.withValues(alpha: 0.4)),
                    minimumSize: const Size.fromHeight(46),
                  ),
                  icon: _cancelling
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.cancel_outlined),
                  label: const Text('Batalkan (salah tekan)'),
                ),
              ],
              const SizedBox(height: 8),
            ]),
          ),
        ]);
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow(
      {required this.icon,
      required this.title,
      required this.meta,
      required this.last,
      required this.color,
      this.note});
  final IconData icon;
  final String title;
  final String meta;
  final String? note;
  final bool last;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 28,
          child: Column(children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Icon(icon, size: 15, color: color),
            ),
            if (!last)
              Expanded(
                  child: Container(
                      width: 2, color: theme.colorScheme.outlineVariant)),
          ]),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: last ? 0 : 12, top: 3),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              Text(meta,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.outline)),
              if (note != null && note!.trim().isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(note!.trim(), style: theme.textTheme.bodySmall),
              ],
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Kotak lampiran: foto tampil langsung, video/suara berupa ikon putar. Ketuk = buka lewat app host.
/// Pratinjau lampiran di dalam app (layar penuh, di lapisan sheet, bukan browser/S3).
void _showMediaPreview(BuildContext context, MediaKind kind, String url,
    Widget Function(String url)? videoBuilder) {
  final overlay = Overlay.maybeOf(context);
  if (overlay == null) return;
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => Positioned.fill(
      child: _MediaPreview(
          kind: kind,
          url: url,
          videoBuilder: videoBuilder,
          onClose: () => entry.remove()),
    ),
  );
  overlay.insert(entry);
}

class _MediaPreview extends StatelessWidget {
  const _MediaPreview(
      {required this.kind,
      required this.url,
      required this.onClose,
      this.videoBuilder});
  final MediaKind kind;
  final String url;
  final VoidCallback onClose;
  final Widget Function(String url)? videoBuilder;

  @override
  Widget build(BuildContext context) {
    final content = kind == MediaKind.video && videoBuilder != null
        ? videoBuilder!(url)
        : InteractiveViewer(
            minScale: 1,
            maxScale: 4,
            child: Image.network(
              url,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(
                  Icons.broken_image_rounded,
                  color: Colors.white54,
                  size: 48),
            ),
          );
    return Material(
      color: Colors.black,
      child: SafeArea(
        child: Stack(children: [
          Positioned.fill(child: Center(child: content)),
          Positioned(
            top: 4,
            right: 4,
            child: IconButton(
              key: const ValueKey('siagasos-preview-close'),
              color: Colors.white,
              icon: const Icon(Icons.close_rounded),
              tooltip: 'Tutup',
              onPressed: onClose,
            ),
          ),
        ]),
      ),
    );
  }
}

class _MediaThumb extends StatelessWidget {
  const _MediaThumb(this.m, {this.videoPlayerBuilder});
  final ReportMediaItem m;
  final Widget Function(String url)? videoPlayerBuilder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = m.url;
    final canPreview = url != null &&
        (m.kind == MediaKind.image ||
            (m.kind == MediaKind.video && videoPlayerBuilder != null));
    final fallback = Container(
      color: m.kind == MediaKind.image
          ? theme.colorScheme.surfaceContainerHighest
          : const Color(0xFF1F2937),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(
          switch (m.kind) {
            MediaKind.image => Icons.image_rounded,
            MediaKind.video => Icons.play_circle_fill_rounded,
            MediaKind.audio => Icons.graphic_eq_rounded,
          },
          color: m.kind == MediaKind.image
              ? theme.colorScheme.outline
              : Colors.white,
          size: 30,
        ),
        if (m.durationS != null)
          Text('${m.durationS!.round()} dtk',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
      ]),
    );
    return Semantics(
      button: canPreview,
      label: switch (m.kind) {
        MediaKind.image => 'Foto',
        MediaKind.video => 'Video',
        MediaKind.audio => 'Rekaman suara'
      },
      child: InkWell(
        key: ValueKey('siagasos-media-${m.id}'),
        borderRadius: BorderRadius.circular(12),
        onTap: canPreview
            ? () => _showMediaPreview(context, m.kind, url, videoPlayerBuilder)
            : null,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 92,
            height: 92,
            child: m.kind == MediaKind.image && url != null
                ? Image.network(url,
                    fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback)
                : fallback,
          ),
        ),
      ),
    );
  }
}
