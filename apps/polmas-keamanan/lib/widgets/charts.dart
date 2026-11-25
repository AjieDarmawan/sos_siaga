import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/models.dart';
import '../theme/tokens.dart';

/// Warna grafik mengikuti mockup Polmas Keamanan: keluarga merah merek.
/// - satu seri (tren total, per kelurahan, per jam) = merah merek;
/// - kategori (donut) = 5 tingkat merah berbeda terang-gelap + "Lainnya" abu. Hue sama tidak cukup untuk membedakan
///   identitas, jadi donut SELALU memakai legenda berlabel nama + angka + persen di sebelahnya (bukan warna saja);
/// - magnitudo (peta panas) = satu hue merah, terang → gelap, dengan legenda Sedikit–Banyak dan teks jam rawan.
/// Seri SOS vs Laporan (bila dua seri) tetap merah vs biru slot-1 (lolos validator CVD dataviz).
abstract final class ChartColors {
  static Color sos(BuildContext c) => c.isDark ? PK.redSoft : PK.red;
  static Color laporan(BuildContext c) => c.isDark ? const Color(0xFF3987E5) : const Color(0xFF2A78D6);
  static Color single(BuildContext c) => sos(c);
  static List<Color> categorical(BuildContext c) => c.isDark
      ? const [Color(0xFFE5484D), Color(0xFFF08A8E), Color(0xFFB3262D), Color(0xFFF7BEC0), Color(0xFF7A1A1F)]
      : const [Color(0xFFD71920), Color(0xFFEF6B6F), Color(0xFF8A0F14), Color(0xFFF6A2A5), Color(0xFFB3141A)];
  static Color other(BuildContext c) => c.isDark ? const Color(0xFF64748B) : const Color(0xFFCBD2DC);
  static const _rampLight = [
    Color(0xFFFDE8E9),
    Color(0xFFF9C5C7),
    Color(0xFFF29A9E),
    Color(0xFFE8656A),
    Color(0xFFD71920),
    Color(0xFFB3141A),
    Color(0xFF8A0F14),
  ];
  static const _rampDark = [
    Color(0xFF3A1418),
    Color(0xFF5C1A1F),
    Color(0xFF8A1F26),
    Color(0xFFB3262D),
    Color(0xFFD93B41),
    Color(0xFFEC6A6F),
    Color(0xFFF5A3A6),
  ];
  static Color ramp(BuildContext c, double t) {
    final r = c.isDark ? _rampDark : _rampLight;
    return r[(t.clamp(0, 1) * (r.length - 1)).round()];
  }

  static Color grid(BuildContext c) => c.hairline;
  static Color tooltipBg(BuildContext c) => c.isDark ? const Color(0xFFF1F5F9) : PK.text;
  static Color tooltipInk(BuildContext c) => c.isDark ? PK.text : Colors.white;
}

TextStyle _axis(BuildContext c) => TextStyle(fontSize: 12, color: c.ink2, fontWeight: FontWeight.w500);

/// Legenda kecil: titik warna + teks (teks memakai warna tinta, bukan warna seri).
class Legend extends StatelessWidget {
  const Legend({super.key, required this.items});
  final List<(Color, String)> items;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 16,
    runSpacing: 6,
    children: [
      for (final (c, l) in items)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3)),
            ),
            const SizedBox(width: 6),
            Text(l, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.ink)),
          ],
        ),
    ],
  );
}

/// Tren harian SOS vs Laporan: dua garis 2 px, satu sumbu, sentuh untuk melihat nilai (crosshair + tooltip).
class TrendChart extends StatelessWidget {
  const TrendChart({super.key, required this.days, this.total = true});
  final List<Map> days; // {day, sos, laporan}

  /// true = satu garis merah total (SOS + laporan), seperti mockup; false = dua seri SOS vs Laporan.
  final bool total;
  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) return const SizedBox(height: 200);
    final sos = ChartColors.sos(context), lap = ChartColors.laporan(context);
    if (total) return _total(context);
    final maxY = days.fold<num>(0, (m, d) => math.max(m, math.max(d['sos'] as num, d['laporan'] as num))).toDouble();
    final step = (days.length / 5).ceil().clamp(1, 1000);
    final fmt = DateFormat('d/M');
    LineChartBarData line(String key, Color color) => LineChartBarData(
      spots: [for (final (i, d) in days.indexed) FlSpot(i.toDouble(), (d[key] as num).toDouble())],
      color: color,
      barWidth: 2,
      isCurved: true,
      preventCurveOverShooting: true,
      dotData: FlDotData(
        show: days.length <= 14,
        getDotPainter: (_, _, _, _) => FlDotCirclePainter(radius: 4, color: color, strokeWidth: 2, strokeColor: context.surface),
      ),
      belowBarData: BarAreaData(show: true, color: color.withValues(alpha: 0.08)),
    );
    return Semantics(
      label:
          'Grafik tren harian: total SOS ${days.fold<num>(0, (s, d) => s + (d['sos'] as num))}, total laporan ${days.fold<num>(0, (s, d) => s + (d['laporan'] as num))}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Legend(items: [(sos, 'SOS'), (lap, 'Laporan')]),
          const SizedBox(height: 12),
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: maxY < 4 ? 4 : maxY * 1.15,
                lineBarsData: [line('laporan', lap), line('sos', sos)],
                gridData: FlGridData(drawVerticalLine: false, getDrawingHorizontalLine: (_) => FlLine(color: ChartColors.grid(context), strokeWidth: 1)),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (v, meta) => v == meta.max || v % 1 != 0
                          ? const SizedBox.shrink()
                          : SideTitleWidget(
                              meta: meta,
                              child: Text(v.toInt().toString(), style: _axis(context)),
                            ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 26,
                      interval: 1,
                      getTitlesWidget: (v, meta) {
                        final i = v.toInt();
                        if (i < 0 || i >= days.length || i % step != 0) return const SizedBox.shrink();
                        return SideTitleWidget(
                          meta: meta,
                          child: Text(fmt.format(DateTime.parse(days[i]['day'] as String)), style: _axis(context)),
                        );
                      },
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  getTouchedSpotIndicator: (_, idx) =>
                      idx.map((_) => TouchedSpotIndicatorData(FlLine(color: context.ink2, strokeWidth: 1, dashArray: [4, 4]), FlDotData(show: true))).toList(),
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => ChartColors.tooltipBg(context),
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    getTooltipItems: (spots) => spots.map((s) {
                      final d = days[s.x.toInt()];
                      final isSos = s.bar.color == sos;
                      final head = s == spots.first ? '${DateFormat('EEE, d MMM', 'id').format(DateTime.parse(d['day'] as String))}\n' : '';
                      return LineTooltipItem(
                        '$head${isSos ? 'SOS' : 'Laporan'}: ${s.y.toInt()}',
                        TextStyle(color: ChartColors.tooltipInk(context), fontSize: 13, fontWeight: FontWeight.w600),
                      );
                    }).toList(),
                  ),
                ),
              ),
              duration: context.reduceMotion ? Duration.zero : const Duration(milliseconds: 600),
            ),
          ),
        ],
      ),
    );
  }

  /// Satu garis merah total per hari dengan titik & area merah muda, sumbu tanggal di bawah.
  Widget _total(BuildContext context) {
    final c = ChartColors.single(context);
    final vals = [for (final d in days) (d['sos'] as num) + (d['laporan'] as num)];
    final maxY = vals.fold<num>(0, math.max).toDouble();
    final step = (days.length / 5).ceil().clamp(1, 1000);
    final fmt = DateFormat('d MMM', 'id');
    return Semantics(
      label: 'Grafik tren laporan harian, total ${vals.fold<num>(0, (s, v) => s + v)} kejadian, tertinggi $maxY per hari',
      child: SizedBox(
        height: 190,
        child: LineChart(
          LineChartData(
            minY: 0,
            maxY: maxY < 4 ? 4 : (maxY * 1.2).ceilToDouble(),
            lineBarsData: [
              LineChartBarData(
                spots: [for (final (i, v) in vals.indexed) FlSpot(i.toDouble(), v.toDouble())],
                color: c,
                barWidth: 2,
                isCurved: false,
                dotData: FlDotData(
                  show: days.length <= 31,
                  checkToShowDot: (s, _) => days.length <= 14 || s.x.toInt() % 3 == 0,
                  getDotPainter: (_, _, _, _) => FlDotCirclePainter(radius: 4, color: c, strokeWidth: 2, strokeColor: context.surface),
                ),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [c.withValues(alpha: 0.25), c.withValues(alpha: 0.02)],
                  ),
                ),
              ),
            ],
            gridData: FlGridData(drawVerticalLine: false, getDrawingHorizontalLine: (_) => FlLine(color: ChartColors.grid(context), strokeWidth: 1)),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  getTitlesWidget: (v, meta) => v % 1 != 0
                      ? const SizedBox.shrink()
                      : SideTitleWidget(
                          meta: meta,
                          child: Text(v.toInt().toString(), style: _axis(context)),
                        ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 26,
                  interval: 1,
                  getTitlesWidget: (v, meta) {
                    final i = v.toInt();
                    if (i < 0 || i >= days.length || i % step != 0) return const SizedBox.shrink();
                    return SideTitleWidget(
                      meta: meta,
                      child: Text(fmt.format(DateTime.parse(days[i]['day'] as String)), style: _axis(context)),
                    );
                  },
                ),
              ),
            ),
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => ChartColors.tooltipBg(context),
                fitInsideHorizontally: true,
                fitInsideVertically: true,
                getTooltipItems: (spots) => spots.map((s) {
                  final d = days[s.x.toInt()];
                  return LineTooltipItem(
                    '${DateFormat('EEE, d MMM', 'id').format(DateTime.parse(d['day'] as String))}\n${s.y.toInt()} kejadian (SOS ${d['sos']})',
                    TextStyle(color: ChartColors.tooltipInk(context), fontSize: 13, fontWeight: FontWeight.w600),
                  );
                }).toList(),
              ),
            ),
          ),
          duration: context.reduceMotion ? Duration.zero : const Duration(milliseconds: 600),
        ),
      ),
    );
  }
}

/// Batang vertikal satu seri (mis. per jam). Batang 4 px membulat di ujung, sentuh untuk nilai.
class ColumnChart extends StatelessWidget {
  const ColumnChart({super.key, required this.values, required this.labelFor, required this.tooltipFor, this.highlightTop = false, this.height = 180});
  final List<num> values;
  final String? Function(int i) labelFor;
  final String Function(int i) tooltipFor;
  final bool highlightTop;
  final double height;
  @override
  Widget build(BuildContext context) {
    final c = ChartColors.single(context);
    final maxV = values.fold<num>(0, math.max).toDouble();
    final peak = maxV == 0 ? -1 : values.indexOf(maxV);
    return SizedBox(
      height: height,
      child: BarChart(
        BarChartData(
          maxY: maxV < 4 ? 4 : maxV * 1.15,
          alignment: BarChartAlignment.spaceBetween,
          barGroups: [
            for (final (i, v) in values.indexed)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: v.toDouble(),
                    width: values.length > 12 ? 7 : 16,
                    color: highlightTop && i == peak ? c.withValues(alpha: 1) : (highlightTop ? c.withValues(alpha: 0.55) : c),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                  ),
                ],
              ),
          ],
          gridData: FlGridData(drawVerticalLine: false, getDrawingHorizontalLine: (_) => FlLine(color: ChartColors.grid(context), strokeWidth: 1)),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (v, meta) => v == meta.max || v % 1 != 0
                    ? const SizedBox.shrink()
                    : SideTitleWidget(
                        meta: meta,
                        child: Text(v.toInt().toString(), style: _axis(context)),
                      ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                getTitlesWidget: (v, meta) {
                  final l = labelFor(v.toInt());
                  return l == null
                      ? const SizedBox.shrink()
                      : SideTitleWidget(
                          meta: meta,
                          child: Text(l, style: _axis(context)),
                        );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => ChartColors.tooltipBg(context),
              fitInsideHorizontally: true,
              getTooltipItem: (g, _, _, _) =>
                  BarTooltipItem(tooltipFor(g.x), TextStyle(color: ChartColors.tooltipInk(context), fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ),
        ),
        duration: context.reduceMotion ? Duration.zero : const Duration(milliseconds: 600),
      ),
    );
  }
}

/// Batang horizontal berlabel (per kelurahan): nama di kiri, nilai di kanan, panjang = jumlah. Lebih terbaca di HP.
class RankBars extends StatelessWidget {
  const RankBars({super.key, required this.items, this.onTap, this.nameWidth = 110});
  final List<(String, num)> items;

  /// Lebar kolom nama (lebih sempit saat setengah layar).
  final double nameWidth;
  final void Function(int i)? onTap;
  @override
  Widget build(BuildContext context) {
    final maxV = items.fold<num>(0, (m, e) => math.max(m, e.$2)).toDouble();
    final c = ChartColors.single(context);
    return Column(
      children: [
        for (final (i, (name, v)) in items.indexed)
          Semantics(
            label: '$name: $v',
            excludeSemantics: true,
            child: InkWell(
              onTap: onTap == null ? null : () => onTap!(i),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: nameWidth,
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.ink),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (_, cs) => TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: maxV == 0 ? 0 : v / maxV),
                          duration: context.reduceMotion ? Duration.zero : const Duration(milliseconds: 600),
                          curve: Curves.easeOut,
                          builder: (_, f, _) => Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              height: 14,
                              width: math.max(4, cs.maxWidth * f),
                              decoration: BoxDecoration(
                                color: c,
                                borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 28,
                      child: Text(
                        '$v',
                        textAlign: TextAlign.right,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.ink, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Donat jenis kejadian: maks. 5 kategori + "Lainnya", jarak 2 px antarsegmen, legenda berangka + persen.
class CategoryDonut extends StatefulWidget {
  const CategoryDonut({super.key, required this.items, this.vertical = false});
  final List<Map> items; // {name, n}

  /// Donat di atas, legenda di bawah (untuk kolom setengah layar).
  final bool vertical;
  @override
  State<CategoryDonut> createState() => _CategoryDonutState();
}

class _CategoryDonutState extends State<CategoryDonut> {
  int _touched = -1;
  @override
  Widget build(BuildContext context) {
    final sorted = [...widget.items]..sort((a, b) => (b['n'] as num).compareTo(a['n'] as num));
    final top = sorted.take(5).map((e) => (categoryLabel(e['name'] as String), (e['n'] as num).toInt())).toList();
    final rest = sorted.skip(5).fold<int>(0, (s, e) => s + (e['n'] as num).toInt());
    if (rest > 0) top.add(('Lainnya', rest));
    final total = top.fold<int>(0, (s, e) => s + e.$2);
    final colors = ChartColors.categorical(context);
    Color colorAt(int i) => i < 5 ? colors[i] : ChartColors.other(context);
    if (total == 0) return const SizedBox(height: 120, child: Center(child: Text('Belum ada data')));
    final v = widget.vertical;
    final d = v ? 112.0 : 140.0;
    final donut = SizedBox(
      width: d,
      height: d,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: v ? 32 : 42,
              startDegreeOffset: -90,
              pieTouchData: PieTouchData(
                touchCallback: (e, r) {
                  if (!e.isInterestedForInteractions || r?.touchedSection == null) return setState(() => _touched = -1);
                  setState(() => _touched = r!.touchedSection!.touchedSectionIndex);
                },
              ),
              sections: [
                for (final (i, (_, n)) in top.indexed)
                  PieChartSectionData(value: n.toDouble(), color: colorAt(i), radius: (i == _touched ? 26 : 22) * (v ? 0.8 : 1), showTitle: false),
              ],
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_touched >= 0 && _touched < top.length ? '${top[_touched].$2}' : '$total', style: Theme.of(context).textTheme.titleLarge),
              Text(
                _touched >= 0 && _touched < top.length ? '${(top[_touched].$2 * 100 / total).round()}%' : 'total',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
    final legend = Column(
      children: [
        for (final (i, (name, n)) in top.indexed)
          Padding(
            padding: EdgeInsets.symmetric(vertical: v ? 2 : 4),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: colorAt(i), borderRadius: BorderRadius.circular(3)),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: (v ? Theme.of(context).textTheme.bodySmall : Theme.of(context).textTheme.bodyMedium)?.copyWith(color: context.ink),
                  ),
                ),
                Text(
                  v ? '${(n * 100 / total).round()}%' : '$n · ${(n * 100 / total).round()}%',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.ink, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
      ],
    );
    if (v) return Column(children: [donut, const SizedBox(height: 10), legend]);
    return Row(
      children: [
        donut,
        const SizedBox(width: 16),
        Expanded(child: legend),
      ],
    );
  }
}

/// Peta panas jam × hari (jam rawan): sel 24 × 7, satu hue biru terang → gelap, sentuh sel untuk nilai.
class HourHeatmap extends StatefulWidget {
  const HourHeatmap({super.key, required this.cells});
  final List<Map> cells; // {dow 1..7, hour 0..23, n}
  @override
  State<HourHeatmap> createState() => _HourHeatmapState();
}

class _HourHeatmapState extends State<HourHeatmap> {
  (int, int)? _sel;
  static const _days = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];

  @override
  Widget build(BuildContext context) {
    final grid = List.generate(7, (_) => List.filled(24, 0));
    for (final c in widget.cells) {
      grid[(c['dow'] as num).toInt() - 1][(c['hour'] as num).toInt()] = (c['n'] as num).toInt();
    }
    final maxV = grid.expand((r) => r).fold<int>(0, math.max);
    final t = Theme.of(context).textTheme;
    final sel = _sel;
    var peak = (0, 0);
    for (var d = 0; d < 7; d++) {
      for (var h = 0; h < 24; h++) {
        if (grid[d][h] > grid[peak.$1][peak.$2]) peak = (d, h);
      }
    }
    return Semantics(
      label: maxV == 0
          ? 'Peta panas jam rawan: belum ada data'
          : 'Peta panas jam rawan. Paling rawan ${_days[peak.$1]} pukul ${peak.$2}.00 dengan ${grid[peak.$1][peak.$2]} kejadian',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, cs) {
              final cell = (cs.maxWidth - 32) / 24;
              return Column(
                children: [
                  for (var d = 0; d < 7; d++)
                    Row(
                      children: [
                        SizedBox(width: 32, child: Text(_days[d], style: _axis(context))),
                        for (var h = 0; h < 24; h++)
                          GestureDetector(
                            onTap: () => setState(() => _sel = (d, h)),
                            child: Container(
                              width: cell,
                              height: cell.clamp(10, 18),
                              margin: EdgeInsets.zero,
                              decoration: BoxDecoration(
                                color: grid[d][h] == 0 ? context.pageBg : ChartColors.ramp(context, grid[d][h] / math.max(1, maxV)),
                                border: Border.all(color: sel == (d, h) ? context.ink : context.surface, width: sel == (d, h) ? 1.5 : 1),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                      ],
                    ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const SizedBox(width: 32),
                      for (final h in [0, 6, 12, 18])
                        SizedBox(
                          width: cell * 6,
                          child: Text('${h.toString().padLeft(2, '0')}.00', style: _axis(context)),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text('Sedikit', style: t.bodySmall),
              const SizedBox(width: 6),
              for (var i = 0; i <= 6; i++) Container(width: 16, height: 10, color: ChartColors.ramp(context, i / 6)),
              const SizedBox(width: 6),
              Text('Banyak', style: t.bodySmall),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            sel != null
                ? '${_days[sel.$1]}, ${sel.$2.toString().padLeft(2, '0')}.00–${sel.$2.toString().padLeft(2, '0')}.59: ${grid[sel.$1][sel.$2]} kejadian'
                : maxV == 0
                ? 'Belum ada data pada periode ini.'
                : 'Paling rawan: ${_days[peak.$1]} pukul ${peak.$2.toString().padLeft(2, '0')}.00 (${grid[peak.$1][peak.$2]} kejadian). Ketuk sel untuk detail.',
            style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
