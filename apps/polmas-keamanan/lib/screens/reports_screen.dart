import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/ui.dart';
import 'incident_screen.dart';

/// Daftar Tindak Lanjut (mockup): header navy + cari + filter, chip status (dengan jumlah) dan chip ekosistem,
/// kartu berisi semua kolom; tabel saat dipilih atau saat HP dimiringkan. Riwayat "Saya" = cakupan di filter.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, this.active = true});

  /// Tab sedang tampil: dipakai untuk menerapkan filter titipan dari Beranda.
  final bool active;
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

const _pillars = [('umkm', 'UMKM'), ('warga', 'Lingkungan'), ('kantor', 'Perkantoran'), ('sekolah', 'Pendidikan'), ('komunitas', 'Komunitas')];

class _ReportsScreenState extends State<ReportsScreen> {
  final _q = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;
  List<Report> _items = [];
  Map? _counts;
  String? _next;
  String? _error;
  bool _loading = true;
  bool _more = false;
  bool _table = false;
  int _version = -1;

  String? _status; // baru | diproses | selesai
  String? _source;
  String? _kind; // sos | laporan
  bool _mine = false;
  int _days = 7;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 400) _loadMore();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppScope.of(context);
    final pending = widget.active ? state.pendingReportStatus : null;
    if (pending != null) {
      state.pendingReportStatus = null;
      _status = pending;
      _version = state.dataVersion;
      _load();
    } else if (state.dataVersion != _version) {
      _version = state.dataVersion;
      _load();
    }
  }

  @override
  void didUpdateWidget(ReportsScreen old) {
    super.didUpdateWidget(old);
    final state = AppScope.read(context);
    if (widget.active && state.pendingReportStatus != null) {
      _status = state.pendingReportStatus;
      state.pendingReportStatus = null;
      _load();
    }
  }

  Map<String, String?> get _query {
    final today = DateTime.now();
    return {
      'scope': _mine ? 'me' : 'kecamatan',
      'status': _status,
      'source': _source,
      'kind': _kind,
      'q': _q.text.trim().isEmpty ? null : _q.text.trim(),
      'from': _ymd(today.subtract(Duration(days: _days - 1))),
      'to': _ymd(today),
      'limit': '20',
    };
  }

  String _ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() => _loading = _items.isEmpty);
    try {
      final r = await AppScope.read(context).api.get('/reports', _query) as Map;
      if (!mounted) return;
      setState(() {
        _items = (r['items'] as List).map((e) => Report(e as Map)).toList();
        _counts = r['counts'] as Map?;
        _next = r['next_before'] as String?;
        _error = null;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_more || _next == null) return;
    _more = true;
    try {
      final r = await AppScope.read(context).api.get('/reports', {..._query, 'before': _next}) as Map;
      if (!mounted) return;
      setState(() {
        _items = [..._items, ...(r['items'] as List).map((e) => Report(e as Map))];
        _next = r['next_before'] as String?;
      });
    } catch (_) {
    } finally {
      _more = false;
    }
  }

  void _set(VoidCallback f) {
    setState(f);
    _load();
  }

  void _onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _load);
  }

  Future<void> _filters() async {
    final res = await showModalBottomSheet<(int, String?, bool)>(
      context: context,
      showDragHandle: true,
      builder: (_) => _FilterSheet(days: _days, kind: _kind, mine: _mine),
    );
    if (res != null) {
      _set(() {
        _days = res.$1;
        _kind = res.$2;
        _mine = res.$3;
      });
    }
  }

  @override
  void dispose() {
    _q.dispose();
    _scroll.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  String get _scopeLine {
    final me = AppScope.of(context).me!;
    final where = _mine ? 'Laporan saya' : (me.scope != null ? 'Kec. ${me.scope!.name}' : 'Wilayah saya');
    return '$where · ${_days == 1 ? 'hari ini' : '$_days hari terakhir'}';
  }

  @override
  Widget build(BuildContext context) {
    final landscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final state = AppScope.of(context);
    final c = _counts;
    final statusChips = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: landscape ? EdgeInsets.zero : const EdgeInsets.fromLTRB(16, 12, 16, 2),
      child: Row(
        children: [
          FilterPill(label: 'Semua', count: c?['semua'] as int?, selected: _status == null, onTap: () => _set(() => _status = null)),
          FilterPill(label: 'Darurat', count: c?['baru'] as int?, selected: _status == 'baru', onTap: () => _set(() => _status = 'baru')),
          FilterPill(label: 'Diproses', count: c?['diproses'] as int?, selected: _status == 'diproses', onTap: () => _set(() => _status = 'diproses')),
          FilterPill(label: 'Selesai', count: c?['selesai'] as int?, selected: _status == 'selesai', onTap: () => _set(() => _status = 'selesai')),
        ],
      ),
    );
    final table = _table || landscape;
    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null && _items.isEmpty) {
      body = ListView(children: [ErrorState(message: _error!, onRetry: _load)]);
    } else if (_items.isEmpty) {
      body = ListView(
        children: const [
          EmptyState(icon: Icons.inbox_outlined, title: 'Tidak ada laporan', body: 'Coba ubah filter status, ekosistem, atau periode.'),
        ],
      );
    } else if (table) {
      body = ListView(
        controller: _scroll,
        padding: EdgeInsets.fromLTRB(landscape ? 44 : 16, 10, 16, 24),
        children: [ReportTable(items: _items)],
      );
    } else {
      body = ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
        itemCount: _items.length + (_next != null ? 1 : 0),
        itemBuilder: (_, i) => i == _items.length
            ? const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
            : ReportCard(r: _items[i], here: state.here, onTap: () => openIncident(context, _items[i].id)),
      );
    }

    if (landscape) {
      return SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(44, 12, 18, 0),
              child: Row(
                children: [
                  Text('Tindak Lanjut', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: context.ink)),
                  const SizedBox(width: 12),
                  Expanded(child: Align(alignment: Alignment.centerRight, child: statusChips)),
                ],
              ),
            ),
            Expanded(child: RefreshIndicator(onRefresh: _load, child: body)),
          ],
        ),
      );
    }

    return Column(
      children: [
        NavyHeader(
          radius: 26,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Tindak Lanjut', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text(_scopeLine, style: const TextStyle(fontSize: 12, color: PK.headerMute)),
                      ],
                    ),
                  ),
                  ViewToggle(table: _table, onDark: true, onChanged: (v) => setState(() => _table = v)),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                height: 44,
                padding: const EdgeInsets.only(left: 12, right: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search_rounded, size: 18, color: PK.headerMute),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _q,
                        onChanged: _onSearch,
                        textInputAction: TextInputAction.search,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        cursorColor: Colors.white,
                        decoration: const InputDecoration(
                          hintText: 'Cari berita, nama, kelurahan…',
                          hintStyle: TextStyle(color: PK.headerMute, fontSize: 13),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          isCollapsed: true,
                        ),
                      ),
                    ),
                    Tooltip(
                      message: 'Filter periode, jenis, cakupan',
                      child: Material(
                        color: PK.gold,
                        borderRadius: BorderRadius.circular(9),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(9),
                          onTap: _filters,
                          child: Badge(
                            isLabelVisible: _days != 7 || _kind != null || _mine,
                            smallSize: 8,
                            backgroundColor: PK.red,
                            child: const SizedBox(width: 32, height: 32, child: Icon(Icons.filter_alt_outlined, size: 16, color: PK.navy2)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        statusChips,
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
          child: Row(
            children: [
              FilterPill(label: 'Semua ekosistem', dashed: true, selected: _source == null, onTap: () => _set(() => _source = null)),
              for (final (k, l) in _pillars) FilterPill(label: l, dashed: true, selected: _source == k, onTap: () => _set(() => _source = k)),
            ],
          ),
        ),
        Expanded(child: RefreshIndicator(onRefresh: _load, child: body)),
      ],
    );
  }
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.days, required this.kind, required this.mine});
  final int days;
  final String? kind;
  final bool mine;
  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late int _days = widget.days;
  late String? _kind = widget.kind;
  late bool _mine = widget.mine;

  Widget _group(String title, List<Widget> chips) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: context.ink)),
        const SizedBox(height: 8),
        Wrap(runSpacing: 8, children: chips),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).padding.bottom),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Filter', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: context.ink)),
        const SizedBox(height: 14),
        _group('Periode', [
          for (final d in const [1, 7, 30, 90])
            FilterPill(label: d == 1 ? 'Hari ini' : '$d hari', selected: _days == d, onTap: () => setState(() => _days = d)),
        ]),
        _group('Jenis', [
          FilterPill(label: 'Semua', selected: _kind == null, onTap: () => setState(() => _kind = null)),
          FilterPill(label: 'SOS', selected: _kind == 'sos', onTap: () => setState(() => _kind = 'sos')),
          FilterPill(label: 'Pengaduan', selected: _kind == 'laporan', onTap: () => setState(() => _kind = 'laporan')),
        ]),
        _group('Cakupan', [
          FilterPill(label: 'Wilayah saya', selected: !_mine, onTap: () => setState(() => _mine = false)),
          FilterPill(label: 'Saya (laporan untuk & ditangani saya)', selected: _mine, onTap: () => setState(() => _mine = true)),
        ]),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: PK.navy, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            onPressed: () => Navigator.pop(context, (_days, _kind, _mine)),
            child: const Text('Terapkan', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          ),
        ),
      ],
    ),
  );
}

// ------------------------------------------------------------------ tabel

/// Tabel Tindak Lanjut: header navy berikon, 9 kolom (Berita, No HP, Ekosistem, Dari Siapa, Foto/Video, Location,
/// Waktu, Status, Tindak Lanjut). Digeser ke samping; ketuk baris untuk membuka detail.
class ReportTable extends StatelessWidget {
  const ReportTable({super.key, required this.items});
  final List<Report> items;

  static const _cols = [
    (Icons.newspaper_rounded, 'Berita', 190.0),
    (Icons.phone_outlined, 'No HP', 130.0),
    (Icons.layers_outlined, 'Ekosistem', 120.0),
    (Icons.person_outline_rounded, 'Dari Siapa', 150.0),
    (Icons.smart_display_outlined, 'Foto/Video', 120.0),
    (Icons.location_on_outlined, 'Location', 170.0),
    (Icons.calendar_today_outlined, 'Waktu', 100.0),
    (Icons.check_circle_outline_rounded, 'Status', 100.0),
    (Icons.assignment_turned_in_outlined, 'Tindak Lanjut', 200.0),
  ];

  @override
  Widget build(BuildContext context) {
    final here = AppScope.of(context).here;
    final line = context.isDark ? context.hairline : const Color(0xFFDCE3EE);
    Widget cell(int i, Widget child, {bool head = false}) => Container(
      width: _cols[i].$3,
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: head ? 11 : 9),
      decoration: BoxDecoration(
        border: Border(right: i < _cols.length - 1 ? BorderSide(color: head ? const Color(0xFF3A4B6E) : line) : BorderSide.none),
      ),
      child: child,
    );
    Widget two(String a, String? b, {Color? color}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(a, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: color ?? context.ink)),
        if (b != null) Text(b, style: TextStyle(fontSize: 11, color: context.ink2)),
      ],
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: context.surface,
          border: Border.all(color: const Color(0xFF2B3B5E)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                color: const Color(0xFF243656),
                child: Row(
                  children: [
                    for (final (i, (icon, label, _)) in _cols.indexed)
                      cell(
                        i,
                        Row(
                          children: [
                            Icon(icon, size: 16, color: Colors.white),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w800),
                              ),
                            ),
                          ],
                        ),
                        head: true,
                      ),
                  ],
                ),
              ),
              for (final r in items)
                InkWell(
                  onTap: () => openIncident(context, r.id),
                  child: Container(
                    decoration: BoxDecoration(border: Border(top: BorderSide(color: line))),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          cell(0, two(r.headline, r.isSos ? 'SOS' : 'Pengaduan')),
                          cell(
                            1,
                            r.reporterPhone == null
                                ? Text('Disamarkan', style: TextStyle(fontSize: 11, color: context.ink2))
                                : Text(fmtPhone(r.reporterPhone!), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.brand)),
                          ),
                          cell(2, two(r.ecosystemLabel, r.ecosystemApp)),
                          cell(3, two(r.reporterName, r.sourcePlace)),
                          cell(
                            4,
                            r.imageCount + r.videoCount + r.audioCount == 0
                                ? Text('Tidak ada', style: TextStyle(fontSize: 11, color: context.ink2))
                                : Wrap(
                                    spacing: 4,
                                    runSpacing: 4,
                                    children: [
                                      if (r.thumbUrls.isNotEmpty || r.imageCount > 0)
                                        MediaThumb(url: r.thumbUrls.firstOrNull, kind: 'image', width: 40, height: 32),
                                      if (r.videoCount > 0) MediaThumb(kind: 'video', seconds: r.videoSeconds, width: 40, height: 32),
                                      if (r.audioCount > 0) const MediaThumb(kind: 'audio', width: 40, height: 32),
                                    ],
                                  ),
                          ),
                          cell(
                            5,
                            two(
                              r.kelurahan != null ? 'Kel. ${r.kelurahan!.name}' : (r.kecamatan != null ? 'Kec. ${r.kecamatan!.name}' : 'Lokasi GPS'),
                              [?(r.locationText ?? r.sourcePlace), ?r.distanceFrom(here)].join(' · '),
                            ),
                          ),
                          cell(6, two(fmtTime(r.createdAt), fmtDayMonth(r.createdAt))),
                          cell(7, Align(alignment: Alignment.topLeft, child: StatusPill(status: r.status, sos: r.isSos))),
                          cell(
                            8,
                            r.lastResponse != null
                                ? two(
                                    responseText(r.lastResponse!),
                                    '${officerName(r.lastResponse!['officer'] as String?)} · ${fmtTime(DateTime.parse(r.lastResponse!['created_at'] as String).toLocal())}',
                                  )
                                : Text(
                                    r.status == PkStatus.baru ? 'Belum ditanggapi' : '–',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.dangerText),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
