import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../screens/area_screen.dart';
import '../theme/tokens.dart';

/// Filter laporan: jenis, status, kelurahan, rentang tanggal, kata kunci (FR-16, FR-18).
class ReportFilter {
  const ReportFilter({this.kind, this.status, this.kelurahan, this.range, this.q = ''});
  final String? kind, status;
  final Region? kelurahan;
  final DateTimeRange? range;
  final String q;

  ReportFilter copy({Object? kind = _keep, Object? status = _keep, Object? kelurahan = _keep, Object? range = _keep, String? q}) => ReportFilter(
    kind: kind == _keep ? this.kind : kind as String?,
    status: status == _keep ? this.status : status as String?,
    kelurahan: kelurahan == _keep ? this.kelurahan : kelurahan as Region?,
    range: range == _keep ? this.range : range as DateTimeRange?,
    q: q ?? this.q,
  );

  static String _d(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Map<String, String?> toQuery() => {
    'kind': kind,
    'status': status,
    'kelurahan': kelurahan?.code,
    'from': range == null ? null : _d(range!.start),
    'to': range == null ? null : _d(range!.end),
    'q': q.trim().isEmpty ? null : q.trim(),
  };

  int get activeCount => [kind, status, kelurahan, range].where((e) => e != null).length;
}

const _keep = Object();

const kindOptions = <(String?, String)>[(null, 'Semua jenis'), ('sos', 'SOS'), ('laporan', 'Laporan')];
const statusOptions = <(String?, String)>[
  (null, 'Semua status'),
  ('baru', 'Baru / Darurat'),
  ('diproses', 'Diproses'),
  ('selesai', 'Selesai'),
  ('tidak_valid', 'Tidak valid'),
];

/// Kolom cari + baris pil filter (jenis, status, kelurahan, tanggal). Pil aktif berwarna; ketuk pil aktif untuk menghapus.
class FilterBar extends StatefulWidget {
  const FilterBar({super.key, required this.value, required this.onChanged, this.showDate = true, this.showKelurahan = true, this.showSearch = true});

  /// false = hanya pil filter (kolom cari dipasang sendiri oleh layar, mis. Riwayat).
  final bool showSearch;
  final ReportFilter value;
  final ValueChanged<ReportFilter> onChanged;
  final bool showDate, showKelurahan;
  @override
  State<FilterBar> createState() => _FilterBarState();
}

class _FilterBarState extends State<FilterBar> {
  late final _q = TextEditingController(text: widget.value.q);
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  /// Lembar pilihan; mengembalikan ('', …) untuk "semua" supaya bisa dibedakan dari batal (null).
  Future<(String?,)?> _choose(String title, List<(String?, String)> options, String? current) => showModalBottomSheet<(String?,)>(
    context: context,
    builder: (_) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(title, style: Theme.of(context).textTheme.titleLarge),
          ),
          for (final (v, l) in options)
            ListTile(
              minTileHeight: 52,
              title: Text(l),
              trailing: v == current ? Icon(Icons.check_rounded, color: context.brand) : null,
              onTap: () => Navigator.pop(context, (v,)),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final f = widget.value;
    final scope = AppScope.of(context).me?.scope;
    return Column(
      children: [
        if (widget.showSearch) ...[
          TextField(
            controller: _q,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: 'Cari judul, jenis, kelurahan, pelapor',
              suffixIcon: _q.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Hapus pencarian',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _q.clear();
                        widget.onChanged(f.copy(q: ''));
                        setState(() {});
                      },
                    ),
            ),
            onChanged: (v) {
              setState(() {});
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 400), () => widget.onChanged(widget.value.copy(q: v)));
            },
          ),
          const SizedBox(height: 8),
        ],
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _Pill(
                label: kindOptions.firstWhere((o) => o.$1 == f.kind).$2,
                active: f.kind != null,
                onTap: () async {
                  final v = await _choose('Jenis', kindOptions, f.kind);
                  if (v != null) widget.onChanged(f.copy(kind: v.$1));
                },
              ),
              _Pill(
                label: statusOptions.firstWhere((o) => o.$1 == f.status).$2,
                active: f.status != null,
                onTap: () async {
                  final v = await _choose('Status', statusOptions, f.status);
                  if (v != null) widget.onChanged(f.copy(status: v.$1));
                },
              ),
              if (widget.showKelurahan && scope != null)
                _Pill(
                  label: f.kelurahan == null ? 'Semua kelurahan' : 'Kel. ${f.kelurahan!.name}',
                  active: f.kelurahan != null,
                  clearable: true,
                  onTap: () async {
                    if (f.kelurahan != null) return widget.onChanged(f.copy(kelurahan: null));
                    final r = await showModalBottomSheet<Region>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => RegionPicker(title: 'Kelurahan', parent: scope.code),
                    );
                    if (r != null) widget.onChanged(f.copy(kelurahan: r));
                  },
                ),
              if (widget.showDate)
                _Pill(
                  label: f.range == null ? 'Semua tanggal' : '${fmtShort(f.range!.start)} – ${fmtShort(f.range!.end)}',
                  icon: Icons.date_range_rounded,
                  active: f.range != null,
                  clearable: true,
                  onTap: () async {
                    if (f.range != null) return widget.onChanged(f.copy(range: null));
                    final now = DateTime.now();
                    final r = await showDateRangePicker(
                      context: context,
                      firstDate: now.subtract(const Duration(days: 365)),
                      lastDate: now,
                      helpText: 'Pilih rentang tanggal',
                    );
                    if (r != null) widget.onChanged(f.copy(range: r));
                  },
                ),
              if (f.activeCount > 0)
                TextButton(
                  onPressed: () => widget.onChanged(ReportFilter(q: f.q)),
                  child: const Text('Reset'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.active, required this.onTap, this.icon, this.clearable = false});
  final String label;
  final bool active, clearable;
  final VoidCallback onTap;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: Semantics(
      button: true,
      label: 'Filter: $label${active ? (clearable ? ', aktif. Ketuk untuk menghapus' : ', aktif. Ketuk untuk mengubah') : ''}',
      excludeSemantics: true,
      child: Material(
        color: active ? context.brand.withValues(alpha: 0.12) : context.surface,
        shape: StadiumBorder(side: BorderSide(color: active ? context.brand : context.hairline)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[Icon(icon, size: 16, color: active ? context.brand : context.ink2), const SizedBox(width: 6)],
                Text(
                  label,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: active ? context.brand : context.ink),
                ),
                const SizedBox(width: 4),
                Icon(active && clearable ? Icons.close_rounded : Icons.expand_more_rounded, size: 18, color: active ? context.brand : context.ink2),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
