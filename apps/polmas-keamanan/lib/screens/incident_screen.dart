import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/map_widgets.dart';
import 'video_screen.dart';

Future<void> openIncident(BuildContext context, String id) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => IncidentScreen(id: id)));

/// Detail insiden (FR-06, FR-07, FR-17): peta kecil, kartu pengirim, bukti yang bisa digeser, garis waktu status, dan
/// aksi Hubungi / Verifikasi / Tangani / Selesaikan di bawah layar (terjangkau satu tangan).
class IncidentScreen extends StatefulWidget {
  const IncidentScreen({super.key, required this.id});
  final String id;
  @override
  State<IncidentScreen> createState() => _IncidentScreenState();
}

class _IncidentScreenState extends State<IncidentScreen> {
  Map? _d;
  String? _error;
  String? _busy;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await AppScope.read(context).api.get('/reports/${widget.id}') as Map;
      if (mounted) {
        setState(() {
          _d = d;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  List<String> get _actions => ((_d?['actions'] as List?) ?? const []).cast<String>();

  Future<void> _respond(String action, {String? note}) async {
    setState(() => _busy = action);
    final state = AppScope.read(context);
    try {
      await state.api.post('/reports/${widget.id}/responses', {'action': action, 'note': ?note});
      await _load();
      state.bump();
      if (!mounted) return;
      if (action == 'selesai') {
        await showCompletedCheck(context);
      } else {
        showToast(context, _doneText[action] ?? 'Tersimpan');
      }
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  static const _doneText = {
    'terima': 'Laporan diterima',
    'verifikasi': 'Laporan diverifikasi',
    'tangani': 'Status: sedang ditangani',
    'tidak_valid': 'Laporan ditandai tidak valid',
    'catatan': 'Catatan terkirim ke pelapor',
    'hubungi': 'Panggilan dicatat',
  };

  Future<void> _call() async {
    final phone = (_d?['reporter'] as Map?)?['phone'] as String?;
    if (phone == null) return;
    final ok = await launchUrl(Uri(scheme: 'tel', path: '+${phone.replaceAll(RegExp(r'[^0-9]'), '')}'));
    if (!ok && mounted) showToast(context, 'Tidak bisa membuka aplikasi telepon', error: true);
    if (_actions.contains('hubungi')) await _respond('hubungi');
  }

  Future<void> _confirm(String action) async {
    final title = switch (action) {
      'verifikasi' => 'Verifikasi laporan',
      'tangani' => 'Tangani laporan',
      'selesai' => 'Selesaikan laporan',
      'tidak_valid' => 'Tandai tidak valid',
      'terima' => 'Terima laporan',
      _ => 'Kirim catatan',
    };
    final note = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _NoteSheet(title: title, required: action == 'catatan', danger: action == 'tidak_valid'),
    );
    if (note == null) return;
    await _respond(action, note: note.isEmpty ? null : note);
  }

  PreferredSizeWidget _appBar(Report? r) {
    final acts = _actions;
    return AppBar(
      centerTitle: true,
      backgroundColor: context.pageBg,
      title: Text('Detail Laporan', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
      actions: [
        if (r != null)
          PopupMenuButton<String>(
            tooltip: 'Menu lainnya',
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (v) {
              final loc = r.location;
              switch (v) {
                case 'hubungi':
                  _call();
                case 'peta':
                  if (loc != null) {
                    launchUrl(Uri.parse('https://www.google.com/maps/search/?api=1&query=${loc.lat},${loc.lng}'), mode: LaunchMode.externalApplication);
                  }
                default:
                  _confirm(v);
              }
            },
            itemBuilder: (_) => [
              if (r.reporterPhone != null) const PopupMenuItem(value: 'hubungi', child: Text('Hubungi pelapor')),
              if (r.location != null) const PopupMenuItem(value: 'peta', child: Text('Buka di aplikasi peta')),
              if (acts.contains('terima')) const PopupMenuItem(value: 'terima', child: Text('Terima laporan')),
              if (acts.contains('catatan')) const PopupMenuItem(value: 'catatan', child: Text('Kirim catatan ke pelapor')),
              if (acts.contains('tidak_valid')) const PopupMenuItem(value: 'tidak_valid', child: Text('Tandai tidak valid')),
            ],
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    if (d == null) {
      return Scaffold(
        appBar: _appBar(null),
        body: _error != null ? ErrorState(message: _error!, onRetry: _load) : const Center(child: CircularProgressIndicator()),
      );
    }
    final r = Report(d);
    final t = Theme.of(context).textTheme;
    final media = (d['media'] as List).cast<Map>();
    final timeline = (d['timeline'] as List).cast<Map>();
    final complaint = d['complaint'] as Map?;
    final loc = r.location;
    final trail = ((d['trail'] as List?) ?? const []).cast<Map>();
    final dist = r.distanceFrom(AppScope.of(context).me?.areaLocation);
    final notes = timeline.where((e) => (e['note'] as String?)?.isNotEmpty == true).length;
    return Scaffold(
      backgroundColor: context.pageBg,
      appBar: _appBar(r),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            if (loc != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(PK.rCard),
                child: SizedBox(
                  height: 150,
                  child: _MiniMap(lat: loc.lat, lng: loc.lng, sos: r.isSos, trail: trail),
                ),
              ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(r.headline, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                ),
                if (r.isDemo) const DemoTag(),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: StatusBadge(status: r.status, sos: r.isSos),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.calendar_today_rounded, size: 16, color: context.ink2),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(fmtDayTime(r.createdAt), style: t.bodyMedium?.copyWith(color: context.ink2)),
                ),
                if (dist != null) ...[
                  Icon(Icons.location_on_outlined, size: 16, color: context.ink2),
                  const SizedBox(width: 4),
                  Text(dist, style: t.bodyMedium?.copyWith(color: context.ink2)),
                ],
              ],
            ),
            if (r.message != null) ...[const SizedBox(height: 10), Text(r.message!, style: t.bodyLarge)],
            if (complaint != null) ...[
              if (complaint['location_text'] != null) _InfoRow(Icons.place_rounded, 'Lokasi kejadian', complaint['location_text'] as String),
              if (complaint['occurred_at'] != null)
                _InfoRow(Icons.schedule_rounded, 'Waktu kejadian', fmtDateTime(DateTime.parse(complaint['occurred_at'] as String).toLocal())),
              if (complaint['suspect'] != null) _InfoRow(Icons.person_search_rounded, 'Ciri pelaku', complaint['suspect'] as String),
              if (complaint['witness'] != null) _InfoRow(Icons.record_voice_over_rounded, 'Saksi', complaint['witness'] as String),
            ],
            const SizedBox(height: 14),
            _SenderCard(r: r, onCall: r.reporterPhone != null ? _call : null),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Text('Bukti Laporan (${media.length})', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                ),
                if (media.isNotEmpty)
                  TextButton(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _MediaGrid(media: media))),
                    style: TextButton.styleFrom(foregroundColor: context.dangerText),
                    child: const Text('Lihat semua', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            if (media.isEmpty)
              Text('Pelapor belum melampirkan foto atau video.', style: t.bodyMedium?.copyWith(color: context.ink2))
            else
              _MediaStrip(media: media),
            const SizedBox(height: 20),
            Text('Status Penanganan', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            _Stepper(r: r, timeline: timeline),
            if (notes > 0) ...[
              const SizedBox(height: 12),
              AppCard(
                padding: EdgeInsets.zero,
                child: ExpansionTile(
                  shape: const Border(),
                  title: Text('Catatan & aktivitas ($notes)', style: t.titleSmall),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [_Timeline(items: timeline)],
                ),
              ),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
      bottomNavigationBar: _actionBar(r),
    );
  }

  /// Bilah aksi bawah (satu tangan): Verifikasi (garis merah), Tangani (emas), Selesaikan (hijau).
  /// Aksi ditentukan server: penerima Nomor Darurat hanya untuk laporan yang memanggil nomornya, Bhabinkamtibmas untuk
  /// kecamatannya, peran lain hanya melihat (tombol Hubungi bila nomor pelapor terlihat).
  Widget? _actionBar(Report r) {
    final acts = _actions;
    final closed = const {PkStatus.selesai, PkStatus.tidakValid, PkStatus.dibatalkan}.contains(r.status);
    if (acts.isEmpty) {
      if (closed) {
        return _BarShell(
          child: Row(
            children: [
              Icon(Icons.lock_rounded, size: 18, color: context.ink2),
              const SizedBox(width: 8),
              Expanded(child: Text('Laporan sudah ditutup.', style: Theme.of(context).textTheme.bodyMedium)),
            ],
          ),
        );
      }
      if (r.reporterPhone == null) return null;
      return _BarShell(
        child: PrimaryButton(label: 'Hubungi pelapor', icon: Icons.call_rounded, color: PK.green, onPressed: _call),
      );
    }
    final busy = _busy != null;
    return _BarShell(
      child: Row(
        children: [
          _ActBtn(
            label: 'Verifikasi',
            icon: Icons.check_rounded,
            outlined: true,
            color: PK.red,
            loading: _busy == 'verifikasi',
            onTap: acts.contains('verifikasi') && !busy ? () => _confirm('verifikasi') : null,
          ),
          const SizedBox(width: 8),
          _ActBtn(
            label: 'Tangani',
            icon: Icons.person_rounded,
            color: const Color(0xFFE0A21B),
            loading: _busy == 'tangani',
            onTap: acts.contains('tangani') && !busy ? () => _confirm('tangani') : null,
          ),
          const SizedBox(width: 8),
          _ActBtn(
            label: 'Selesaikan',
            icon: Icons.check_rounded,
            color: PK.green,
            loading: _busy == 'selesai',
            onTap: acts.contains('selesai') && !busy ? () => _confirm('selesai') : null,
          ),
        ],
      ),
    );
  }
}

class _BarShell extends StatelessWidget {
  const _BarShell({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: context.surface,
      border: Border(top: BorderSide(color: context.hairline)),
    ),
    padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
    child: child,
  );
}

class _ActBtn extends StatelessWidget {
  const _ActBtn({required this.label, required this.icon, required this.color, this.onTap, this.outlined = false, this.loading = false});
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final bool outlined, loading;
  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final child = loading
        ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: outlined ? color : Colors.white))
        : FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18),
                const SizedBox(width: 4),
                Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ],
            ),
          );
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
    return Expanded(
      child: SizedBox(
        height: 50,
        child: outlined
            ? OutlinedButton(
                onPressed: onTap,
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.dangerText,
                  side: BorderSide(color: enabled ? color : context.hairline, width: 1.5),
                  shape: shape,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                ),
                child: child,
              )
            : FilledButton(
                onPressed: onTap,
                style: FilledButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: color.withValues(alpha: 0.3),
                  disabledForegroundColor: Colors.white,
                  shape: shape,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                ),
                child: child,
              ),
      ),
    );
  }
}

/// Langkah Status Penanganan: Diterima → Diverifikasi → Ditangani → Selesai. Selesai = centang hijau + waktu,
/// berikutnya = lingkaran abu "Menunggu …".
class _Stepper extends StatelessWidget {
  const _Stepper({required this.r, required this.timeline});
  final Report r;
  final List<Map> timeline;

  DateTime? _at(String action) {
    final e = timeline.where((x) => x['kind'] == 'response' && x['action'] == action).firstOrNull;
    return e == null ? null : DateTime.parse(e['at'] as String).toLocal();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = r.status;
    final verified = r.raw['verified_at'] is String ? DateTime.parse(r.raw['verified_at'] as String).toLocal() : null;
    final level = switch (s) {
      PkStatus.baru => 0,
      PkStatus.diterima => 1,
      PkStatus.diverifikasi => 2,
      PkStatus.ditangani => 3,
      _ => 4,
    };
    final closedOther = s == PkStatus.tidakValid || s == PkStatus.dibatalkan;
    final steps = <(String, DateTime?, bool, String)>[
      ('Diterima', r.acknowledgedAt ?? _at('terima'), level >= 1, 'Menunggu diterima'),
      ('Diverifikasi', verified ?? _at('verifikasi'), level >= 2 && (verified != null || level >= 3), 'Menunggu verifikasi'),
      ('Ditangani', _at('tangani'), level >= 3 && !closedOther, 'Menunggu penanganan'),
      (
        s == PkStatus.tidakValid
            ? 'Tidak valid'
            : s == PkStatus.dibatalkan
            ? 'Dibatalkan'
            : 'Selesai',
        r.resolvedAt,
        level >= 4,
        'Menunggu penyelesaian',
      ),
    ];
    final firstPending = steps.indexWhere((x) => !x.$3);
    return Column(
      children: [
        for (final (i, (label, at, done, waiting)) in steps.indexed)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 30,
                  child: Column(
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: done ? (closedOther && i == 3 ? PK.grey : PK.green) : Colors.transparent,
                          border: done ? null : Border.all(color: context.hairline, width: 2),
                        ),
                        child: done ? const Icon(Icons.check_rounded, size: 15, color: Colors.white) : null,
                      ),
                      if (i < steps.length - 1) Expanded(child: Container(width: 2, color: done && steps[i + 1].$3 ? PK.green : context.hairline)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: i < steps.length - 1 ? 14 : 0),
                    child: Semantics(
                      label: '$label: ${done ? (at != null ? fmtDayTime(at) : 'selesai') : (i == firstPending ? waiting : 'belum')}',
                      excludeSemantics: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: done ? context.ink : context.ink2),
                          ),
                          Text(done ? (at != null ? fmtDayTime(at) : 'Selesai') : (i == firstPending ? waiting : '–'), style: t.bodySmall),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Semua bukti dalam kisi 3 kolom.
class _MediaGrid extends StatelessWidget {
  const _MediaGrid({required this.media});
  final List<Map> media;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Bukti Laporan (${media.length})')),
    body: GridView.count(
      padding: const EdgeInsets.all(12),
      crossAxisCount: 3,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: [for (final (i, m) in media.indexed) _MediaTile(m: m, index: i)],
    ),
  );
}

class _SenderCard extends StatelessWidget {
  const _SenderCard({required this.r, this.onCall});
  final Report r;
  final VoidCallback? onCall;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: context.brand.withValues(alpha: 0.12),
                child: Text(
                  r.reporterName.isEmpty ? '?' : r.reporterName[0],
                  style: TextStyle(color: context.brand, fontWeight: FontWeight.w800, fontSize: 18),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.isMine ? '${r.reporterName} (Anda)' : r.reporterName, style: t.titleMedium),
                    if (r.reporterPhone != null) Text(fmtPhone(r.reporterPhone!), style: t.bodySmall) else Text('Identitas disamarkan', style: t.bodySmall),
                  ],
                ),
              ),
              if (onCall != null)
                IconButton.filled(
                  tooltip: 'Telepon pelapor',
                  style: IconButton.styleFrom(backgroundColor: PK.green, minimumSize: const Size(48, 48)),
                  onPressed: onCall,
                  icon: const Icon(Icons.call_rounded, color: Colors.white),
                ),
            ],
          ),
          const Divider(height: 24),
          _InfoRow(sourceIcon(r.source), 'Aplikasi asal', [r.sourceLabel, ?r.sourcePlace].join(' · ')),
          _InfoRow(
            Icons.place_rounded,
            'Wilayah',
            [if (r.kelurahan != null) 'Kel. ${r.kelurahan!.name}', if (r.kecamatan != null) 'Kec. ${r.kecamatan!.name}'].join(', ').ifEmpty('Belum diketahui'),
          ),
        ],
      ),
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.icon, this.label, this.value);
  final IconData icon;
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: context.ink2),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              Text(value, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    ),
  );
}

class _MiniMap extends StatelessWidget {
  const _MiniMap({required this.lat, required this.lng, required this.sos, required this.trail});
  final double lat, lng;
  final bool sos;
  final List<Map> trail;
  @override
  Widget build(BuildContext context) {
    final p = LatLng(lat, lng);
    final path = trail.map((e) => LatLng((e['lat'] as num).toDouble(), (e['lng'] as num).toDouble())).toList();
    return Semantics(
      label: 'Peta lokasi kejadian',
      child: FlutterMap(
        options: MapOptions(
          initialCenter: p,
          initialZoom: 16,
          interactionOptions: const InteractionOptions(flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag),
        ),
        children: [
          osmTiles(context),
          if (path.length > 1)
            PolylineLayer(
              polylines: [Polyline(points: path, color: PK.navy, strokeWidth: 3)],
            ),
          MarkerLayer(
            markers: [
              Marker(
                point: p,
                width: 50,
                height: 50,
                alignment: Alignment.topCenter,
                child: Icon(
                  Icons.location_on_rounded,
                  size: 46,
                  color: sos ? PK.red : PK.navy,
                  shadows: const [Shadow(color: Color(0x55000000), blurRadius: 6)],
                ),
              ),
            ],
          ),
          osmAttribution(),
        ],
      ),
    );
  }
}

/// Deretan gambar mini bukti (bisa digeser): foto, video (ikon putar), suara.
class _MediaStrip extends StatelessWidget {
  const _MediaStrip({required this.media});
  final List<Map> media;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 92,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: media.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (_, i) => SizedBox(
        width: 108,
        child: _MediaTile(m: media[i], index: i),
      ),
    ),
  );
}

class _MediaTile extends StatelessWidget {
  const _MediaTile({required this.m, required this.index});
  final Map m;
  final int index;

  void _open(BuildContext context) {
    final url = m['url'] as String?;
    if (url == null) return;
    switch (m['kind']) {
      case 'video':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => VideoScreen(url: url, title: 'Bukti video'),
          ),
        );
      case 'image':
        Navigator.push(context, MaterialPageRoute(builder: (_) => _ImageViewer(url: url)));
      default:
        final p = AudioPlayer();
        p.play(UrlSource(url));
        showModalBottomSheet(
          context: context,
          builder: (context) => Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            child: Row(
              children: [
                const Icon(Icons.graphic_eq_rounded, size: 32),
                const SizedBox(width: 16),
                const Expanded(child: Text('Memutar rekaman suara…')),
                IconButton(tooltip: 'Hentikan', icon: const Icon(Icons.stop_circle_rounded, size: 36), onPressed: () => Navigator.pop(context)),
              ],
            ),
          ),
        ).whenComplete(p.dispose);
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = m['url'] as String?;
    final kind = m['kind'] as String;
    final label = kind == 'video'
        ? 'Video'
        : kind == 'image'
        ? 'Foto'
        : 'Suara';
    return Semantics(
      button: true,
      label: '$label bukti ${index + 1}',
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Material(
          color: const Color(0xFF1F2937),
          child: InkWell(
            onTap: () => _open(context),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (kind == 'image' && url != null)
                  Image.network(
                    url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const _MediaFallback(icon: Icons.broken_image_rounded),
                  )
                else
                  _MediaFallback(icon: kind == 'video' ? Icons.videocam_rounded : Icons.graphic_eq_rounded, gradient: true),
                if (kind == 'video')
                  Center(
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      child: const Icon(Icons.play_arrow_rounded, color: PK.text, size: 26),
                    ),
                  ),
                if (m['duration_s'] != null)
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(5)),
                      child: Text(
                        fmtDuration(m['duration_s'] as num),
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MediaFallback extends StatelessWidget {
  const _MediaFallback({required this.icon, this.gradient = false});
  final IconData icon;
  final bool gradient;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: gradient ? const LinearGradient(colors: [PK.navy, Color(0xFF1E3A8A), PK.redDark], begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
      color: gradient ? null : Colors.black,
    ),
    child: Center(child: Icon(icon, color: Colors.white, size: 56)),
  );
}

class _ImageViewer extends StatelessWidget {
  const _ImageViewer({required this.url});
  final String url;
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: const Text('Foto bukti')),
    body: InteractiveViewer(
      maxScale: 5,
      child: Center(child: Image.network(url, semanticLabel: 'Foto bukti')),
    ),
  );
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.items});
  final List<Map> items;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      children: [
        for (final (i, e) in items.indexed)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 28,
                  child: Column(
                    children: [
                      Container(
                        width: 14,
                        height: 14,
                        margin: const EdgeInsets.only(top: 3),
                        decoration: BoxDecoration(
                          color: _color(context, e),
                          shape: BoxShape.circle,
                          border: Border.all(color: context.surface, width: 2),
                        ),
                      ),
                      if (i < items.length - 1) Expanded(child: Container(width: 2, color: context.hairline)),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: i < items.length - 1 ? 16 : 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e['title'] as String? ?? '', style: t.titleSmall),
                        Text(
                          '${e['actor'] ?? ''}${e['is_me'] == true ? ' (Anda)' : ''} · ${fmtDateTime(DateTime.parse(e['at'] as String).toLocal())}',
                          style: t.bodySmall,
                        ),
                        if (e['note'] != null && (e['note'] as String).isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(e['note'] as String, style: t.bodyMedium),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Color _color(BuildContext context, Map e) => switch (e['action'] ?? e['kind']) {
    'created' => context.danger,
    'selesai' => PK.green,
    'tidak_valid' => PK.grey,
    'terima' || 'verifikasi' || 'tangani' || 'status' => PK.gold,
    _ => context.brand,
  };
}

class _NoteSheet extends StatefulWidget {
  const _NoteSheet({required this.title, required this.required, this.danger = false});
  final String title;
  final bool required, danger;
  @override
  State<_NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends State<_NoteSheet> {
  final _c = TextEditingController();
  String? _error;
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text('Catatan ini terlihat oleh pelapor dan pengguna di kecamatan yang sama.', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 16),
        TextField(
          controller: _c,
          autofocus: true,
          minLines: 3,
          maxLines: 5,
          maxLength: 1000,
          decoration: InputDecoration(hintText: widget.required ? 'Tulis catatan' : 'Catatan (opsional)', errorText: _error),
        ),
        const SizedBox(height: 8),
        PrimaryButton(
          label: 'Kirim',
          color: widget.danger ? PK.redDark : null,
          onPressed: () {
            if (widget.required && _c.text.trim().isEmpty) return setState(() => _error = 'Catatan wajib diisi');
            Navigator.pop(context, _c.text.trim());
          },
        ),
      ],
    ),
  );
}

/// Centang selesai: garis centang tergambar (500 ms spring) dengan percikan kecil.
Future<void> showCompletedCheck(BuildContext context) async {
  HapticFeedback.heavyImpact();
  await showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Tutup',
    barrierColor: Colors.black38,
    transitionDuration: const Duration(milliseconds: 150),
    pageBuilder: (context, _, _) => const _CheckDialog(),
  );
}

class _CheckDialog extends StatefulWidget {
  const _CheckDialog();
  @override
  State<_CheckDialog> createState() => _CheckDialogState();
}

class _CheckDialogState extends State<_CheckDialog> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  @override
  void initState() {
    super.initState();
    _c.forward();
    Future.delayed(const Duration(milliseconds: 1600), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = context.reduceMotion;
    return Center(
      child: Semantics(
        liveRegion: true,
        label: 'Laporan selesai ditangani',
        child: Container(
          width: 220,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: context.surface, borderRadius: BorderRadius.circular(24)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _c,
                builder: (_, _) => CustomPaint(size: const Size(120, 120), painter: _CheckPainter(reduce ? 1 : _c.value)),
              ),
              const SizedBox(height: 12),
              const Material(
                type: MaterialType.transparency,
                child: Text('Laporan selesai', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  _CheckPainter(this.t);
  final double t;
  @override
  void paint(Canvas canvas, Size s) {
    final c = s.center(Offset.zero);
    final circleT = Curves.elasticOut.transform((t / 0.55).clamp(0, 1));
    canvas.drawCircle(c, 40 * circleT, Paint()..color = PK.green);
    // centang tergambar
    final checkT = ((t - 0.25) / 0.4).clamp(0.0, 1.0);
    final a = c + const Offset(-18, 2), b = c + const Offset(-5, 15), d = c + const Offset(20, -13);
    final path = Path()..moveTo(a.dx, a.dy);
    if (checkT < 0.4) {
      final p = Offset.lerp(a, b, checkT / 0.4)!;
      path.lineTo(p.dx, p.dy);
    } else {
      path.lineTo(b.dx, b.dy);
      final p = Offset.lerp(b, d, (checkT - 0.4) / 0.6)!;
      path.lineTo(p.dx, p.dy);
    }
    if (checkT > 0) {
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
    // percikan kecil
    final sparkT = ((t - 0.45) / 0.55).clamp(0.0, 1.0);
    if (sparkT > 0 && sparkT < 1) {
      for (var i = 0; i < 8; i++) {
        final ang = i * math.pi / 4;
        final r1 = 46 + 14 * sparkT, r2 = r1 + 8 * (1 - sparkT);
        canvas.drawLine(
          c + Offset(math.cos(ang) * r1, math.sin(ang) * r1),
          c + Offset(math.cos(ang) * r2, math.sin(ang) * r2),
          Paint()
            ..color = (i.isEven ? PK.gold : PK.red).withValues(alpha: 1 - sparkT)
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.t != t;
}
