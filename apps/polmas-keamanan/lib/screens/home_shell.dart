import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../theme/tokens.dart';
import 'analytics_screen.dart';
import 'dashboard_screen.dart';
import 'history_screen.dart';
import 'notifications_screen.dart';
import 'profile_screen.dart';
import 'reports_screen.dart';

/// Navigasi bawah 5 item: Beranda, Laporan, Riwayat, Analisa, Profil. Notifikasi lewat lonceng di header.
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
    // Lokasi HP hanya untuk jarak ke SOS; tidak menentukan wilayah.
    WidgetsBinding.instance.addPostFrameCallback((_) => AppScope.read(context).refreshPosition());
  }

  static const _items = [
    (Icons.home_outlined, Icons.home_rounded, 'Beranda'),
    (Icons.assignment_outlined, Icons.assignment_rounded, 'Laporan'),
    (Icons.history_rounded, Icons.history_rounded, 'Riwayat'),
    (Icons.insights_outlined, Icons.insights_rounded, 'Analisa'),
    (Icons.person_outline_rounded, Icons.person_rounded, 'Profil'),
  ];

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final pages = [
      DashboardScreen(onOpenTab: (i) => setState(() => _visited.add(_i = i))),
      const ReportsScreen(),
      const HistoryScreen(),
      const AnalyticsScreen(),
      const ProfileScreen(),
    ];
    return Scaffold(
      body: Column(
        children: [
          if (!state.online) const _OfflineBanner(),
          Expanded(
            child: IndexedStack(
              index: _i,
              children: [
                // Layar dibuat saat pertama dibuka supaya tidak memuat semua data sekaligus.
                for (final (i, p) in pages.indexed) _visited.contains(i) ? p : const SizedBox.shrink(),
              ],
            ),
          ),
        ],
      ),
      // Item aktif merah (ikon terisi + label tebal), tanpa pil indikator.
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          labelTextStyle: WidgetStateProperty.resolveWith(
            (s) => TextStyle(
              fontSize: 13,
              fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
              color: s.contains(WidgetState.selected) ? context.danger : context.ink2,
            ),
          ),
          iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(size: 26, color: s.contains(WidgetState.selected) ? context.danger : context.ink2)),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: context.hairline)),
          ),
          child: NavigationBar(
            selectedIndex: _i,
            height: 68,
            backgroundColor: context.surface,
            indicatorColor: Colors.transparent,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            onDestinationSelected: (i) => setState(() => _visited.add(_i = i)),
            destinations: [for (final (o, s, l) in _items) NavigationDestination(icon: Icon(o), selectedIcon: Icon(s), label: l)],
          ),
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

/// Lonceng notifikasi dengan tanda belum dibaca.
class NotifBell extends StatelessWidget {
  const NotifBell({super.key, this.light = false});
  final bool light;
  @override
  Widget build(BuildContext context) {
    final n = AppScope.of(context).unread;
    return Semantics(
      button: true,
      label: n > 0 ? 'Notifikasi, $n belum dibaca' : 'Notifikasi',
      excludeSemantics: true,
      child: IconButton(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen())),
        icon: Badge(
          isLabelVisible: n > 0,
          backgroundColor: PK.red,
          // Di header navy cukup titik merah (gaya mockup); di tempat lain angka.
          label: light ? null : Text(n > 99 ? '99+' : '$n'),
          smallSize: 10,
          child: Icon(Icons.notifications_rounded, size: light ? 28 : 24, color: light ? Colors.white : context.ink),
        ),
      ),
    );
  }
}
