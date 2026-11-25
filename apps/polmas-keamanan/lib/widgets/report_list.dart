import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../screens/incident_screen.dart';
import '../theme/tokens.dart';
import 'common.dart';
import 'report_table.dart';

enum ReportLayout { card, fields, table }

/// Judul kelompok hari: pita abu muda selebar daftar (Hari ini, Kemarin, …).
class DayHeader extends StatelessWidget {
  const DayHeader(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 6, bottom: 10),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(color: context.isDark ? PK.darkSurface : const Color(0xFFECEFF3), borderRadius: BorderRadius.circular(10)),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
  );
}

/// Daftar laporan dari `/reports` atau `/history`: tarik ke bawah untuk memuat ulang, gulir untuk memuat lebih lama,
/// opsional dikelompokkan per hari. Memuat ulang otomatis saat filter atau [AppState.dataVersion] berubah.
class ReportList extends StatefulWidget {
  const ReportList({
    super.key,
    required this.query,
    this.endpoint = '/reports',
    this.groupByDay = false,
    this.header,
    this.emptyTitle = 'Belum ada laporan',
    this.emptyBody,
    this.limit = 30,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 24),
    this.primary,
    this.thumbnail = false,
    this.layout = ReportLayout.card,
  });

  /// card = kartu ringkas (foto/bilah), fields = kartu lengkap 9 isian, table = tabel geser samping.
  final ReportLayout layout;

  /// Kartu dengan gambar mini (Beranda) atau bilah warna status (Laporan, Riwayat).
  final bool thumbnail;
  final Map<String, String?> query;
  final String endpoint;
  final bool groupByDay;
  final Widget? header;
  final String emptyTitle;
  final String? emptyBody;
  final int limit;
  final EdgeInsets padding;
  final bool? primary;

  @override
  State<ReportList> createState() => _ReportListState();
}

class _ReportListState extends State<ReportList> {
  final _items = <Report>[];
  String? _next;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _version = -1;
  String _queryKey = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final v = AppScope.of(context).dataVersion;
    if (v != _version) {
      final first = _version == -1;
      _version = v;
      _load(silent: !first);
    }
  }

  @override
  void didUpdateWidget(ReportList old) {
    super.didUpdateWidget(old);
    if (_key(widget.query) != _queryKey || old.endpoint != widget.endpoint) _load();
  }

  String _key(Map<String, String?> q) => (q.entries.where((e) => e.value != null).map((e) => '${e.key}=${e.value}').toList()..sort()).join('&');

  Future<void> _load({bool silent = false}) async {
    _queryKey = _key(widget.query);
    final key = _queryKey;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final r = await AppScope.read(context).api.get(widget.endpoint, {...widget.query, 'limit': '${widget.limit}'}) as Map;
      if (!mounted || key != _queryKey) return;
      setState(() {
        _items
          ..clear()
          ..addAll((r['items'] as List).map((e) => Report(e as Map)));
        _next = r['next_before'] as String?;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted && key == _queryKey && !silent) setState(() => _error = e.message);
    } finally {
      if (mounted && key == _queryKey) setState(() => _loading = false);
    }
  }

  Future<void> _more() async {
    if (_next == null || _loadingMore) return;
    setState(() => _loadingMore = true);
    final key = _queryKey;
    try {
      final r = await AppScope.read(context).api.get(widget.endpoint, {...widget.query, 'limit': '${widget.limit}', 'before': _next}) as Map;
      if (!mounted || key != _queryKey) return;
      setState(() {
        _items.addAll((r['items'] as List).map((e) => Report(e as Map)));
        _next = r['next_before'] as String?;
      });
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    if (widget.header != null) children.add(widget.header!);
    if (_loading) {
      children.addAll(List.generate(4, (_) => const _Skeleton()));
    } else if (_error != null) {
      children.add(ErrorState(message: _error!, onRetry: _load));
    } else if (_items.isEmpty) {
      children.add(EmptyState(icon: Icons.inbox_rounded, title: widget.emptyTitle, body: widget.emptyBody));
    } else {
      DateTime? lastDay;
      final from = AppScope.of(context).here;
      if (widget.layout == ReportLayout.table) children.add(ReportTable(reports: List.of(_items), from: from));
      for (final (i, r) in widget.layout == ReportLayout.table ? const <(int, Report)>[] : _items.indexed) {
        final d = DateTime(r.createdAt.year, r.createdAt.month, r.createdAt.day);
        if (widget.groupByDay && d != lastDay) {
          lastDay = d;
          children.add(Semantics(header: true, child: DayHeader(fmtDayHeader(d))));
        }
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Reveal(
              index: i,
              child: widget.layout == ReportLayout.fields
                  ? ReportFieldsCard(report: r, from: from)
                  : IncidentCard(report: r, thumbnail: widget.thumbnail, from: from, onTap: () => openIncident(context, r.id)),
            ),
          ),
        );
      }
      if (_next != null) {
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: _loadingMore
                  ? const CircularProgressIndicator()
                  : TextButton.icon(onPressed: _more, icon: const Icon(Icons.expand_more_rounded), label: const Text('Muat lebih lama')),
            ),
          ),
        );
      } else {
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(child: Text('Semua laporan sudah ditampilkan', style: Theme.of(context).textTheme.bodySmall)),
          ),
        );
      }
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.axis == Axis.vertical && n.metrics.extentAfter < 300) _more();
          return false;
        },
        child: ListView(primary: widget.primary, physics: const AlwaysScrollableScrollPhysics(), padding: widget.padding, children: children),
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: AppCard(
      child: Row(
        children: [
          CircleAvatar(radius: 22, backgroundColor: Theme.of(context).dividerColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(height: 14, width: 160, color: Theme.of(context).dividerColor),
                const SizedBox(height: 8),
                Container(height: 12, width: 220, color: Theme.of(context).dividerColor),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// Baris pil filter yang bisa digeser horizontal.
class FilterChips<T> extends StatelessWidget {
  const FilterChips({super.key, required this.options, required this.value, required this.onChanged});
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 48,
    child: ListView(
      scrollDirection: Axis.horizontal,
      children: [
        for (final (v, label) in options)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(label: Text(label), selected: v == value, showCheckmark: false, onSelected: (_) => onChanged(v)),
          ),
      ],
    ),
  );
}
