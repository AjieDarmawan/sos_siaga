import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/ui.dart';
import 'incident_screen.dart';
import 'reports_screen.dart' show ReportTable;

/// Beranda (mockup): header navy (sapaan, nama, peran · wilayah, lonceng), kartu merah SOS masuk, 4 angka,
/// Tindak Lanjut Terbaru (kartu atau tabel).
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.onOpenReports});
  final void Function([String? status]) onOpenReports;
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map? _cards;
  Report? _sos;
  List<Report> _latest = const [];
  String? _error;
  bool _table = false;
  int _version = -1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final v = AppScope.of(context).dataVersion;
    if (v != _version) {
      _version = v;
      _load();
    }
  }

  Future<void> _load() async {
    final api = AppScope.read(context).api;
    try {
      final res = await Future.wait([
        api.get('/dashboard'),
        api.get('/reports', {'kind': 'sos', 'status': 'baru', 'limit': '1'}),
        api.get('/reports', {'limit': '6'}),
      ]);
      if (!mounted) return;
      final sos = ((res[1] as Map)['items'] as List).map((e) => Report(e as Map)).firstOrNull;
      setState(() {
        _cards = (res[0] as Map)['cards'] as Map;
        _sos = sos;
        _latest = ((res[2] as Map)['items'] as List).map((e) => Report(e as Map)).where((r) => r.id != sos?.id).take(5).toList();
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _call(Report r) async {
    final p = r.reporterPhone;
    if (p == null) return;
    final ok = await launchUrl(Uri(scheme: 'tel', path: '+${p.replaceAll(RegExp(r'[^0-9]'), '')}'));
    if (!ok && mounted) showToast(context, 'Tidak bisa membuka aplikasi telepon', error: true);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final me = state.me!;
    final c = _cards;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          NavyHeader(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 76),
            child: Row(
              children: [
                _Avatar(name: me.name),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Selamat bertugas,', style: TextStyle(fontSize: 12, color: PK.headerMute)),
                      Text(me.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(me.identity, style: const TextStyle(fontSize: 12, color: PK.headerMute), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                if (me.isDemo) const Padding(padding: EdgeInsets.only(right: 8), child: DemoTag()),
                HeaderIconButton(
                  icon: Icons.notifications_none_rounded,
                  tooltip: state.openReports > 0 ? '${state.openReports} laporan belum ditanggapi' : 'Laporan baru',
                  dot: state.openReports > 0,
                  onTap: () => widget.onOpenReports('baru'),
                ),
              ],
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -58),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_sos != null) _SosAlert(r: _sos!, here: state.here, onRespond: () => openIncident(context, _sos!.id), onCall: () => _call(_sos!)) else const _AllClear(),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _Stat(color: PK.red, value: c?['sos_today'], label: 'SOS\nhari ini'),
                      _Stat(color: const Color(0xFF4F7BD9), value: c?['new_reports'], label: 'Laporan\nbaru'),
                      _Stat(color: PK.amber, value: c?['in_progress'], label: 'Dalam\npenanganan'),
                      _Stat(color: PK.green, value: c?['resolved_7d'], label: 'Selesai\n7 hari', last: true),
                    ],
                  ),
                  SectionHead('Tindak Lanjut Terbaru', trailing: ViewToggle(table: _table, onChanged: (v) => setState(() => _table = v))),
                  if (_error != null && _cards == null)
                    ErrorState(message: _error!, onRetry: _load)
                  else if (_cards == null)
                    const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
                  else if (_latest.isEmpty)
                    const EmptyState(icon: Icons.inbox_outlined, title: 'Belum ada laporan', body: 'Laporan dari wilayah dan Nomor Darurat Anda akan tampil di sini.')
                  else if (_table)
                    ReportTable(items: _latest)
                  else
                    for (final r in _latest) ReportCard(r: r, here: state.here, showDate: false, onTap: () => openIncident(context, r.id)),
                  if (_latest.isNotEmpty)
                    Center(
                      child: TextButton(
                        onPressed: widget.onOpenReports,
                        child: Text('Lihat semua tindak lanjut', style: TextStyle(fontWeight: FontWeight.w700, color: context.brand)),
                      ),
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

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name});
  final String name;
  static const size = 46.0;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: const Color(0xFF1E3F8F),
      shape: BoxShape.circle,
      border: Border.all(color: PK.gold, width: 2),
    ),
    child: Text(initials(name), style: TextStyle(fontWeight: FontWeight.w800, fontSize: size * 0.34, color: Colors.white)),
  );
}

/// "Andi Saputra" → "AS".
String initials(String name) {
  final w = name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
  if (w.isEmpty) return '?';
  if (w.length == 1) return w.first.substring(0, 1).toUpperCase();
  return (w.first[0] + w.last[0]).toUpperCase();
}

class _SosAlert extends StatefulWidget {
  const _SosAlert({required this.r, required this.here, required this.onRespond, required this.onCall});
  final Report r;
  final ({double lat, double lng})? here;
  final VoidCallback onRespond, onCall;
  @override
  State<_SosAlert> createState() => _SosAlertState();
}

class _SosAlertState extends State<_SosAlert> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.r;
    final dist = r.distanceFrom(widget.here);
    final place = placeText(r);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFEA3A2E), Color(0xFFAE1F14)]),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Color(0xCCD92D20), blurRadius: 28, offset: Offset(0, 16), spreadRadius: -14)],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Positioned(right: -16, top: -12, child: Icon(Icons.campaign_outlined, size: 120, color: Color(0x1FFFFFFF))),
          DefaultTextStyle.merge(
            style: const TextStyle(color: Colors.white),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedBuilder(
                            animation: _pulse,
                            builder: (_, _) => Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: context.reduceMotion
                                    ? null
                                    : [BoxShadow(color: Colors.white.withValues(alpha: 0.85 * (1 - _pulse.value)), spreadRadius: 9 * _pulse.value)],
                              ),
                            ),
                          ),
                          const SizedBox(width: 7),
                          const Text('SOS MASUK', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1)),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Text(fmtRelative(r.createdAt), style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.85))),
                  ],
                ),
                const SizedBox(height: 11),
                Text(r.headline, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                EcoChip(label: r.ecosystemLabel, app: r.ecosystemApp, onDark: true),
                const SizedBox(height: 4),
                _line(Icons.person_outline_rounded, [r.reporterName, ?r.sourcePlace].join(' · ')),
                if (place.isNotEmpty || dist != null) _line(Icons.location_on_outlined, [if (place.isNotEmpty) place, ?dist].join(' · ')),
                const SizedBox(height: 13),
                Row(
                  children: [
                    Expanded(
                      child: _AlertBtn(label: 'Tanggapi', icon: Icons.back_hand_outlined, filled: true, onTap: widget.onRespond),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _AlertBtn(label: 'Telepon', icon: Icons.phone_outlined, onTap: r.reporterPhone == null ? null : widget.onCall),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _line(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(top: 5),
    child: Row(
      children: [
        Icon(icon, size: 15, color: Colors.white),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text, style: TextStyle(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.94)), maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    ),
  );
}

class _AlertBtn extends StatelessWidget {
  const _AlertBtn({required this.label, required this.icon, required this.onTap, this.filled = false});
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool filled;
  @override
  Widget build(BuildContext context) => Opacity(
    opacity: onTap == null ? 0.5 : 1,
    child: Material(
      color: filled ? Colors.white : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: filled ? BorderSide.none : BorderSide(color: Colors.white.withValues(alpha: 0.55), width: 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          height: 42,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 17, color: filled ? PK.redDark : Colors.white),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: filled ? PK.redDark : Colors.white)),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Pengganti kartu merah saat tidak ada SOS yang menunggu.
class _AllClear extends StatelessWidget {
  const _AllClear();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: context.surface,
      borderRadius: BorderRadius.circular(20),
      boxShadow: const [BoxShadow(color: Color(0x330B2A6F), blurRadius: 28, offset: Offset(0, 14), spreadRadius: -16)],
    ),
    child: Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: const Color(0xFFD1FADF), borderRadius: BorderRadius.circular(13)),
          child: const Icon(Icons.verified_user_outlined, color: PK.greenDark),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Tidak ada SOS yang menunggu', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: context.ink)),
              const SizedBox(height: 2),
              Text('SOS baru akan berbunyi dan tampil di sini.', style: TextStyle(fontSize: 12.5, color: context.ink2)),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.color, required this.value, required this.label, this.last = false});
  final Color color;
  final Object? value;
  final String label;
  final bool last;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      margin: EdgeInsets.only(right: last ? 0 : 8),
      padding: const EdgeInsets.fromLTRB(9, 10, 9, 10),
      constraints: const BoxConstraints(minHeight: 86),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(color: Color(0x400F172A), blurRadius: 16, offset: Offset(0, 6), spreadRadius: -10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(width: 18, height: 4, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 7),
          Text(
            value == null ? '–' : '$value',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, height: 1.1, color: context.ink, fontFeatures: const [FontFeature.tabularFigures()]),
          ),
          const SizedBox(height: 2),
          // Dua baris tetap; mengecil bila huruf perangkat besar supaya kata tidak terpotong di tengah.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(label, maxLines: 2, style: TextStyle(fontSize: 10.5, height: 1.25, fontWeight: FontWeight.w600, color: context.ink2)),
          ),
        ],
      ),
    ),
  );
}
