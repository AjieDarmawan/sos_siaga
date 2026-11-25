import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/report_filters.dart';
import '../widgets/report_list.dart';
import '../widgets/search_filter.dart';

/// Riwayat (FR-18): segmen Saya (SOS yang memanggil nomor saya, laporan saya, yang saya tanggapi) dan Kecamatan,
/// kolom cari + tombol filter (jenis, status, kelurahan, tanggal), dikelompokkan per hari.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  ReportFilter _f = const ReportFilter();
  int _seg = 0;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context).me!.scope;
    return Scaffold(
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            const PageHeader(title: 'Riwayat'),
            // Tab Kecamatan hanya untuk yang punya wilayah tugas (Bhabinkamtibmas dari Nomor Darurat).
            if (scope != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _Segmented(labels: ['Saya', 'Kec. ${scope.name}'], index: _seg, onChanged: (i) => setState(() => _seg = i)),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: SearchFilterRow(value: _f, onChanged: (f) => setState(() => _f = f)),
            ),
            Expanded(
              child: IndexedStack(
                index: scope == null ? 0 : _seg,
                children: [
                  ReportList(
                    endpoint: '/history',
                    query: {..._f.toQuery(), 'scope': 'me'},
                    groupByDay: true,
                    emptyTitle: 'Belum ada riwayat',
                    emptyBody: 'SOS yang memanggil nomor Anda dan laporan yang Anda tanggapi akan tercatat di sini.',
                  ),
                  ReportList(
                    endpoint: '/history',
                    query: {..._f.toQuery(), 'scope': 'kecamatan'},
                    groupByDay: true,
                    emptyTitle: 'Belum ada riwayat wilayah',
                    emptyBody: scope == null ? 'Konfirmasi wilayah Anda di Profil untuk melihat laporan kecamatan.' : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Segmen dua pilihan: lintasan abu, pilihan aktif pil merah berteks putih.
class _Segmented extends StatelessWidget {
  const _Segmented({required this.labels, required this.index, required this.onChanged});
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => Container(
    height: 48,
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(color: context.isDark ? PK.darkSurface : const Color(0xFFF1F3F6), borderRadius: BorderRadius.circular(14)),
    child: Row(
      children: [
        for (final (i, l) in labels.indexed)
          Expanded(
            child: Semantics(
              button: true,
              selected: i == index,
              label: l,
              excludeSemantics: true,
              child: GestureDetector(
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: context.reduceMotion ? Duration.zero : PK.tab,
                  curve: Curves.easeInOut,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == index ? PK.red : Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: i == index ? const [BoxShadow(color: Color(0x33D71920), blurRadius: 8, offset: Offset(0, 3))] : null,
                  ),
                  child: Text(
                    l,
                    style: TextStyle(fontSize: 16, fontWeight: i == index ? FontWeight.w700 : FontWeight.w500, color: i == index ? Colors.white : context.ink),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
