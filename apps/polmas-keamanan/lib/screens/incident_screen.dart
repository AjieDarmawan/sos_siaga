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
import '../widgets/ui.dart';
import 'video_screen.dart' show VideoScreen;

Future<void> openIncident(BuildContext context, String id) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => IncidentScreen(id: id)));

/// Detail & Tindak Lanjut (mockup): header navy (judul, jenis, nomor tiket, langkah Diterima → Diverifikasi →
/// Ditangani → Selesai), peta + Rute, info pelapor, lampiran, riwayat tindak lanjut, dan bilah tulis + Perbarui.
class IncidentScreen extends StatefulWidget {
  const IncidentScreen({super.key, required this.id});
  final String id;
  @override
  State<IncidentScreen> createState() => _IncidentScreenState();
}

class _IncidentScreenState extends State<IncidentScreen> {
  final _note = TextEditingController();
  Map? _d;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
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
    setState(() => _busy = true);
    final state = AppScope.read(context);
    try {
      await state.api.post('/reports/${widget.id}/responses', {'action': action, 'note': ?note});
      _note.clear();
      FocusManager.instance.primaryFocus?.unfocus();
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
      if (mounted) setState(() => _busy = false);
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

  void _route(({double lat, double lng}) l) => launchUrl(
    Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${l.lat},${l.lng}'),
    mode: LaunchMode.externalApplication,
  );

  /// "Perbarui": pilih status baru (aksi yang diizinkan server) atau kirim catatan saja.
  Future<void> _update() async {
    final note = _note.text.trim();
    final choices = [
      for (final a in const ['terima', 'verifikasi', 'tangani', 'selesai', 'tidak_valid'])
        if (_actions.contains(a)) a,
      if (_actions.contains('catatan') && note.isNotEmpty) 'catatan',
    ];
    if (choices.isEmpty) {
      showToast(context, 'Tulis catatan tindak lanjut terlebih dahulu', error: true);
      return;
    }
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text('Perbarui status', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: context.ink)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                note.isEmpty ? 'Tanpa catatan. Tulis di kolom bawah bila perlu.' : 'Catatan: "$note"',
                style: TextStyle(fontSize: 13, color: context.ink2),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            for (final a in choices)
              ListTile(
                leading: Icon(_actionIcon[a], color: a == 'tidak_valid' ? context.dangerText : context.brand),
                title: Text(_actionLabel[a]!, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(_actionHint[a]!),
                onTap: () => Navigator.pop(context, a),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action != null) await _respond(action, note: note.isEmpty ? null : note);
  }

  static const _actionLabel = {
    'terima': 'Diterima',
    'verifikasi': 'Diverifikasi',
    'tangani': 'Ditangani',
    'selesai': 'Selesai',
    'tidak_valid': 'Tidak valid',
    'catatan': 'Kirim catatan saja',
  };
  static const _actionHint = {
    'terima': 'Saya menerima laporan ini',
    'verifikasi': 'Pelapor dihubungi, kejadian benar',
    'tangani': 'Petugas menuju / di lokasi',
    'selesai': 'Kejadian sudah ditangani',
    'tidak_valid': 'Laporan palsu atau ganda',
    'catatan': 'Status tidak berubah',
  };
  static const _actionIcon = {
    'terima': Icons.mark_email_read_outlined,
    'verifikasi': Icons.verified_outlined,
    'tangani': Icons.directions_run_rounded,
    'selesai': Icons.check_circle_outline_rounded,
    'tidak_valid': Icons.block_rounded,
    'catatan': Icons.chat_bubble_outline_rounded,
  };

  Future<void> _invalid() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tandai tidak valid?'),
        content: const Text('Laporan ditutup sebagai palsu atau ganda. Pelapor akan melihat status ini.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: PK.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Tandai'),
          ),
        ],
      ),
    );
    if (ok == true) await _respond('tidak_valid', note: _note.text.trim().isEmpty ? null : _note.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    if (d == null) {
      return Scaffold(
        backgroundColor: context.pageBg,
        appBar: AppBar(title: const Text('Detail Laporan')),
        body: _error != null ? ErrorState(message: _error!, onRetry: _load) : const Center(child: CircularProgressIndicator()),
      );
    }
    final r = Report(d);
    final media = (d['media'] as List).cast<Map>();
    final timeline = (d['timeline'] as List).cast<Map>();
    final complaint = d['complaint'] as Map?;
    final loc = r.location;
    final trail = ((d['trail'] as List?) ?? const []).cast<Map>();
    final dist = r.distanceFrom(AppScope.of(context).here);
    final photosVideos = media.where((m) => m['kind'] != 'audio').toList();
    final audios = media.where((m) => m['kind'] == 'audio').toList();
    final history = timeline.reversed.toList();
    return Scaffold(
      backgroundColor: context.pageBg,
      body: Column(
        children: [
          NavyHeader(
            radius: 26,
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    HeaderIconButton(icon: Icons.chevron_left_rounded, tooltip: 'Kembali', size: 38, onTap: () => Navigator.pop(context)),
                    const Expanded(
                      child: Text('Detail Laporan', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Menu lainnya',
                      onSelected: (v) => switch (v) {
                        'hubungi' => _call(),
                        'rute' => loc == null ? null : _route(loc),
                        'tidak_valid' => _invalid(),
                        _ => null,
                      },
                      itemBuilder: (_) => [
                        if (r.reporterPhone != null) const PopupMenuItem(value: 'hubungi', child: Text('Telepon pelapor')),
                        if (loc != null) const PopupMenuItem(value: 'rute', child: Text('Buka rute di aplikasi peta')),
                        if (_actions.contains('tidak_valid')) const PopupMenuItem(value: 'tidak_valid', child: Text('Tandai tidak valid')),
                      ],
                      child: const IgnorePointer(child: HeaderIconButton(icon: Icons.more_horiz_rounded, tooltip: 'Menu lainnya', size: 38)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(r.headline, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, height: 1.3)),
                    ),
                    if (r.isDemo) const DemoTag(),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    KindTag(sos: r.isSos),
                    const SizedBox(width: 6),
                    Text(
                      '#${r.code}',
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5, color: PK.headerMute, fontWeight: FontWeight.w700),
                    ),
                    Text(' · masuk ${fmtTime(r.createdAt)}', style: const TextStyle(fontSize: 11.5, color: PK.headerMute)),
                  ],
                ),
                const SizedBox(height: 16),
                _Steps(r: r),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
                children: [
                  if (loc != null)
                    Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: context.surface,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: context.isDark ? context.hairline : const Color(0xFFE8EDF5)),
                      ),
                      child: Column(
                        children: [
                          SizedBox(height: 118, child: _MiniMap(lat: loc.lat, lng: loc.lng, sos: r.isSos, trail: trail)),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        r.locationText ?? r.sourcePlace ?? 'Titik GPS pelapor',
                                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.ink),
                                      ),
                                      Text(
                                        [
                                          if (r.kelurahan != null) 'Kel. ${r.kelurahan!.name}',
                                          if (r.kecamatan != null) 'Kec. ${r.kecamatan!.name}',
                                          ?dist,
                                        ].join(' · ').ifEmpty('Wilayah sedang ditentukan'),
                                        style: TextStyle(fontSize: 11.5, color: context.ink2),
                                      ),
                                    ],
                                  ),
                                ),
                                FilledButton.icon(
                                  onPressed: () => _route(loc),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: PK.navy,
                                    minimumSize: const Size(0, 36),
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                                  ),
                                  icon: const Icon(Icons.arrow_forward_rounded, size: 15, color: PK.gold2),
                                  label: const Text('Rute', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  Panel(
                    border: true,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    child: Column(
                      children: [
                        _Info(icon: Icons.layers_outlined, label: 'Ekosistem', value: [r.ecosystemLabel, ?r.ecosystemApp].join(' · ')),
                        _Info(icon: Icons.person_outline_rounded, label: 'Dari siapa', value: r.reporterName, sub: r.sourcePlace),
                        _Info(
                          icon: Icons.phone_outlined,
                          label: 'No HP',
                          value: r.reporterPhone == null ? 'Disamarkan' : fmtPhone(r.reporterPhone!),
                          action: r.reporterPhone == null ? null : _call,
                        ),
                        _Info(icon: Icons.calendar_today_outlined, label: 'Waktu', value: '${fmtDay(r.createdAt)} · ${fmtTime(r.createdAt)} WIB'),
                        if (complaint?['occurred_at'] != null)
                          _Info(
                            icon: Icons.schedule_rounded,
                            label: 'Waktu kejadian',
                            value: fmtDateTime(DateTime.parse(complaint!['occurred_at'] as String).toLocal()),
                          ),
                        if (complaint?['suspect'] != null) _Info(icon: Icons.person_search_outlined, label: 'Ciri pelaku', value: complaint!['suspect'] as String),
                        if (complaint?['witness'] != null) _Info(icon: Icons.record_voice_over_outlined, label: 'Saksi', value: complaint!['witness'] as String),
                        _Info(icon: Icons.newspaper_rounded, label: 'Berita', value: r.message ?? r.headline, plain: true, last: true),
                      ],
                    ),
                  ),
                  SectionHead(
                    'Lampiran',
                    trailing: Text(
                      media.isEmpty
                          ? 'tidak ada'
                          : [
                              if (photosVideos.isNotEmpty) '${photosVideos.length} foto/video',
                              if (audios.isNotEmpty) '${audios.length} suara',
                            ].join(' · '),
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: context.ink2),
                    ),
                  ),
                  if (media.isEmpty)
                    Text('Pelapor belum melampirkan foto, video, atau suara.', style: TextStyle(fontSize: 13, color: context.ink2))
                  else ...[
                    if (photosVideos.isNotEmpty)
                      GridView.count(
                        crossAxisCount: 3,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 1.25,
                        children: [for (final m in photosVideos) _MediaTile(m: m)],
                      ),
                    for (final a in audios) _AudioTile(m: a),
                  ],
                  const SectionHead('Riwayat Tindak Lanjut'),
                  Panel(
                    border: true,
                    margin: EdgeInsets.zero,
                    padding: const EdgeInsets.all(14),
                    child: Column(children: [for (final (i, e) in history.indexed) _TimelineRow(e: e, first: i == 0, last: i == history.length - 1)]),
                  ),
                ],
              ),
            ),
          ),
          _bottomBar(r),
        ],
      ),
    );
  }

  Widget _bottomBar(Report r) {
    final closed = const {PkStatus.selesai, PkStatus.tidakValid, PkStatus.dibatalkan}.contains(r.status);
    final pad = EdgeInsets.fromLTRB(14, 10, 14, 10 + MediaQuery.of(context).padding.bottom);
    final deco = BoxDecoration(
      color: context.surface,
      border: Border(top: BorderSide(color: context.hairline)),
    );
    if (_actions.isEmpty) {
      return Container(
        padding: pad,
        decoration: deco,
        child: Row(
          children: [
            Icon(closed ? Icons.lock_outline_rounded : Icons.visibility_outlined, size: 18, color: context.ink2),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                closed ? 'Laporan sudah ditutup.' : 'Anda hanya dapat melihat laporan ini.',
                style: TextStyle(fontSize: 13, color: context.ink2),
              ),
            ),
            if (r.reporterPhone != null && !closed)
              FilledButton.icon(
                onPressed: _call,
                style: FilledButton.styleFrom(backgroundColor: PK.green),
                icon: const Icon(Icons.phone_rounded, size: 16),
                label: const Text('Telepon'),
              ),
          ],
        ),
      );
    }
    return Container(
      padding: pad,
      decoration: deco,
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: context.pageBg,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: context.hairline),
              ),
              child: TextField(
                controller: _note,
                maxLength: 1000,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _update(),
                style: TextStyle(fontSize: 13, color: context.ink),
                decoration: InputDecoration(
                  hintText: 'Tulis tindak lanjut…',
                  hintStyle: const TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8)),
                  counterText: '',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  isCollapsed: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 13),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 44,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF123A94), PK.navy]),
                borderRadius: BorderRadius.circular(13),
              ),
              child: TextButton(
                onPressed: _busy ? null : _update,
                style: TextButton.styleFrom(foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 14)),
                child: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Perbarui', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

/// Langkah status di header: lingkaran emas bercentang untuk yang sudah, cincin putih untuk yang sedang.
class _Steps extends StatelessWidget {
  const _Steps({required this.r});
  final Report r;
  @override
  Widget build(BuildContext context) {
    final s = r.status;
    final verified = r.raw['verified_at'] != null;
    final done = [
      s != PkStatus.baru,
      verified || s == PkStatus.ditangani || s == PkStatus.selesai,
      s == PkStatus.ditangani || s == PkStatus.selesai,
      s == PkStatus.selesai,
    ];
    final closedOther = s == PkStatus.tidakValid || s == PkStatus.dibatalkan;
    final labels = ['Diterima', 'Diverifikasi', 'Ditangani', closedOther ? (s == PkStatus.tidakValid ? 'Tidak valid' : 'Dibatalkan') : 'Selesai'];
    if (closedOther) done[3] = true;
    final current = done.indexWhere((x) => !x);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < 4; i++)
          Expanded(
            child: Semantics(
              label: '${labels[i]}: ${done[i] ? 'sudah' : (i == current ? 'sedang' : 'belum')}',
              excludeSemantics: true,
              child: Column(
                children: [
                  SizedBox(
                    height: 24,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (i > 0)
                          Positioned(
                            left: 0,
                            right: null,
                            child: FractionallySizedBox(widthFactor: 0.5, child: Container(height: 2)),
                          ),
                        Row(
                          children: [
                            Expanded(
                              child: Container(height: 2, color: i == 0 ? Colors.transparent : (done[i] || i == current ? PK.gold : Colors.white24)),
                            ),
                            Expanded(
                              child: Container(height: 2, color: i == 3 ? Colors.transparent : (done[i + 1] || i + 1 == current ? PK.gold : Colors.white24)),
                            ),
                          ],
                        ),
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: done[i] ? (closedOther && i == 3 ? PK.headerMute : PK.gold) : (i == current ? Colors.white : const Color(0xFF1A3576)),
                            border: Border.all(color: done[i] || i == current ? PK.gold : Colors.white24, width: 2),
                            boxShadow: i == current ? const [BoxShadow(color: Color(0x4DD4A82A), spreadRadius: 4)] : null,
                          ),
                          child: done[i]
                              ? const Icon(Icons.check_rounded, size: 13, color: PK.navy2)
                              : i == current
                              ? Center(
                                  child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: PK.navy, shape: BoxShape.circle)),
                                )
                              : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    labels[i],
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: done[i] || i == current ? Colors.white : const Color(0xFF8EA2CC)),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.icon, required this.label, required this.value, this.sub, this.action, this.plain = false, this.last = false});
  final IconData icon;
  final String label, value;
  final String? sub;
  final VoidCallback? action;
  final bool plain, last;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 10),
    decoration: BoxDecoration(
      border: last ? null : Border(bottom: BorderSide(color: context.isDark ? context.hairline : const Color(0xFFF1F4F9))),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(color: context.isDark ? context.hairline : const Color(0xFFEEF2FB), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, size: 16, color: context.brand),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: context.ink2)),
              const SizedBox(height: 1),
              Text(value, style: TextStyle(fontSize: 13, height: plain ? 1.45 : 1.3, fontWeight: plain ? FontWeight.w500 : FontWeight.w700, color: context.ink)),
              if (sub != null) Text(sub!, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: context.ink2)),
            ],
          ),
        ),
        if (action != null)
          Tooltip(
            message: 'Telepon pelapor',
            child: Material(
              color: const Color(0xFFD1FADF),
              borderRadius: BorderRadius.circular(11),
              child: InkWell(
                borderRadius: BorderRadius.circular(11),
                onTap: action,
                child: const SizedBox(width: 34, height: 34, child: Icon(Icons.phone_outlined, size: 16, color: PK.greenDark)),
              ),
            ),
          ),
      ],
    ),
  );
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.e, required this.first, required this.last});
  final Map e;
  final bool first, last;
  @override
  Widget build(BuildContext context) {
    final at = DateTime.parse(e['at'] as String).toLocal();
    final note = e['note'] as String?;
    final actor = '${e['actor'] ?? ''}${e['is_me'] == true ? ' (Anda)' : ''}';
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 12,
            child: Column(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  margin: const EdgeInsets.only(top: 3),
                  decoration: BoxDecoration(
                    color: first ? PK.gold : PK.navy,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: first ? const Color(0xFFFBF1D3) : PK.navySoft, spreadRadius: 3)],
                  ),
                ),
                if (!last) Expanded(child: Container(width: 2, margin: const EdgeInsets.only(top: 3), color: context.hairline)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    [e['title'] as String? ?? '', if (actor.isNotEmpty) actor].join(' · '),
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [fmtTime(at), if (note != null && note.isNotEmpty) note].join(' · '),
                    style: TextStyle(fontSize: 11.5, height: 1.4, color: context.ink2),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
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
          if (path.length > 1) PolylineLayer(polylines: [Polyline(points: path, color: PK.navy, strokeWidth: 3)]),
          MarkerLayer(
            markers: [
              Marker(
                point: p,
                width: 44,
                height: 44,
                alignment: Alignment.topCenter,
                child: Icon(
                  Icons.location_on_rounded,
                  size: 40,
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

class _MediaTile extends StatelessWidget {
  const _MediaTile({required this.m});
  final Map m;
  @override
  Widget build(BuildContext context) {
    final url = m['url'] as String?;
    final video = m['kind'] == 'video';
    return Semantics(
      button: true,
      label: video ? 'Putar video bukti' : 'Lihat foto bukti',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: url == null
            ? null
            : () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => video ? VideoScreen(url: url, title: 'Bukti video') : _ImageViewer(url: url)),
              ),
        child: LayoutBuilder(
          builder: (_, c) => MediaThumb(url: url, kind: m['kind'] as String, seconds: m['duration_s'] as num?, width: c.maxWidth, height: c.maxHeight),
        ),
      ),
    );
  }
}

/// Rekaman suara: ▶ + gelombang + durasi, putar di tempat.
class _AudioTile extends StatefulWidget {
  const _AudioTile({required this.m});
  final Map m;
  @override
  State<_AudioTile> createState() => _AudioTileState();
}

class _AudioTileState extends State<_AudioTile> {
  final _player = AudioPlayer();
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _player.onPlayerComplete.listen((_) => mounted ? setState(() => _playing = false) : null);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    final url = widget.m['url'] as String?;
    if (url == null) return;
    if (_playing) {
      await _player.stop();
    } else {
      await _player.play(UrlSource(url));
    }
    if (mounted) setState(() => _playing = !_playing);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Material(
      color: context.isDark ? context.hairline : const Color(0xFFEEF2F8),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _toggle,
        child: SizedBox(
          height: 46,
          child: Row(
            children: [
              const SizedBox(width: 12),
              Icon(_playing ? Icons.stop_rounded : Icons.play_arrow_rounded, color: context.brand),
              const SizedBox(width: 10),
              Expanded(child: CustomPaint(size: const Size(double.infinity, 22), painter: _WavePainter(context.brand))),
              const SizedBox(width: 10),
              Text(
                widget.m['duration_s'] == null ? 'Suara' : fmtClock(widget.m['duration_s'] as num),
                style: TextStyle(fontFamily: 'monospace', fontSize: 11.5, fontWeight: FontWeight.w700, color: context.brand),
              ),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    ),
  );
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.color);
  final Color color;
  static const _h = [0.4, 0.7, 0.35, 0.9, 0.5, 1.0, 0.45, 0.75, 0.3, 0.85, 0.55, 0.95, 0.4, 0.7, 0.5, 0.8, 0.35, 0.65, 0.9, 0.45];
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color.withValues(alpha: 0.8)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final n = (size.width / 5).floor();
    for (var i = 0; i < n; i++) {
      final h = _h[i % _h.length] * size.height;
      final x = i * 5.0 + 1;
      canvas.drawLine(Offset(x, (size.height - h) / 2), Offset(x, (size.height + h) / 2), p);
    }
  }

  @override
  bool shouldRepaint(_WavePainter o) => o.color != color;
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

/// Centang selesai: lingkaran hijau membesar + "Laporan selesai", tutup sendiri setelah 1,4 dtk.
Future<void> showCompletedCheck(BuildContext context) async {
  HapticFeedback.heavyImpact();
  await showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Tutup',
    barrierColor: Colors.black38,
    transitionDuration: const Duration(milliseconds: 220),
    transitionBuilder: (context, a, _, child) =>
        ScaleTransition(scale: CurvedAnimation(parent: a, curve: context.reduceMotion ? Curves.linear : Curves.easeOutBack), child: child),
    pageBuilder: (context, _, _) {
      Future.delayed(const Duration(milliseconds: 1400), () {
        if (context.mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
      });
      return Center(
        child: Semantics(
          liveRegion: true,
          label: 'Laporan selesai ditangani',
          child: Container(
            width: 210,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: context.surface, borderRadius: BorderRadius.circular(24)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: const BoxDecoration(color: Color(0xFFD1FADF), shape: BoxShape.circle),
                  child: const Icon(Icons.check_rounded, size: 52, color: PK.greenDark),
                ),
                const SizedBox(height: 14),
                Material(
                  type: MaterialType.transparency,
                  child: Text('Laporan selesai', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: context.ink)),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
