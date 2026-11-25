import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/ui.dart';
import 'incident_screen.dart';

/// Analitik (mockup, 4 tab): Ringkasan, Ekosistem, Waktu & Wilayah, Kinerja. Filter periode + ekosistem berlaku
/// untuk semua tab. Data: GET /analytics/summary + /analytics/evaluation.
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});
  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

const _tabs = ['Ringkasan', 'Ekosistem', 'Waktu & Wilayah', 'Kinerja'];
const _periods = [('7d', '7 hari terakhir'), ('30d', '30 hari terakhir'), ('90d', '90 hari terakhir')];
const _pillars = [('umkm', 'UMKM'), ('warga', 'Lingkungan'), ('kantor', 'Perkantoran'), ('sekolah', 'Pendidikan'), ('komunitas', 'Komunitas')];

/// Palet kategori (urut sesuai jumlah): SOS merah dulu bila ada, lalu navy → emas → abu.
const _catColors = [PK.navy, PK.blueMid, PK.gold, PK.blueSoft, Color(0xFF8C6A0A), Color(0xFF98A6C0), Color(0xFFD3DAE6), Color(0xFF5B6B85)];

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  int _tab = 0;
  String _period = '7d';
  String? _source;
  Map? _sum;
  Map? _eval;
  String? _error;
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
    final q = {'period': _period, 'source': _source};
    try {
      final r = await Future.wait([api.get('/analytics/summary', q), api.get('/analytics/evaluation', q)]);
      if (!mounted) return;
      setState(() {
        _sum = r[0] as Map;
        _eval = r[1] as Map;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  String get _rangeLine {
    final p = _sum?['period'] as Map?;
    final me = AppScope.of(context).me!;
    final where = me.scope != null ? 'Kec. ${me.scope!.name}' : 'Wilayah saya';
    if (p == null) return where;
    final from = DateTime.parse(p['from'] as String), to = DateTime.parse(p['to'] as String);
    final range = from.month == to.month ? '${from.day}–${fmtShort(to)}' : '${fmtDayMonth(from)} – ${fmtShort(to)}';
    return '$where · $range';
  }

  Future<void> _pick<T>(String title, List<(T, String)> options, T current, ValueChanged<T> onPick) async {
    final v = await showModalBottomSheet<(T,)>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: context.ink)),
            const SizedBox(height: 8),
            for (final (k, l) in options)
              ListTile(
                title: Text(l, style: const TextStyle(fontWeight: FontWeight.w600)),
                trailing: k == current ? Icon(Icons.check_rounded, color: context.brand) : null,
                onTap: () => Navigator.pop(context, (k,)),
              ),
          ],
        ),
      ),
    );
    if (v != null) {
      onPick(v.$1);
      setState(() => _sum = null);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _sum, e = _eval;
    Widget body;
    if (_error != null && s == null) {
      body = ListView(children: [ErrorState(message: _error!, onRetry: _load)]);
    } else if (s == null || e == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: switch (_tab) {
          0 => _summary(s, e),
          1 => _ecosystem(s),
          2 => _timeArea(s),
          _ => _performance(s, e),
        },
      );
    }
    return Column(
      children: [
        NavyHeader(
          radius: 26,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Analitik', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Row(
                children: [
                  const Icon(Icons.shield_outlined, size: 14, color: PK.gold2),
                  const SizedBox(width: 6),
                  Expanded(child: Text(_rangeLine, style: const TextStyle(fontSize: 12.5, color: PK.headerMute))),
                ],
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final (i, t) in _tabs.indexed)
                      InkWell(
                        onTap: () => setState(() => _tab = i),
                        child: Container(
                          margin: const EdgeInsets.only(right: 18),
                          padding: const EdgeInsets.fromLTRB(0, 6, 0, 12),
                          decoration: BoxDecoration(
                            border: Border(bottom: BorderSide(color: _tab == i ? PK.gold : Colors.transparent, width: 3)),
                          ),
                          child: Text(
                            t,
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _tab == i ? Colors.white : const Color(0xFF8EA2CC)),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              _FilterBox(
                icon: Icons.calendar_today_outlined,
                label: _periods.firstWhere((p) => p.$1 == _period).$2,
                onTap: () => _pick('Periode', _periods, _period, (v) => _period = v),
              ),
              const SizedBox(width: 8),
              _FilterBox(
                icon: Icons.layers_outlined,
                label: _source == null ? 'Semua ekosistem' : _pillars.firstWhere((p) => p.$1 == _source).$2,
                onTap: () => _pick<String?>('Ekosistem', [(null, 'Semua ekosistem'), ..._pillars], _source, (v) => _source = v),
              ),
            ],
          ),
        ),
        Expanded(child: RefreshIndicator(onRefresh: _load, child: body)),
      ],
    );
  }

  // ---------------------------------------------------------------- Ringkasan

  List<Widget> _summary(Map s, Map e) {
    final t = s['totals'] as Map, p = s['previous_totals'] as Map;
    final total = t['total'] as int, prevTotal = p['total'] as int;
    final pct = total == 0 ? null : (t['selesai'] as int) * 100 / total;
    final prevPct = prevTotal == 0 ? null : (p['selesai'] as int) * 100 / prevTotal;
    final med = t['median_response_s'] as num?, prevMed = p['median_response_s'] as num?;
    final trend = (s['trend'] as List).cast<Map>();
    final cats = (s['by_category'] as List).cast<Map>();
    return [
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.55,
        children: [
          _Kpi(
            icon: Icons.description_outlined,
            tint: PK.navySoft,
            fg: PK.navy,
            label: 'Total laporan',
            value: fmtNumber(total),
            delta: prevTotal == 0 ? 'periode lalu: 0' : '${total >= prevTotal ? '▲' : '▼'} ${((total - prevTotal).abs() * 100 / prevTotal).round()}% dari periode lalu',
          ),
          _Kpi(
            icon: Icons.campaign_outlined,
            tint: const Color(0xFFFEE4E2),
            fg: PK.red,
            label: 'SOS darurat',
            value: fmtNumber(t['sos'] as int),
            delta: total == 0 ? '–' : '${((t['sos'] as int) * 100 / total).round()}% dari total',
          ),
          _Kpi(
            icon: Icons.schedule_rounded,
            tint: const Color(0xFFFEF3D6),
            fg: const Color(0xFFB98A0E),
            label: 'Respons median',
            value: minutes1(med),
            unit: med == null ? null : 'mnt',
            delta: med == null || prevMed == null
                ? 'belum ada pembanding'
                : med <= prevMed
                ? '▼ ${minutes1(prevMed - med)} mnt lebih cepat'
                : '▲ ${minutes1(med - prevMed)} mnt lebih lambat',
            good: med == null || prevMed == null ? null : med <= prevMed,
          ),
          _Kpi(
            icon: Icons.check_rounded,
            tint: const Color(0xFFD1FADF),
            fg: PK.greenDark,
            label: 'Selesai',
            value: pct == null ? '–' : '${pct.round()}%',
            delta: pct == null || prevPct == null ? 'belum ada pembanding' : '${pct >= prevPct ? '▲' : '▼'} ${(pct - prevPct).abs().round()} poin',
            good: pct == null || prevPct == null ? null : pct >= prevPct,
          ),
        ],
      ),
      Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PanelTitle('Laporan per Hari', hint: _busiestDay(trend)),
            const SizedBox(height: 6),
            const _Legend([(PK.red, 'SOS'), (PK.blueTrack, 'Pengaduan')]),
            const SizedBox(height: 8),
            _StackedBars(trend: trend),
          ],
        ),
      ),
      Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PanelTitle('Kategori Kejadian', hint: '${fmtNumber(total)} laporan'),
            const SizedBox(height: 12),
            if (cats.isEmpty) _empty() else _Donut(items: cats, total: total),
          ],
        ),
      ),
    ];
  }

  String? _busiestDay(List<Map> trend) {
    if (trend.isEmpty) return null;
    final best = trend.reduce((a, b) => (a['sos'] + a['laporan']) >= (b['sos'] + b['laporan']) ? a : b);
    if ((best['sos'] as int) + (best['laporan'] as int) == 0) return null;
    final d = DateTime.parse(best['day'] as String);
    return 'Teramai: ${trend.length <= 7 ? fmtWeekday(d) : fmtDayMonth(d)}';
  }

  Widget _empty() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 18),
    child: Center(child: Text('Belum ada data pada periode ini.', style: TextStyle(fontSize: 12.5, color: context.ink2))),
  );

  // ---------------------------------------------------------------- Ekosistem

  List<Widget> _ecosystem(Map s) {
    final eco = (s['by_ecosystem'] as List).cast<Map>();
    final matrix = (s['matrix'] as List).cast<Map>();
    final maxN = eco.isEmpty ? 1 : eco.map((e) => e['n'] as int).reduce(math.max);
    final colors = [PK.navy, PK.blueMid, PK.gold, PK.blueSoft, const Color(0xFF98A6C0)];
    // Kolom matriks: 4 kategori terbanyak di seluruh ekosistem.
    final catTotals = <String, int>{};
    for (final m in matrix) {
      catTotals[m['category'] as String] = (catTotals[m['category']] ?? 0) + (m['n'] as int);
    }
    final topCats = (catTotals.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(4).map((e) => e.key).toList();
    final sources = eco.map((e) => e['source'] as String?).toSet().toList();
    final maxCell = matrix.isEmpty ? 1 : matrix.map((m) => m['n'] as int).reduce(math.max);
    final sla = ((s['sla_min'] as Map?)?['sos'] as num?)?.toDouble() ?? 15;
    final meds = eco.where((e) => e['median_response_s'] != null).toList()
      ..sort((a, b) => (a['median_response_s'] as num).compareTo(b['median_response_s'] as num));
    final scaleMax = math.max(sla * 1.25, meds.isEmpty ? 0 : (meds.last['median_response_s'] as num) / 60);
    String cats(Map e) => (e['top_categories'] as List).map((c) => categoryLabel(c as String).toLowerCase()).join(' dan ');
    return [
      Panel(
        margin: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PanelTitle('Ekosistem Paling Sering Melapor'),
            if (eco.isEmpty) _empty(),
            for (final (i, e) in eco.indexed)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(color: colors[i % colors.length].withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                      child: Icon(ecosystemIcon(e['source'] as String?), size: 17, color: i < 3 ? colors[i] : PK.text2),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(text: e['label'] as String, style: const TextStyle(fontWeight: FontWeight.w800)),
                                if (e['app_name'] != e['label'])
                                  TextSpan(text: '  ${e['app_name']}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: context.ink2)),
                              ],
                            ),
                            style: TextStyle(fontSize: 12.5, color: context.ink),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 5),
                          Track(value: (e['n'] as int) / maxN, color: colors[i % colors.length]),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 42,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(fmtNumber(e['n'] as int), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: context.ink)),
                          Text('${e['pct']}%', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: context.ink2)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      if (eco.isNotEmpty && (eco.first['top_categories'] as List).isNotEmpty)
        InsightBox(
          lead: '${eco.first['label']} paling sering melapor,',
          text: [
            'terutama ${cats(eco.first)}.',
            if (eco.length > 1 && (eco[1]['top_categories'] as List).isNotEmpty) '${eco[1]['label']} paling banyak soal ${cats(eco[1])}.',
          ].join(' '),
        ),
      Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PanelTitle('Kategori per Ekosistem', hint: 'jumlah laporan'),
            const SizedBox(height: 10),
            if (topCats.isEmpty)
              _empty()
            else
              Table(
                columnWidths: const {0: FlexColumnWidth(1.5)},
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                children: [
                  TableRow(
                    children: [
                      const SizedBox(),
                      for (final c in topCats)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            _short(categoryLabel(c)),
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: context.ink2),
                          ),
                        ),
                    ],
                  ),
                  for (final src in sources)
                    TableRow(
                      children: [
                        Text(
                          src == null ? 'Lainnya' : eco.firstWhere((e) => e['source'] == src)['label'] as String,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: context.ink2),
                        ),
                        for (final c in topCats)
                          Builder(
                            builder: (context) {
                              final n = matrix.where((m) => m['source'] == src && m['category'] == c).fold<int>(0, (a, m) => a + (m['n'] as int));
                              final a = 0.06 + n / maxCell * 0.9;
                              return Container(
                                height: 32,
                                margin: const EdgeInsets.all(1.5),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(color: PK.navy.withValues(alpha: a), borderRadius: BorderRadius.circular(7)),
                                child: Text(
                                  '$n',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: a > 0.5 ? Colors.white : PK.navy),
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                ],
              ),
          ],
        ),
      ),
      Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PanelTitle('Waktu Respons per Ekosistem', hint: 'median'),
            if (meds.isEmpty) _empty(),
            for (final e in meds)
              Builder(
                builder: (context) {
                  final m = (e['median_response_s'] as num) / 60;
                  final over = m > sla;
                  return Padding(
                    padding: const EdgeInsets.only(top: 9),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 80,
                          child: Text(e['label'] as String, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: context.ink)),
                        ),
                        Expanded(
                          child: Track(value: m / scaleMax, color: over ? PK.red : PK.navy, height: 10, marker: sla / scaleMax),
                        ),
                        SizedBox(
                          width: 46,
                          child: Text(
                            '${minutes1(e['median_response_s'] as num)}m',
                            textAlign: TextAlign.right,
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: over ? context.dangerText : context.ink),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            if (meds.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'garis merah = target SOS ${sla.round()} menit',
                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: PK.red),
                  ),
                ),
              ),
          ],
        ),
      ),
    ];
  }

  String _short(String s) => s.length <= 8 ? s : s.split(' ').first;

  // ---------------------------------------------------------------- Waktu & Wilayah

  List<Widget> _timeArea(Map s) {
    final hours = (s['by_hour'] as List).cast<int>();
    final heat = (s['heatmap'] as List).cast<Map>();
    final kel = (s['by_kelurahan'] as List).cast<Map>().take(5).toList();
    final hint = s['patrol_hint'] as Map?;
    final maxKel = kel.isEmpty ? 1 : kel.map((k) => k['n'] as int).reduce(math.max);
    String hh(int h) => '${h.toString().padLeft(2, '0')}.00';
    return [
      Panel(
        margin: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PanelTitle('Jam Rawan', hint: 'laporan per jam'),
            const SizedBox(height: 8),
            _HourBars(hours: hours, from: hint?['from_hour'] as int?, to: hint?['to_hour'] as int?),
          ],
        ),
      ),
      Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PanelTitle('Hari × Jam', hint: 'kepadatan laporan'),
            const SizedBox(height: 10),
            _Heatmap(cells: heat),
          ],
        ),
      ),
      if (hint != null)
        InsightBox(
          lead: 'Saran patroli:',
          text: '${[
            '${hint['days']} pukul ${hh(hint['from_hour'] as int)}–${hh(hint['to_hour'] as int)}',
            if ((hint['kelurahan'] as List).isNotEmpty) 'di Kel. ${(hint['kelurahan'] as List).join(' dan ')}',
          ].join(' ')}.',
        ),
      Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PanelTitle('Wilayah (Kelurahan)', hint: 'vs periode lalu'),
            if (kel.isEmpty) _empty(),
            for (final k in kel)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 86,
                      child: Text(
                        k['name'] as String,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: context.ink),
                      ),
                    ),
                    Expanded(child: Track(value: (k['n'] as int) / maxKel, color: PK.gold)),
                    SizedBox(
                      width: 34,
                      child: Text(
                        '${k['n']}',
                        textAlign: TextAlign.right,
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: context.ink),
                      ),
                    ),
                    SizedBox(width: 46, child: _change(k['n'] as int, k['prev_n'] as int)),
                  ],
                ),
              ),
          ],
        ),
      ),
    ];
  }

  /// Naik = merah (lebih banyak kejadian), turun = hijau.
  Widget _change(int n, int prev) {
    if (prev == 0) {
      return Text(n == 0 ? '0%' : 'baru', textAlign: TextAlign.right, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: context.ink2));
    }
    final d = ((n - prev) * 100 / prev).round();
    final color = d > 0 ? context.dangerText : (d < 0 ? PK.greenDark : context.ink2);
    return Text(
      d == 0 ? '0%' : '${d > 0 ? '▲' : '▼'} ${d.abs()}%',
      textAlign: TextAlign.right,
      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: color),
    );
  }

  // ---------------------------------------------------------------- Kinerja

  List<Widget> _performance(Map s, Map e) {
    final pending = (e['pending'] as List).cast<Map>().map(Report.new).toList();
    final late = pending.where((r) => DateTime.now().difference(r.createdAt).inMinutes > 30).length;
    final f = s['funnel'] as Map;
    final masuk = f['masuk'] as int;
    final weekly = (s['weekly'] as List).cast<Map>();
    final officers = (s['officers'] as List).cast<Map>();
    final sla = ((s['sla_min'] as Map?)?['sos'] as num?)?.toDouble() ?? 15;
    final med = (s['totals'] as Map)['median_response_s'] as num?;
    double pct(String k) => masuk == 0 ? 0 : (f[k] as int) / masuk;
    return [
      if (e['detail'] == true)
        Panel(
          margin: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PanelTitle(
                'Menunggu Tindak Lanjut',
                trailing: late > 0
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(color: const Color(0xFFFEE4E2), borderRadius: BorderRadius.circular(20)),
                        child: Text('$late lewat 30 mnt', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: PK.redDark)),
                      )
                    : null,
              ),
              if (pending.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text('Semua laporan sudah ditanggapi.', style: TextStyle(fontSize: 12.5, color: context.ink2)),
                ),
              for (final (i, r) in pending.take(5).indexed)
                InkWell(
                  onTap: () => openIncident(context, r.id),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      border: i == math.min(pending.length, 5) - 1 ? null : Border(bottom: BorderSide(color: context.isDark ? context.hairline : const Color(0xFFF1F4F9))),
                    ),
                    child: Row(
                      children: [
                        KindTag(sos: r.isSos, short: true),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r.headline, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.ink)),
                              Text(
                                [r.ecosystemLabel, if (r.kelurahan != null) 'Kel. ${r.kelurahan!.name}'].join(' · '),
                                style: TextStyle(fontSize: 11, color: context.ink2),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          _age(r.createdAt),
                          style: TextStyle(fontFamily: 'monospace', fontSize: 12.5, fontWeight: FontWeight.w700, color: context.dangerText),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      Panel(
        margin: e['detail'] == true ? const EdgeInsets.only(top: 10) : EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PanelTitle('Alur Tindak Lanjut', hint: '${fmtNumber(masuk)} laporan'),
            _FunnelRow('Masuk', f['masuk'] as int, 1, PK.blueTrack, showPct: false),
            _FunnelRow('Diterima', f['diterima'] as int, pct('diterima'), PK.blueSoft),
            if ((f['tidak_valid'] as int) > 0)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text('${f['tidak_valid']} laporan dinyatakan tidak valid (palsu atau ganda)', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: PK.redDark)),
              ),
            _FunnelRow('Ditangani', f['ditangani'] as int, pct('ditangani'), PK.blueMid),
            _FunnelRow('Selesai', f['selesai'] as int, pct('selesai'), PK.navy),
          ],
        ),
      ),
      Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Tren Waktu Respons', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: context.ink)),
                      Text('median per minggu, 8 minggu', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: context.ink2)),
                    ],
                  ),
                ),
                if (med != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: med / 60 <= sla ? const Color(0xFFD1FADF) : const Color(0xFFFEE4E2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${minutes1(med)} mnt',
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: med / 60 <= sla ? PK.greenDark : PK.redDark),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (weekly.where((w) => w['median_response_s'] != null).length < 2) _empty() else _LineChart(weekly: weekly, target: sla),
          ],
        ),
      ),
      Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PanelTitle('Per Petugas', hint: 'selesai · respons'),
            if (officers.isEmpty) _empty(),
            for (final (i, o) in officers.take(5).indexed)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  border: i == math.min(officers.length, 5) - 1 ? null : Border(bottom: BorderSide(color: context.isDark ? context.hairline : const Color(0xFFF1F4F9))),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E3F8F),
                        shape: BoxShape.circle,
                        border: o['is_me'] == true ? Border.all(color: PK.gold, width: 2) : null,
                      ),
                      child: Text(
                        _initials(officerName(o['officer'] as String?)),
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${officerName(o['officer'] as String?)}${o['is_me'] == true ? ' (Anda)' : ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.ink),
                          ),
                          Text('${o['ditangani']} ditangani', style: TextStyle(fontSize: 11, color: context.ink2)),
                        ],
                      ),
                    ),
                    Text(
                      '${o['selesai']} · ${minutes1(o['median_response_s'] as num?)}m',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: context.ink),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ];
  }

  String _age(DateTime d) {
    final m = DateTime.now().difference(d).inMinutes;
    if (m < 60) return '${m}m';
    if (m < 1440) return '${m ~/ 60}j';
    return '${m ~/ 1440}h';
  }

  String _initials(String name) {
    final w = name.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (w.isEmpty) return '?';
    return (w.length == 1 ? w.first[0] : w[w.length - 2][0] + w.last[0]).toUpperCase();
  }
}

// ------------------------------------------------------------------ komponen

class _FilterBox extends StatelessWidget {
  const _FilterBox({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Material(
      color: context.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: context.hairline)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          height: 38,
          child: Row(
            children: [
              const SizedBox(width: 10),
              Icon(icon, size: 15, color: context.brand),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.ink),
                ),
              ),
              const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Color(0xFF94A3B8)),
              const SizedBox(width: 6),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Kpi extends StatelessWidget {
  const _Kpi({
    required this.icon,
    required this.tint,
    required this.fg,
    required this.label,
    required this.value,
    required this.delta,
    this.unit,
    this.good,
  });
  final IconData icon;
  final Color tint, fg;
  final String label, value, delta;
  final String? unit;
  final bool? good;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(color: context.surface, borderRadius: BorderRadius.circular(16)),
    child: Stack(
      children: [
        Positioned(
          top: 0,
          right: 0,
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(9)),
            child: Icon(icon, size: 16, color: fg),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: context.ink2)),
            const SizedBox(height: 4),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: value),
                  if (unit != null) TextSpan(text: ' $unit', style: TextStyle(fontSize: 13, color: context.ink2)),
                ],
              ),
              style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800, color: context.ink, fontFeatures: const [FontFeature.tabularFigures()]),
            ),
            const SizedBox(height: 3),
            Text(
              delta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: good == null
                    ? context.ink2
                    : good!
                    ? PK.greenDark
                    : context.dangerText,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _Legend extends StatelessWidget {
  const _Legend(this.items);
  final List<(Color, String)> items;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final (c, l) in items) ...[
        Container(width: 9, height: 9, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 5),
        Text(l, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: context.ink2)),
        const SizedBox(width: 12),
      ],
    ],
  );
}

/// Batang bertumpuk per hari (SOS merah di atas, pengaduan biru muda; batang teramai navy). 90 hari → per minggu.
class _StackedBars extends StatelessWidget {
  const _StackedBars({required this.trend});
  final List<Map> trend;
  @override
  Widget build(BuildContext context) {
    var rows = trend.map((t) => (day: DateTime.parse(t['day'] as String), sos: t['sos'] as int, lap: t['laporan'] as int)).toList();
    if (rows.length > 31) {
      final weeks = <({DateTime day, int sos, int lap})>[];
      for (var i = 0; i < rows.length; i += 7) {
        final w = rows.sublist(i, math.min(i + 7, rows.length));
        weeks.add((day: w.first.day, sos: w.fold(0, (a, x) => a + x.sos), lap: w.fold(0, (a, x) => a + x.lap)));
      }
      rows = weeks;
    }
    final maxV = rows.isEmpty ? 1 : math.max(1, rows.map((r) => r.sos + r.lap).reduce(math.max));
    final busiest = rows.isEmpty ? -1 : rows.indexWhere((r) => r.sos + r.lap == maxV);
    final few = rows.length <= 7;
    return SizedBox(
      height: 150,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final (i, r) in rows.indexed)
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: few ? 5 : 1),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (few)
                      Text(
                        '${r.sos + r.lap}',
                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: i == busiest ? context.brand : context.ink2),
                      ),
                    const SizedBox(height: 4),
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: math.max(0.02, (r.sos + r.lap) / maxV),
                          child: ClipRRect(
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(7), bottom: Radius.circular(3)),
                            child: Column(
                              children: [
                                if (r.sos > 0) Expanded(flex: r.sos, child: Container(color: PK.red)),
                                Expanded(
                                  flex: math.max(r.lap, r.sos == 0 ? 1 : 0),
                                  child: Container(color: i == busiest ? PK.navy : PK.blueTrack),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      few
                          ? fmtWeekdayShort(r.day)
                          : (i % (rows.length > 14 ? 5 : 2) == 0 ? '${r.day.day}' : ''),
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: i == busiest ? context.brand : context.ink2),
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

class _Donut extends StatelessWidget {
  const _Donut({required this.items, required this.total});
  final List<Map> items;
  final int total;
  @override
  Widget build(BuildContext context) {
    final sum = items.fold<int>(0, (a, m) => a + (m['n'] as int));
    final segs = <(Color, double, String, int)>[];
    var ci = 0;
    for (final m in items) {
      final cat = m['name'] as String? ?? 'lainnya';
      final color = const {'darurat', 'general'}.contains(cat) ? PK.red : _catColors[ci++ % _catColors.length];
      segs.add((color, (m['n'] as int) / (sum == 0 ? 1 : sum), categoryLabel(cat), m['n'] as int));
    }
    final rest = total - sum;
    if (rest > 0) segs.add((const Color(0xFFD3DAE6), rest / total, 'Lainnya', rest));
    return Row(
      children: [
        SizedBox(
          width: 116,
          height: 116,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(size: const Size.square(116), painter: _DonutPainter(segs.map((s) => (s.$1, s.$2)).toList(), context.isDark ? context.hairline : const Color(0xFFEEF2F8))),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(fmtNumber(total), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: context.ink)),
                  Text('laporan', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: context.ink2)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            children: [
              for (final (c, _, l, n) in segs)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Container(width: 9, height: 9, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(l, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: context.ink)),
                      ),
                      Text('$n', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: context.ink)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.segs, this.track);
  final List<(Color, double)> segs;
  final Color track;
  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 16.0;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: size.width / 2 - stroke / 2);
    canvas.drawArc(rect, 0, math.pi * 2, false, Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke);
    var start = -math.pi / 2;
    for (final (c, f) in segs) {
      final sweep = f * math.pi * 2;
      canvas.drawArc(rect, start, sweep, false, Paint()
        ..color = c
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter o) => true;
}

/// 24 batang per jam: jendela saran patroli navy, jam tertinggi merah + label.
class _HourBars extends StatelessWidget {
  const _HourBars({required this.hours, this.from, this.to});
  final List<int> hours;
  final int? from, to;
  @override
  Widget build(BuildContext context) {
    final maxV = math.max(1, hours.reduce(math.max));
    final peak = hours.indexOf(maxV);
    return Column(
      children: [
        SizedBox(
          height: 18,
          child: LayoutBuilder(
            builder: (_, c) => Stack(
              children: [
                if (hours.any((h) => h > 0))
                  Positioned(
                    left: ((peak + 0.5) / 24 * c.maxWidth - 40).clamp(0, c.maxWidth - 80),
                    width: 80,
                    child: Text(
                      '${peak.toString().padLeft(2, '0')}.00 · $maxV',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: PK.red),
                    ),
                  ),
              ],
            ),
          ),
        ),
        SizedBox(
          height: 120,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final (h, v) in hours.indexed)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1.5),
                    child: FractionallySizedBox(
                      heightFactor: math.max(0.02, v / maxV),
                      child: Container(
                        decoration: BoxDecoration(
                          color: h == peak && v > 0
                              ? PK.red
                              : (from != null && h >= from! && h < to!)
                              ? PK.navy
                              : PK.blueTrack,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(3), bottom: Radius.circular(1)),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 5),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final l in const ['00', '06', '12', '18', '23']) Text(l, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8))),
          ],
        ),
      ],
    );
  }
}

/// Hari (Sen–Min) × blok 3 jam, warna navy sebanding jumlah.
class _Heatmap extends StatelessWidget {
  const _Heatmap({required this.cells});
  final List<Map> cells;
  @override
  Widget build(BuildContext context) {
    final grid = List.generate(7, (_) => List.filled(8, 0));
    for (final c in cells) {
      grid[(c['dow'] as int) - 1][(c['hour'] as int) ~/ 3] += c['n'] as int;
    }
    final maxV = math.max(1, grid.expand((r) => r).reduce(math.max));
    const days = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
    final label = TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: context.ink2);
    return Column(
      children: [
        Row(
          children: [
            const SizedBox(width: 30),
            for (final h in const ['00', '03', '06', '09', '12', '15', '18', '21'])
              Expanded(child: Text(h, textAlign: TextAlign.center, style: label.copyWith(fontSize: 9.5))),
          ],
        ),
        const SizedBox(height: 3),
        for (final (d, row) in grid.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(
              children: [
                SizedBox(width: 30, child: Text(days[d], style: label)),
                for (final v in row)
                  Expanded(
                    child: Container(
                      height: 22,
                      margin: const EdgeInsets.symmetric(horizontal: 1.5),
                      decoration: BoxDecoration(color: PK.navy.withValues(alpha: 0.06 + v / maxV * 0.9), borderRadius: BorderRadius.circular(5)),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('Sepi', style: label),
            for (final a in const [0.08, 0.3, 0.6, 0.95])
              Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.only(left: 4),
                decoration: BoxDecoration(color: PK.navy.withValues(alpha: a), borderRadius: BorderRadius.circular(3)),
              ),
            const SizedBox(width: 4),
            Text('Ramai', style: label),
          ],
        ),
      ],
    );
  }
}

class _FunnelRow extends StatelessWidget {
  const _FunnelRow(this.label, this.n, this.frac, this.color, {this.showPct = true});
  final String label;
  final int n;
  final double frac;
  final Color color;
  final bool showPct;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Column(
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: context.ink))),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: fmtNumber(n)),
                  if (showPct) TextSpan(text: '  ${(frac * 100).round()}%', style: TextStyle(fontWeight: FontWeight.w600, color: context.ink2)),
                ],
              ),
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: context.ink),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Track(value: frac, color: color, height: 12),
      ],
    ),
  );
}

/// Garis median respons per minggu (menit) + garis target merah putus-putus.
class _LineChart extends StatelessWidget {
  const _LineChart({required this.weekly, required this.target});
  final List<Map> weekly;
  final double target;
  @override
  Widget build(BuildContext context) {
    final pts = weekly.map((w) => (w['median_response_s'] as num?)?.toDouble()).toList();
    return Column(
      children: [
        SizedBox(height: 120, child: CustomPaint(size: Size.infinite, painter: _LinePainter(pts, target, context.isDark ? context.hairline : const Color(0xFFEEF2F7)))),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final w in weekly)
              Text(
                fmtDayMonth(DateTime.parse(w['week'] as String)).split(' ').first,
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8)),
              ),
          ],
        ),
      ],
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.pts, this.target, this.grid);
  final List<double?> pts;
  final double target;
  final Color grid;
  @override
  void paint(Canvas canvas, Size size) {
    final vals = pts.whereType<double>().map((s) => s / 60).toList();
    final maxV = math.max(target * 1.5, vals.isEmpty ? 1 : vals.reduce(math.max) * 1.15);
    double y(double v) => size.height - 8 - (v / maxV) * (size.height - 16);
    double x(int i) => pts.length == 1 ? size.width / 2 : 10 + i * (size.width - 20) / (pts.length - 1);
    final g = Paint()..color = grid;
    for (final f in const [0.15, 0.5, 0.85]) {
      canvas.drawLine(Offset(0, size.height * f), Offset(size.width, size.height * f), g);
    }
    final ty = y(target);
    final dash = Paint()
      ..color = PK.red
      ..strokeWidth = 1.5;
    for (double dx = 10; dx < size.width - 10; dx += 10) {
      canvas.drawLine(Offset(dx, ty), Offset(math.min(dx + 5, size.width - 10), ty), dash);
    }
    final tp = TextPainter(
      text: TextSpan(text: 'target ${target.round()} mnt', style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: PK.red)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(size.width - 10 - tp.width, ty - tp.height - 2));

    final line = Path(), area = Path();
    Offset? last;
    var started = false;
    for (final (i, p) in pts.indexed) {
      if (p == null) continue;
      final o = Offset(x(i), y(p / 60));
      if (!started) {
        line.moveTo(o.dx, o.dy);
        area.moveTo(o.dx, size.height);
        area.lineTo(o.dx, o.dy);
        started = true;
      } else {
        line.lineTo(o.dx, o.dy);
        area.lineTo(o.dx, o.dy);
      }
      last = o;
    }
    if (last == null) return;
    area
      ..lineTo(last.dx, size.height)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x2E0B2A6F), Color(0x000B2A6F)])
            .createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = PK.navy
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(last, 5, Paint()..color = Colors.white);
    canvas.drawCircle(
      last,
      5,
      Paint()
        ..color = PK.gold
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_LinePainter o) => true;
}
