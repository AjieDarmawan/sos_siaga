import 'dart:async';

import 'package:flutter/material.dart';

import '../screens/home_shell.dart';
import '../theme/tokens.dart';
import 'report_filters.dart';

/// Judul layar besar (gaya mockup): "Riwayat", "Laporan", … + subjudul opsional + aksi kanan + lonceng.
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.subtitle, this.actions = const []});
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(title, style: t.headlineSmall?.copyWith(fontSize: 30, fontWeight: FontWeight.w800)),
                ),
                if (subtitle != null) Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodySmall),
              ],
            ),
          ),
          ...actions,
          const NotifBell(),
        ],
      ),
    );
  }
}

/// Kolom cari abu membulat + tombol filter (lencana jumlah filter aktif). Filter dibuka di lembar bawah.
class SearchFilterRow extends StatefulWidget {
  const SearchFilterRow({super.key, required this.value, required this.onChanged, this.showDate = true, this.hint = 'Cari laporan...'});
  final ReportFilter value;
  final ValueChanged<ReportFilter> onChanged;
  final bool showDate;
  final String hint;
  @override
  State<SearchFilterRow> createState() => _SearchFilterRowState();
}

class _SearchFilterRowState extends State<SearchFilterRow> {
  late final _q = TextEditingController(text: widget.value.q);
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  Future<void> _openFilter() async {
    var draft = widget.value;
    final applied = await showModalBottomSheet<ReportFilter>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Filter laporan', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              FilterBar(value: draft, showSearch: false, showDate: widget.showDate, onChanged: (f) => set(() => draft = f)),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, draft),
                  style: FilledButton.styleFrom(
                    backgroundColor: PK.red,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PK.rButton)),
                  ),
                  child: const Text('Terapkan', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (applied != null) widget.onChanged(applied.copy(q: _q.text));
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.value.activeCount;
    final fill = context.isDark ? PK.darkSurface : const Color(0xFFF1F3F6);
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _q,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: widget.hint,
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: fill,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: context.brand, width: 2),
              ),
              suffixIcon: _q.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Hapus pencarian',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _q.clear();
                        setState(() {});
                        widget.onChanged(widget.value.copy(q: ''));
                      },
                    ),
            ),
            onChanged: (v) {
              setState(() {});
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 400), () => widget.onChanged(widget.value.copy(q: v)));
            },
          ),
        ),
        const SizedBox(width: 10),
        Material(
          color: active > 0 ? PK.red.withValues(alpha: 0.1) : context.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: active > 0 ? PK.red : context.hairline),
          ),
          child: IconButton(
            tooltip: active > 0 ? 'Filter ($active aktif)' : 'Filter',
            onPressed: _openFilter,
            constraints: const BoxConstraints(minWidth: 50, minHeight: 50),
            icon: Badge(
              isLabelVisible: active > 0,
              backgroundColor: PK.red,
              label: Text('$active'),
              child: Icon(Icons.filter_alt_rounded, color: active > 0 ? PK.red : context.ink),
            ),
          ),
        ),
      ],
    );
  }
}
