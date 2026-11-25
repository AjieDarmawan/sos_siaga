import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../core/format.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import 'incident_screen.dart';
import 'news_screen.dart';

/// Riwayat notifikasi (FR-05): SOS & laporan baru di wilayah, tanggapan petugas, dan berita, dengan tanda belum dibaca.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await AppScope.read(context).api.get('/notifications') as Map;
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

  Future<void> _readAll() async {
    try {
      await AppScope.read(context).markAllRead();
      if (!mounted) return;
      setState(() => _items = _items?.map((e) => {...e, 'unread': false}).toList());
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message, error: true);
    }
  }

  Future<void> _open(Map n) async {
    if (n['report_id'] != null) {
      await openIncident(context, n['report_id'] as String);
    } else if (n['news_id'] != null) {
      // berita dibuka dari tab Berita; di sini cukup muat daftar dan cari
      final r = await AppScope.read(context).api.get('/news') as Map;
      final item = (r['items'] as List).cast<Map>().where((e) => e['id'] == n['news_id']).firstOrNull;
      if (item != null && mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => NewsScreen(news: item)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final unread = _items?.where((e) => e['unread'] == true).length ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifikasi'),
        actions: [
          if (unread > 0) TextButton(onPressed: _readAll, child: const Text('Tandai dibaca')),
          const SizedBox(width: 4),
        ],
      ),
      body: _error != null && _items == null
          ? ErrorState(message: _error!, onRetry: _load)
          : _items == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _items!.isEmpty
                  ? ListView(
                      children: const [
                        EmptyState(
                          icon: Icons.notifications_none_rounded,
                          title: 'Belum ada notifikasi',
                          body: 'SOS, laporan, dan tanggapan di wilayah Anda akan muncul di sini.',
                        ),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: _items!.length,
                      separatorBuilder: (_, _) => const Divider(indent: 72),
                      itemBuilder: (_, i) => _Tile(n: _items![i], onTap: () => _open(_items![i])),
                    ),
            ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.n, required this.onTap});
  final Map n;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (n['type']) {
      'sos' => (Icons.sos_rounded, context.danger),
      'laporan' => (Icons.assignment_rounded, context.brand),
      'tanggapan' => (Icons.local_police_rounded, PK.gold),
      _ => (Icons.newspaper_rounded, PK.green),
    };
    final unread = n['unread'] == true;
    final t = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: '${unread ? 'Belum dibaca. ' : ''}${n['title']}. ${n['body'] ?? ''}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          color: unread ? context.brand.withValues(alpha: 0.05) : null,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.13), shape: BoxShape.circle),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(n['title'] as String, style: t.titleSmall?.copyWith(fontWeight: unread ? FontWeight.w800 : FontWeight.w600)),
                    if ((n['body'] as String?)?.isNotEmpty == true)
                      Text(
                        n['body'] as String,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.bodyMedium?.copyWith(color: context.ink2),
                      ),
                    const SizedBox(height: 2),
                    Text(fmtRelative(DateTime.parse(n['at'] as String).toLocal()), style: t.bodySmall),
                  ],
                ),
              ),
              if (unread)
                Container(
                  margin: const EdgeInsets.only(top: 6, left: 8),
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(color: PK.red, shape: BoxShape.circle),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
