import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../theme/tokens.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import 'home_shell.dart';
import 'incident_screen.dart';

/// Analisa & Evaluasi (FR-19, FR-20, FR-21): pilihan periode, kartu ringkasan, tren harian, per kelurahan, jenis
/// kejadian, jam rawan (peta panas), lalu evaluasi waktu respons & perbandingan periode sebelumnya. Bagikan sebagai PDF.
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});
  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  String _period = '7d';
  DateTimeRange? _custom;
  Map? _sum, _eval;
  String? _error;
  bool _loading = true;
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

  String _d(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Map<String, String?> get _q => {
    'period': _period,
    if (_period == 'custom' && _custom != null) 'from': _d(_custom!.start),
    if (_period == 'custom' && _custom != null) 'to': _d(_custom!.end),
  };

  Future<void> _load() async {
    setState(() => _loading = true);
    final api = AppScope.read(context).api;
    try {
      final res = await Future.wait([api.get('/analytics/summary', _q), api.get('/analytics/evaluation', _q)]);
      if (!mounted) return;
      setState(() {
        _sum = res[0] as Map;
        _eval = res[1] as Map;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickPeriod(String p) async {
    if (p == 'custom') {
      final now = DateTime.now();
      final r = await showDateRangePicker(context: context, firstDate: now.subtract(const Duration(days: 365)), lastDate: now, helpText: 'Periode analisa');
      if (r == null) return;
      _custom = r;
    }
    setState(() => _period = p);
    await _load();
  }

  String get _periodLabel => switch (_period) {
    '7d' => '7 hari terakhir',
    '30d' => '30 hari terakhir',
    '90d' => '3 bulan terakhir',
    _ => _custom == null ? 'Kustom' : '${fmtShort(_custom!.start)} – ${fmtShort(_custom!.end)}',
  };

  @override
  Widget build(BuildContext context) {
    final me = AppScope.of(context).me!;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text('Analisa', style: t.headlineSmall?.copyWith(fontSize: 30, fontWeight: FontWeight.w800)),
                    ),
                  ),
                  IconButton(tooltip: 'Bagikan ringkasan (PDF)', icon: const Icon(Icons.ios_share_rounded), onPressed: _sum == null ? null : () => _share(me)),
                  const NotifBell(),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _PeriodSegment(value: _period, onChanged: _pickPeriod),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: _period == 'custom' ? PK.red : (context.isDark ? PK.darkSurface : const Color(0xFFF1F3F6)),
                    borderRadius: BorderRadius.circular(12),
                    child: IconButton(
                      tooltip: 'Periode kustom',
                      onPressed: () => _pickPeriod('custom'),
                      icon: Icon(Icons.date_range_rounded, color: _period == 'custom' ? Colors.white : context.ink),
                    ),
                  ),
                ],
              ),
              if (_period == 'custom')
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(_periodLabel, style: t.bodySmall),
                ),
              const SizedBox(height: 12),
              if (_loading && _sum == null)
                const Padding(
                  padding: EdgeInsets.all(48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null && _sum == null)
                ErrorState(message: _error!, onRetry: _load)
              else
                AnimatedOpacity(opacity: _loading ? 0.5 : 1, duration: const Duration(milliseconds: 150), child: _content(me)),
            ],
          ),
        ),
      ),
    );
  }

  /// Persen perubahan terhadap periode sebelumnya (null bila periode lalu 0).
  int? _delta(Map? prev, String k, int cur) {
    final p = (prev?[k] as num?)?.toInt();
    if (p == null || p == 0) return null;
    return ((cur - p) * 100 / p).round();
  }

  Widget _content(Me me) {
    final s = _sum!, e = _eval!;
    final t = Theme.of(context).textTheme;
    final totals = s['totals'] as Map;
    final prev = s['previous_totals'] as Map?;
    int n(String k) => (totals[k] as num?)?.toInt() ?? 0;
    final kel = (s['by_kelurahan'] as List).cast<Map>();
    final proses = n('diproses') + n('baru');
    final prevProses = prev == null ? null : {'p': ((prev['diproses'] as num?) ?? 0) + ((prev['baru'] as num?) ?? 0)};
    final days = (s['period'] as Map)['days'] as num;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StatGrid(
          children: [
            StatCard(
              label: 'Total Laporan',
              value: n('total'),
              icon: Icons.description_rounded,
              color: const Color(0xFF2A78D6),
              delta: _delta(prev, 'total', n('total')),
            ),
            StatCard(
              label: 'Laporan Darurat',
              value: n('sos'),
              icon: Icons.notifications_active_rounded,
              color: context.danger,
              delta: _delta(prev, 'sos', n('sos')),
              lowerIsBetter: true,
            ),
            StatCard(
              label: 'Dalam Proses',
              value: proses,
              icon: Icons.hourglass_bottom_rounded,
              color: const Color(0xFFE09A00),
              delta: _delta(prevProses, 'p', proses),
              lowerIsBetter: true,
            ),
            StatCard(label: 'Selesai', value: n('selesai'), icon: Icons.check_circle_rounded, color: PK.green, delta: _delta(prev, 'selesai', n('selesai'))),
          ],
        ),
        const SizedBox(height: 16),
        _Section(
          title: 'Tren Laporan Harian ($days Hari)',
          child: TrendChart(days: (s['trend'] as List).cast<Map>()),
        ),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _Section(
                  title: 'Laporan per Kelurahan',
                  compact: true,
                  child: kel.isEmpty
                      ? const Text('Belum ada data')
                      : RankBars(nameWidth: 64, items: [for (final k in kel.take(6)) (k['name'] as String, k['n'] as num)]),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Section(
                  title: 'Jenis Kejadian',
                  compact: true,
                  child: CategoryDonut(vertical: true, items: (s['by_category'] as List).cast<Map>()),
                ),
              ),
            ],
          ),
        ),
        _Section(
          title: 'Waktu Terbanyak Terjadi Laporan',
          child: HourHeatmap(cells: (s['heatmap'] as List).cast<Map>()),
        ),
        const SizedBox(height: 8),
        Semantics(
          header: true,
          child: Text('Evaluasi', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        ),
        const SizedBox(height: 4),
        Text(
          'Dibanding ${fmtShort(DateTime.parse(e['period']['prev_from'] as String))} – ${fmtShort(DateTime.parse(e['period']['prev_to'] as String))}',
          style: t.bodySmall,
        ),
        const SizedBox(height: 10),
        _Evaluation(e: e),
      ],
    );
  }

  Future<void> _share(Me me) async {
    try {
      final s = _sum!, e = _eval!;
      final totals = s['totals'] as Map;
      final cur = e['current'] as Map, prev = e['previous'] as Map;
      final doc = pw.Document(title: 'Ringkasan Polmas Keamanan');
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (_) => [
            pw.Container(height: 6, color: PdfColor.fromHex('#D71920')),
            pw.SizedBox(height: 12),
            pw.Text(
              'Ringkasan Keamanan',
              style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#0B2A6B')),
            ),
            pw.Text('${me.scope != null ? 'Kec. ${me.scope!.name} · ' : ''}$_periodLabel · dibuat ${fmtDateTime(DateTime.now())} oleh ${me.name}'),
            if (me.isDemo)
              pw.Text(
                'DATA DEMO (fiktif)',
                style: pw.TextStyle(color: PdfColor.fromHex('#A80F15'), fontWeight: pw.FontWeight.bold),
              ),
            pw.SizedBox(height: 16),
            pw.TableHelper.fromTextArray(
              headers: ['Ukuran', 'Nilai'],
              data: [
                ['Total kejadian', '${totals['total']}'],
                ['SOS', '${totals['sos']}'],
                ['Laporan', '${totals['laporan']}'],
                ['Selesai', '${totals['selesai']}'],
                ['Diproses / baru', '${(totals['diproses'] as num) + (totals['baru'] as num)}'],
                ['Waktu respons rata-rata', fmtDuration(cur['avg_response_s'] as num?)],
                ['Persentase selesai', cur['pct_selesai'] == null ? '–' : '${cur['pct_selesai']}%'],
                ['Laporan tertunda', '${cur['tertunda']}'],
                ['Periode sebelumnya: total / selesai', '${prev['total']} / ${prev['selesai']}'],
              ],
            ),
            pw.SizedBox(height: 16),
            pw.Text('Per kelurahan', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.TableHelper.fromTextArray(
              headers: ['Kelurahan', 'Jumlah'],
              data: [
                for (final k in (s['by_kelurahan'] as List).cast<Map>()) [k['name'], '${k['n']}'],
              ],
            ),
            pw.SizedBox(height: 16),
            pw.Text('Jenis kejadian', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.TableHelper.fromTextArray(
              headers: ['Jenis', 'Jumlah'],
              data: [
                for (final c in (s['by_category'] as List).cast<Map>()) [categoryLabel(c['name'] as String), '${c['n']}'],
              ],
            ),
            pw.SizedBox(height: 16),
            pw.Text('Tren harian', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.TableHelper.fromTextArray(
              headers: ['Tanggal', 'SOS', 'Laporan'],
              data: [
                for (final d in (s['trend'] as List).cast<Map>()) [fmtShort(DateTime.parse(d['day'] as String)), '${d['sos']}', '${d['laporan']}'],
              ],
            ),
          ],
        ),
      );
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/ringkasan-polmas-${DateTime.now().millisecondsSinceEpoch}.pdf');
      await file.writeAsBytes(await doc.save());
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/pdf')],
          text: 'Ringkasan keamanan $_periodLabel',
        ),
      );
    } catch (_) {
      if (mounted) showToast(context, 'Gagal membuat PDF ringkasan', error: true);
    }
  }
}

/// Segmen periode 7 hari / 30 hari / 3 bulan: lintasan abu, aktif pil merah.
class _PeriodSegment extends StatelessWidget {
  const _PeriodSegment({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => Container(
    height: 46,
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(color: context.isDark ? PK.darkSurface : const Color(0xFFF1F3F6), borderRadius: BorderRadius.circular(14)),
    child: Row(
      children: [
        for (final (k, l) in const [('7d', '7 hari'), ('30d', '30 hari'), ('90d', '3 bulan')])
          Expanded(
            child: Semantics(
              button: true,
              selected: value == k,
              label: l,
              excludeSemantics: true,
              child: GestureDetector(
                onTap: () => onChanged(k),
                child: AnimatedContainer(
                  duration: context.reduceMotion ? Duration.zero : PK.tab,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: value == k ? PK.red : Colors.transparent, borderRadius: BorderRadius.circular(11)),
                  child: Text(
                    l,
                    style: TextStyle(fontSize: 15, fontWeight: value == k ? FontWeight.w700 : FontWeight.w500, color: value == k ? Colors.white : context.ink),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.compact = false});
  final String title;
  final Widget child;

  /// Kartu setengah lebar: padding & judul lebih kecil.
  final bool compact;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: AppCard(
      padding: EdgeInsets.all(compact ? 12 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: (compact ? Theme.of(context).textTheme.titleSmall : Theme.of(context).textTheme.titleMedium)?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    ),
  );
}

/// Waktu respons, % selesai, tertunda, dibanding periode sebelumnya (panah naik/turun hijau/merah + teks).
class _Evaluation extends StatelessWidget {
  const _Evaluation({required this.e});
  final Map e;
  @override
  Widget build(BuildContext context) {
    final cur = e['current'] as Map, prev = e['previous'] as Map;
    final pending = (e['pending'] as List).cast<Map>();
    final detail = e['detail'] == true;
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Metric(
          icon: Icons.timer_rounded,
          label: 'Waktu respons rata-rata',
          value: fmtDuration(cur['avg_response_s'] as num?),
          cur: cur['avg_response_s'] as num?,
          prev: prev['avg_response_s'] as num?,
          lowerIsBetter: true,
          fmt: (v) => fmtDuration(v),
        ),
        _Metric(
          icon: Icons.task_alt_rounded,
          label: 'Laporan selesai',
          value: cur['pct_selesai'] == null ? '–' : '${cur['pct_selesai'].toString().replaceAll('.', ',')}%',
          cur: cur['pct_selesai'] as num?,
          prev: prev['pct_selesai'] as num?,
          fmt: (v) => '${v.toString().replaceAll('.', ',')}%',
        ),
        _Metric(
          icon: Icons.pending_actions_rounded,
          label: 'Laporan tertunda',
          value: '${cur['tertunda']}',
          cur: cur['tertunda'] as num?,
          prev: prev['tertunda'] as num?,
          lowerIsBetter: true,
          fmt: (v) => '$v',
        ),
        if (!detail)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${cur['ditanggapi']} dari ${cur['total']} laporan sudah ditanggapi, rata-rata dalam ${fmtDuration(cur['avg_response_s'] as num?)}.',
              style: t.bodyMedium,
            ),
          ),
        if (detail) ...[
          const SizedBox(height: 8),
          Text('Belum ditanggapi (${pending.length})', style: t.titleMedium),
          const SizedBox(height: 8),
          if (pending.isEmpty)
            AppCard(
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: PK.green),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Semua laporan sudah ditanggapi.', style: t.bodyMedium)),
                ],
              ),
            )
          else
            for (final p in pending)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AppCard(
                  onTap: () => openIncident(context, p['id'] as String),
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(p['kind'] == 'sos' ? Icons.sos_rounded : Icons.assignment_rounded, color: p['kind'] == 'sos' ? context.danger : context.brand),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(Report(p).headline, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleSmall),
                            Text(
                              '${Report(p).placeLine.isEmpty ? Report(p).sourceLabel : Report(p).placeLine} · menunggu ${fmtDuration((p['age_min'] as num) * 60)}',
                              style: t.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      if (p['late'] == true)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: context.danger.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.schedule_rounded, size: 14, color: context.dangerText),
                              const SizedBox(width: 4),
                              Text(
                                'Terlambat',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.dangerText),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
        ],
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.icon,
    required this.label,
    required this.value,
    required this.cur,
    required this.prev,
    required this.fmt,
    this.lowerIsBetter = false,
  });
  final IconData icon;
  final String label, value;
  final num? cur, prev;
  final bool lowerIsBetter;
  final String Function(num) fmt;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget? delta;
    String deltaText = 'Tidak ada data periode sebelumnya';
    if (cur != null && prev != null && prev != 0) {
      final diff = cur! - prev!;
      final better = lowerIsBetter ? diff < 0 : diff > 0;
      final same = diff == 0;
      final color = same ? context.ink2 : (better ? PK.green : context.danger);
      final pct = (diff.abs() * 100 / prev!.abs()).round();
      deltaText = same ? 'Sama dengan periode sebelumnya' : '${diff > 0 ? 'Naik' : 'Turun'} $pct% (${better ? 'membaik' : 'memburuk'}) dari ${fmt(prev!)}';
      delta = Icon(same ? Icons.trending_flat_rounded : (diff > 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded), color: color);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        label: '$label: $value. $deltaText',
        excludeSemantics: true,
        child: AppCard(
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: context.brand.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: Icon(icon, color: context.brand),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: t.bodySmall),
                    Text(value, style: t.titleLarge),
                    Text(deltaText, style: t.bodySmall),
                  ],
                ),
              ),
              ?delta,
            ],
          ),
        ),
      ),
    );
  }
}
