import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../theme/tokens.dart';
import 'analytics_screen.dart';
import 'dashboard_screen.dart';
import 'profile_screen.dart';
import 'reports_screen.dart';

/// Navigasi bawah 4 tab (mockup): Beranda, Laporan, Analitik, Profil. Tanpa tombol SOS: petugas menerima SOS,
/// tidak mengirim. Badge Laporan = laporan belum ditanggapi (dari /inbox).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _i = 0;
  final _visited = <int>{0};

  @override
  void initState() {
    super.initState();
    // Lokasi HP hanya untuk jarak ke lokasi laporan; tidak menentukan wilayah.
    WidgetsBinding.instance.addPostFrameCallback((_) => AppScope.read(context).refreshPosition());
  }

  void _go(int i) => setState(() => _visited.add(_i = i));

  /// Dari Beranda: buka tab Laporan, opsional dengan filter status (mis. "baru" dari lonceng).
  void _openReports([String? status]) {
    AppScope.read(context).pendingReportStatus = status;
    _go(1);
  }

  static const _items = [
    (Icons.home_outlined, Icons.home_rounded, 'Beranda'),
    (Icons.assignment_turned_in_outlined, Icons.assignment_turned_in_rounded, 'Laporan'),
    (Icons.bar_chart_rounded, Icons.bar_chart_rounded, 'Analitik'),
    (Icons.person_outline_rounded, Icons.person_rounded, 'Profil'),
  ];

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final pages = [
      DashboardScreen(onOpenReports: _openReports),
      ReportsScreen(active: _i == 1),
      const AnalyticsScreen(),
      const ProfileScreen(),
    ];
    return Scaffold(
      backgroundColor: context.pageBg,
      body: Column(
        children: [
          if (!state.online) const _OfflineBanner(),
          Expanded(
            child: IndexedStack(
              index: _i,
              children: [for (final (i, p) in pages.indexed) _visited.contains(i) ? p : const SizedBox.shrink()],
            ),
          ),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: context.surface,
          border: Border(top: BorderSide(color: context.hairline)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 64,
            child: Row(
              children: [
                for (final (i, (off, on, label)) in _items.indexed)
                  Expanded(
                    child: _NavItem(
                      icon: _i == i ? on : off,
                      label: label,
                      selected: _i == i,
                      badge: i == 1 ? state.openReports : 0,
                      onTap: () => _go(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.icon, required this.label, required this.selected, required this.onTap, this.badge = 0});
  final IconData icon;
  final String label;
  final bool selected;
  final int badge;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final color = selected ? context.brand : const Color(0xFF94A3B8);
    return Semantics(
      button: true,
      selected: selected,
      label: badge > 0 ? '$label, $badge belum ditanggapi' : label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            if (selected)
              Container(
                width: 28,
                height: 3,
                decoration: const BoxDecoration(color: PK.gold, borderRadius: BorderRadius.vertical(bottom: Radius.circular(3))),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(
                children: [
                  Badge(
                    isLabelVisible: badge > 0,
                    backgroundColor: PK.red,
                    offset: const Offset(10, -4),
                    label: Text(badge > 99 ? '99+' : '$badge', style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800)),
                    child: Icon(icon, size: 22, color: color),
                  ),
                  const SizedBox(height: 4),
                  Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      width: double.infinity,
      color: PK.gold,
      padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 6, 16, 6),
      child: const Row(
        children: [
          Icon(Icons.cloud_off_rounded, size: 18, color: PK.text),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Koneksi terputus. Mencoba menyambung ulang…',
              style: TextStyle(color: PK.text, fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ),
        ],
      ),
    ),
  );
}
