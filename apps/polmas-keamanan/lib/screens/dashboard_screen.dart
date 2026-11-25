import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../core/api.dart';
import '../core/app_state.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../theme/tokens.dart';
import '../widgets/brand.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import '../widgets/incident_map.dart';
import '../widgets/report_list.dart';
import 'home_shell.dart';
import 'news_screen.dart';
import 'video_screen.dart';

/// Beranda / Dashboard Analitik (FR-08): header navy (sapaan, nama, wilayah, lonceng), empat kartu angka, lalu tab
/// Berita, Laporan, Video, Lokasi, Waktu yang bisa digeser.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.onOpenTab});
  final ValueChanged<int> onOpenTab;
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 5, vsync: this, initialIndex: 1, animationDuration: PK.tab);
  Map? _cards;
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
    try {
      final r = await AppScope.read(context).api.get('/dashboard') as Map;
      if (mounted) setState(() => _cards = r['cards'] as Map);
    } on ApiException {
      // kartu tetap menampilkan nilai terakhir
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final me = AppScope.of(context).me!;
    final c = _cards;
    int n(String k) => (c?[k] as num?)?.toInt() ?? 0;
    return NestedScrollView(
      headerSliverBuilder: (context, _) => [
        SliverToBoxAdapter(
          child: _Header(firstName: _firstName(me.name), place: me.identity, role: me.roleLabel, demo: me.isDemo),
        ),
        SliverToBoxAdapter(
          child: Transform.translate(
            offset: const Offset(0, -6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  if (n('active_sos') > 0) ...[_ActiveSosBanner(count: n('active_sos'), onTap: () => widget.onOpenTab(1)), const SizedBox(height: 10)],
                  StatGrid(
                    children: [
                      Reveal(
                        index: 0,
                        child: StatCard(label: 'SOS hari ini', value: n('sos_today'), icon: Icons.notifications_active_rounded, color: context.danger),
                      ),
                      Reveal(
                        index: 1,
                        child: StatCard(
                          label: 'Laporan baru',
                          value: n('new_reports'),
                          icon: Icons.description_rounded,
                          color: const Color(0xFF2A78D6),
                          onTap: () => _tabs.animateTo(1),
                        ),
                      ),
                      Reveal(
                        index: 2,
                        child: StatCard(label: 'Dalam penanganan', value: n('in_progress'), icon: Icons.warning_rounded, color: const Color(0xFFE09A00)),
                      ),
                      Reveal(
                        index: 3,
                        child: StatCard(label: 'Selesai', value: n('resolved_7d'), icon: Icons.check_circle_rounded, color: PK.green),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        SliverPersistentHeader(pinned: true, delegate: _TabBarDelegate(_tabs, context.pageBg)),
      ],
      body: TabBarView(
        controller: _tabs,
        children: [
          const _NewsTab(),
          const _ReportsTab(),
          const _VideoTab(),
          _MapTab(center: AppScope.of(context).here == null ? null : LatLng(AppScope.of(context).here!.lat, AppScope.of(context).here!.lng)),
          const _TimeTab(),
        ],
      ),
    );
  }
}

String _firstName(String name) {
  const ranks = {'aiptu', 'aipda', 'bripka', 'brigpol', 'briptu', 'bripda', 'ipda', 'iptu', 'akp', 'kompol', 'pak', 'bu'};
  final parts = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '';
  return parts.length > 1 && ranks.contains(parts.first.toLowerCase()) ? parts[1] : parts.first;
}

/// Header navy: "Selamat sore, Rina 👋", wilayah, lonceng; tepi bawah gradasi merah → putih tipis.
class _Header extends StatelessWidget {
  const _Header({required this.firstName, required this.place, required this.role, required this.demo});
  final String firstName, place, role;
  final bool demo;
  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final navy = navyHeader(context);
    return CustomPaint(
      painter: NavyWavePainter(navy: navy, bg: context.pageBg),
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, top + 14, 8, 44),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '${greeting()}${firstName.isEmpty ? '' : ', $firstName'} 👋',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800),
                        ),
                      ),
                      if (demo) ...[const SizedBox(width: 8), const DemoTag()],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Semantics(
                    label: 'Anda sebagai: $place',
                    excludeSemantics: true,
                    child: Row(
                      children: [
                        const Icon(Icons.badge_rounded, color: Colors.white, size: 16),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            place,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const NotifBell(light: true),
          ],
        ),
      ),
    );
  }
}

class _ActiveSosBanner extends StatelessWidget {
  const _ActiveSosBanner({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    liveRegion: true,
    label: '$count SOS aktif belum ditanggapi. Ketuk untuk melihat.',
    excludeSemantics: true,
    child: Material(
      color: PK.red,
      borderRadius: BorderRadius.circular(PK.rCard),
      child: InkWell(
        borderRadius: BorderRadius.circular(PK.rCard),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Icon(Icons.notifications_active_rounded, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$count SOS aktif menunggu tanggapan',
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Tab teks (Berita, Laporan, Video, Lokasi, Waktu): aktif merah dengan garis bawah 3 px.
class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  _TabBarDelegate(this.controller, this.bg);
  final TabController controller;
  final Color bg;
  @override
  double get minExtent => 48;
  @override
  double get maxExtent => 48;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => Container(
    color: bg,
    child: TabBar(
      controller: controller,
      isScrollable: false,
      labelColor: context.danger,
      unselectedLabelColor: context.ink2,
      labelPadding: EdgeInsets.zero,
      labelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      unselectedLabelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
      indicator: UnderlineTabIndicator(
        borderSide: BorderSide(color: context.danger, width: 3),
        borderRadius: BorderRadius.circular(3),
      ),
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: context.hairline,
      tabs: const [
        Tab(height: 48, text: 'Berita'),
        Tab(height: 48, text: 'Laporan'),
        Tab(height: 48, text: 'Video'),
        Tab(height: 48, text: 'Lokasi'),
        Tab(height: 48, text: 'Waktu'),
      ],
    ),
  );
  @override
  bool shouldRebuild(_TabBarDelegate old) => old.bg != bg || old.controller != controller;
}

// ---------------------------------------------------------------- tab: Berita

class _NewsTab extends StatefulWidget {
  const _NewsTab();
  @override
  State<_NewsTab> createState() => _NewsTabState();
}

class _NewsTabState extends State<_NewsTab> with AutomaticKeepAliveClientMixin {
  List<Map>? _items;
  String? _error;
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await AppScope.read(context).api.get('/news') as Map;
      if (mounted) setState(() => _items = (r['items'] as List).cast<Map>());
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_error != null && _items == null) return ErrorState(message: _error!, onRetry: _load);
    if (_items == null) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _load,
      child: _items!.isEmpty
          ? ListView(
              children: const [
                EmptyState(icon: Icons.newspaper_rounded, title: 'Belum ada kabar', body: 'Pengumuman keamanan wilayah Anda akan tampil di sini.'),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: _items!.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) => Reveal(
                index: i,
                child: NewsCard(news: _items![i]),
              ),
            ),
    );
  }
}

// ---------------------------------------------------------------- tab: Laporan

class _ReportsTab extends StatefulWidget {
  const _ReportsTab();
  @override
  State<_ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<_ReportsTab> with AutomaticKeepAliveClientMixin {
  String? _status;
  ReportLayout _layout = ReportLayout.fields;
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ReportList(
      layout: _layout,
      query: {'status': _status},
      limit: 20,
      header: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Expanded(
              child: FilterChips<String?>(
                value: _status,
                onChanged: (v) => setState(() => _status = v),
                options: const [(null, 'Semua'), ('baru', 'Baru'), ('diproses', 'Diproses'), ('selesai', 'Selesai'), ('tidak_valid', 'Tidak valid')],
              ),
            ),
            const SizedBox(width: 8),
            // Ganti tampilan: kartu lengkap (enak di HP) atau tabel (Berita · No HP · … · Tindak Lanjut).
            SegmentedButton<ReportLayout>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: PK.red,
                selectedForegroundColor: Colors.white,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 6),
              ),
              segments: const [
                ButtonSegment(value: ReportLayout.fields, icon: Icon(Icons.view_agenda_outlined, size: 20), tooltip: 'Tampilan kartu'),
                ButtonSegment(value: ReportLayout.table, icon: Icon(Icons.table_rows_outlined, size: 20), tooltip: 'Tampilan tabel'),
              ],
              selected: {_layout},
              onSelectionChanged: (s) => setState(() => _layout = s.first),
            ),
          ],
        ),
      ),
      emptyTitle: 'Tidak ada laporan',
      emptyBody: 'Belum ada laporan dengan status ini di kecamatan Anda.',
    );
  }
}

// ---------------------------------------------------------------- tab: Video

class _VideoTab extends StatefulWidget {
  const _VideoTab();
  @override
  State<_VideoTab> createState() => _VideoTabState();
}

class _VideoTabState extends State<_VideoTab> with AutomaticKeepAliveClientMixin {
  List<Map>? _items;
  String? _error;
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await AppScope.read(context).api.get('/videos') as Map;
      if (mounted) {
        setState(() {
          _items = (r['items'] as List).cast<Map>();
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_error != null && _items == null) return ErrorState(message: _error!, onRetry: _load);
    if (_items == null) return const Center(child: CircularProgressIndicator());
    if (_items!.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: const [
            EmptyState(
              icon: Icons.videocam_off_rounded,
              title: 'Belum ada video bukti',
              body: 'Video yang dikirim pelapor di kecamatan Anda akan tampil di sini.',
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 0.78),
        itemCount: _items!.length,
        itemBuilder: (context, i) {
          final v = _items![i];
          final r = Report(v['report'] as Map);
          return Reveal(
            index: i,
            child: Semantics(
              button: true,
              label: 'Video bukti ${r.headline}, ${fmtRelative(DateTime.parse(v['created_at'] as String).toLocal())}',
              excludeSemantics: true,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(PK.rCard),
                child: Material(
                  color: PK.navy,
                  child: InkWell(
                    onTap: v['url'] == null
                        ? null
                        : () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => VideoScreen(url: v['url'] as String, title: r.headline, subtitle: r.placeLine),
                            ),
                          ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: r.isSos ? const [PK.red, PK.redDark] : const [Color(0xFF1E3A8A), PK.navy],
                            ),
                          ),
                        ),
                        Center(
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.9), shape: BoxShape.circle),
                            child: Icon(Icons.play_arrow_rounded, size: 36, color: r.isSos ? PK.red : PK.navy),
                          ),
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(6)),
                            child: Text(
                              v['duration_s'] != null ? fmtDuration(v['duration_s'] as num) : 'Video',
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(10, 18, 10, 10),
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black87]),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  r.headline,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  [if (r.kelurahan != null) r.kelurahan!.name, fmtRelative(DateTime.parse(v['created_at'] as String).toLocal())].join(' · '),
                                  maxLines: 1,
                                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------- tab: Lokasi

class _MapTab extends StatefulWidget {
  const _MapTab({this.center});
  final LatLng? center;
  @override
  State<_MapTab> createState() => _MapTabState();
}

class _MapTabState extends State<_MapTab> with AutomaticKeepAliveClientMixin {
  List<Report>? _items;
  String? _kind;
  int _days = 30;
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await AppScope.read(context).api.get('/map', {'days': '$_days', 'kind': _kind}) as Map;
      if (mounted) setState(() => _items = (r['items'] as List).map((e) => Report(e as Map)).toList());
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: FilterChips<String?>(
                  value: _kind,
                  onChanged: (v) {
                    setState(() => _kind = v);
                    _load();
                  },
                  options: const [(null, 'Semua'), ('sos', 'SOS'), ('laporan', 'Laporan')],
                ),
              ),
              PopupMenuButton<int>(
                tooltip: 'Rentang waktu',
                initialValue: _days,
                onSelected: (d) {
                  setState(() => _days = d);
                  _load();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 7, child: Text('7 hari')),
                  PopupMenuItem(value: 30, child: Text('30 hari')),
                  PopupMenuItem(value: 90, child: Text('3 bulan')),
                ],
                child: Chip(avatar: const Icon(Icons.date_range_rounded, size: 18), label: Text(_days == 90 ? '3 bulan' : '$_days hari')),
              ),
            ],
          ),
        ),
        Expanded(
          child: _items == null
              ? const Center(child: CircularProgressIndicator())
              : Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(PK.rCard),
                    child: IncidentMap(reports: _items!, center: widget.center),
                  ),
                ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- tab: Waktu

class _TimeTab extends StatefulWidget {
  const _TimeTab();
  @override
  State<_TimeTab> createState() => _TimeTabState();
}

class _TimeTabState extends State<_TimeTab> with AutomaticKeepAliveClientMixin {
  Map? _d;
  String? _error;
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await AppScope.read(context).api.get('/analytics/summary', {'period': '30d'}) as Map;
      if (mounted) setState(() => _d = r);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_error != null && _d == null) return ErrorState(message: _error!, onRetry: _load);
    final d = _d;
    if (d == null) return const Center(child: CircularProgressIndicator());
    final byHour = (d['by_hour'] as List).cast<num>();
    final weekly = (d['weekly'] as List).cast<Map>();
    final peak = byHour.isEmpty ? 0 : byHour.indexOf(byHour.reduce((a, b) => a > b ? a : b));
    final t = Theme.of(context).textTheme;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Kejadian per jam', style: t.titleMedium),
                Text(
                  '30 hari terakhir · jam rawan: ${peak.toString().padLeft(2, '0')}.00–${((peak + 1) % 24).toString().padLeft(2, '0')}.00',
                  style: t.bodySmall,
                ),
                const SizedBox(height: 16),
                ColumnChart(
                  values: byHour,
                  highlightTop: true,
                  labelFor: (i) => i % 6 == 0 ? i.toString().padLeft(2, '0') : null,
                  tooltipFor: (i) => 'Pukul ${i.toString().padLeft(2, '0')}.00: ${byHour[i]} kejadian',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tren mingguan', style: t.titleMedium),
                Text('Jumlah SOS + laporan per minggu, 8 minggu terakhir', style: t.bodySmall),
                const SizedBox(height: 16),
                if (weekly.isEmpty)
                  const Text('Belum ada data')
                else
                  ColumnChart(
                    values: weekly.map((w) => w['n'] as num).toList(),
                    height: 160,
                    labelFor: (i) => i < weekly.length ? fmtShort(DateTime.parse(weekly[i]['week'] as String)).split(' ').take(2).join(' ') : null,
                    tooltipFor: (i) => 'Minggu ${fmtShort(DateTime.parse(weekly[i]['week'] as String))}: ${weekly[i]['n']} kejadian',
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
