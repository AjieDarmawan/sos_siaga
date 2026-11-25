import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../core/models.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/incident_map.dart';
import '../widgets/report_filters.dart';
import '../widgets/report_list.dart';
import '../widgets/search_filter.dart';

/// Laporan (FR-16): SOS & laporan yang memanggil nomor pengguna + laporan di kecamatannya, sebagai daftar berfoto
/// atau peta, dengan cari + filter (jenis, status, kelurahan) di lembar bawah.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  ReportFilter _f = const ReportFilter();
  bool _map = false;

  @override
  Widget build(BuildContext context) {
    final me = AppScope.of(context).me!;
    return Scaffold(
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            PageHeader(
              title: 'Laporan',
              subtitle: me.scope != null ? 'Untuk Anda + Kec. ${me.scope!.name}' : 'SOS yang memanggil nomor Anda',
              actions: [
                IconButton(
                  tooltip: _map ? 'Tampilkan daftar' : 'Tampilkan peta',
                  icon: Icon(_map ? Icons.view_list_rounded : Icons.map_outlined),
                  onPressed: () => setState(() => _map = !_map),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: SearchFilterRow(value: _f, showDate: false, onChanged: (f) => setState(() => _f = f)),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: context.reduceMotion ? Duration.zero : PK.tab,
                child: _map
                    ? Padding(
                        key: const ValueKey('map'),
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(PK.rCard),
                          child: _FilteredMap(filter: _f),
                        ),
                      )
                    : ReportList(
                        key: const ValueKey('list'),
                        thumbnail: true,
                        query: _f.toQuery(),
                        emptyTitle: 'Tidak ada laporan',
                        emptyBody: 'Belum ada SOS atau laporan yang cocok dengan filter ini.',
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilteredMap extends StatefulWidget {
  const _FilteredMap({required this.filter});
  final ReportFilter filter;
  @override
  State<_FilteredMap> createState() => _FilteredMapState();
}

class _FilteredMapState extends State<_FilteredMap> {
  List<Report>? _items;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_FilteredMap old) {
    super.didUpdateWidget(old);
    if (old.filter.toQuery().toString() != widget.filter.toQuery().toString()) _load();
  }

  Future<void> _load() async {
    try {
      final r = await AppScope.read(context).api.get('/reports', {...widget.filter.toQuery(), 'limit': '100'}) as Map;
      if (mounted) setState(() => _items = (r['items'] as List).map((e) => Report(e as Map)).toList());
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) => _items == null ? const Center(child: CircularProgressIndicator()) : IncidentMap(reports: _items!);
}
