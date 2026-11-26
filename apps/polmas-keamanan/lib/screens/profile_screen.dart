import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';
import '../widgets/ui.dart';

/// Profil (mockup): avatar + nama (ubah), peran, label "HP ini menerima SOS" + kecamatan, kinerja 30 hari,
/// Penugasan (dari Nomor Darurat, dikunci), Pengaturan, Bantuan, Tentang, Keluar.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map? _stats;
  int _version = -1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final v = AppScope.of(context).dataVersion;
    if (v != _version) {
      _version = v;
      _loadStats();
    }
  }

  Future<void> _loadStats() async {
    try {
      final s = await AppScope.read(context).api.get('/me/stats', {'days': '30'}) as Map;
      if (mounted) setState(() => _stats = s);
    } catch (_) {}
  }

  String _initials(String name) {
    final parts = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    // Lewati pangkat di depan nama (Aiptu, Bripka, …) supaya inisial = nama orangnya.
    const ranks = {'aiptu', 'aipda', 'bripka', 'brigpol', 'briptu', 'bripda', 'ipda', 'iptu', 'akp', 'kompol', 'pak', 'bu'};
    final p = parts.length > 2 && ranks.contains(parts.first.toLowerCase()) ? parts.sublist(1) : parts;
    return (p.first[0] + (p.length > 1 ? p[1][0] : '')).toUpperCase();
  }

  Future<void> _editName(Me me) async {
    final c = TextEditingController(text: me.name);
    final name = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ubah nama', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: context.ink)),
            const SizedBox(height: 4),
            Text('Nama ini terlihat oleh pelapor saat Anda menanggapi.', style: TextStyle(fontSize: 13, color: context.ink2)),
            const SizedBox(height: 16),
            TextField(controller: c, autofocus: true, textCapitalization: TextCapitalization.words, maxLength: 100),
            const SizedBox(height: 8),
            PrimaryButton(label: 'Simpan', color: PK.navy, onPressed: () => Navigator.pop(context, c.text.trim())),
          ],
        ),
      ),
    );
    c.dispose();
    if (name == null || name.length < 2 || name == me.name || !mounted) return;
    try {
      await AppScope.read(context).updateName(name);
      if (mounted) showToast(context, 'Nama diperbarui');
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message, error: true);
    }
  }

  Future<void> _pickRole(Me me) async {
    final r = await showModalBottomSheet<RoleInfo>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Pilih peran aktif', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: context.ink)),
            ),
            for (final r in me.roles)
              ListTile(
                leading: Icon(Icons.shield_outlined, color: context.brand),
                title: Text(r.label),
                subtitle: Text([?r.unit, if (r.kecamatan != null) 'Kec. ${r.kecamatan!.name}'].join(' · ')),
                trailing: r.id == me.roleId ? const Icon(Icons.check_circle_rounded, color: PK.green) : null,
                onTap: () => Navigator.pop(context, r),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (r == null || r.id == me.roleId || !mounted) return;
    try {
      await AppScope.read(context).switchRole(r.id);
      if (mounted) showToast(context, 'Peran aktif: ${r.label}');
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message, error: true);
    }
  }

  Future<void> _changePassword() async {
    final ok = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, showDragHandle: true, builder: (_) => const _PasswordSheet());
    if (ok == true && mounted) showToast(context, 'Kata sandi diganti. Perangkat lain perlu masuk ulang.');
  }

  Future<void> _simulate() async {
    final source = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (k, l) in const [('umkm', 'UMKM'), ('warga', 'Lingkungan'), ('kantor', 'Perkantoran'), ('sekolah', 'Pendidikan'), ('komunitas', 'Komunitas')])
              ListTile(leading: Icon(ecosystemIcon(k)), title: Text(l), onTap: () => Navigator.pop(context, k)),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    final state = AppScope.read(context);
    try {
      await state.api.post('/demo/sos', {'source': source});
      if (mounted) showToast(context, 'SOS simulasi dikirim. Tunggu panggilan masuk…');
      Future.delayed(const Duration(seconds: 1), state.pollNow);
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message, error: true);
    }
  }

  Future<void> _logout() async {
    final ok = await showConfirmDialog(
      context,
      icon: Icons.logout_rounded,
      title: 'Keluar dari aplikasi?',
      message: 'HP ini berhenti menerima SOS untuk nomor Anda sampai Anda masuk lagi.',
      confirmLabel: 'Keluar',
    );
    if (!ok || !mounted) return;
    await AppScope.read(context).logout();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final me = state.me!;
    final s = _stats;
    final eco = me.ecosystems;
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        NavyHeader(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 64),
          child: Column(
            children: [
              const SizedBox(
                height: 38,
                child: Center(child: Text('Profil', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
              ),
              const SizedBox(height: 10),
              Semantics(
                button: true,
                label: 'Ubah nama',
                child: GestureDetector(
                  onTap: () => _editName(me),
                  child: SizedBox(
                    width: 92,
                    height: 92,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 84,
                          height: 84,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(colors: [Color(0xFF1E3F8F), Color(0xFF123A94)]),
                            border: Border.all(color: PK.gold, width: 3),
                            boxShadow: const [BoxShadow(color: Color(0x2ED4A82A), spreadRadius: 7)],
                          ),
                          child: Text(_initials(me.name), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                        ),
                        Positioned(
                          right: 2,
                          bottom: 4,
                          child: Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: PK.gold,
                              shape: BoxShape.circle,
                              border: Border.all(color: PK.navyMid, width: 3),
                            ),
                            child: const Icon(Icons.edit_rounded, size: 13, color: PK.navy2),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(me.name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text(me.identity, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: PK.headerMute)),
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 6,
                runSpacing: 6,
                children: [
                  _Badge(
                    me.serverPush == false
                        ? 'Server belum mengirim push SOS'
                        : state.receivesSos
                        ? 'HP ini menerima SOS'
                        : 'Notifikasi SOS belum aktif',
                    on: state.receivesSos && me.serverPush != false,
                  ),
                  if (me.scope != null) _Badge('Kec. ${me.scope!.name}'),
                ],
              ),
            ],
          ),
        ),
        Transform.translate(
          offset: const Offset(0, -46),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
                  decoration: BoxDecoration(
                    color: context.surface,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [BoxShadow(color: Color(0x590B2A6F), blurRadius: 30, offset: Offset(0, 14), spreadRadius: -16)],
                  ),
                  child: Row(
                    children: [
                      _Stat(value: s == null ? '–' : '${s['handled']}', label: 'Ditangani'),
                      _Stat(value: s?['median_response_s'] == null ? '–' : '${minutes1(s!['median_response_s'] as num)}m', label: 'Respons', divider: true),
                      _Stat(value: s?['pct_resolved'] == null ? '–' : '${s!['pct_resolved']}%', label: 'Selesai', divider: true),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 2),
                  child: Text('Kinerja 30 hari terakhir', style: TextStyle(fontSize: 11, color: context.ink2)),
                ),
                SectionHead('Penugasan', trailing: Text('dari Nomor Darurat', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: context.ink2))),
                _List(
                  children: [
                    _Row(
                      icon: Icons.shield_outlined,
                      label: 'Peran',
                      value: me.roleLabel,
                      locked: me.roles.length < 2,
                      onTap: me.roles.length < 2 ? null : () => _pickRole(me),
                      trailingText: me.roles.length < 2 ? null : 'Ganti',
                    ),
                    _Row(
                      icon: Icons.location_on_outlined,
                      label: 'Wilayah',
                      value: me.scope != null ? 'Kec. ${me.scope!.name}' : (me.unit ?? 'Laporan yang memanggil nomor Anda'),
                      locked: true,
                    ),
                    _Row(
                      icon: Icons.layers_outlined,
                      label: 'Ekosistem yang dilayani',
                      valueWidget: eco.isEmpty
                          ? Text('Belum ada', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.ink))
                          : Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [for (final e in eco.take(3)) EcoChip(label: e.label, app: e.app), if (eco.length > 3) EcoChip(label: '+${eco.length - 3}')],
                              ),
                            ),
                    ),
                    _Row(icon: Icons.phone_outlined, label: 'Nomor HP (login)', value: fmtPhone(me.phone), locked: true),
                  ],
                ),
                const SectionHead('Pengaturan'),
                _List(
                  children: [
                    _Row(
                      icon: Icons.campaign_outlined,
                      iconBg: const Color(0xFFFEE4E2),
                      iconFg: PK.red,
                      value: 'Notifikasi SOS',
                      sub: 'Sirene & getar saat SOS masuk',
                      toggle: state.notifSound,
                      onToggle: state.setNotifSound,
                    ),
                    _Row(
                      icon: Icons.dark_mode_outlined,
                      value: 'Tema gelap',
                      toggle: state.themeMode == ThemeMode.dark || (state.themeMode == ThemeMode.system && context.isDark),
                      onToggle: (v) => state.setTheme(v ? ThemeMode.dark : ThemeMode.light),
                    ),
                    _Row(icon: Icons.key_outlined, value: 'Ubah kata sandi', onTap: _changePassword),
                    _Row(
                      icon: Icons.phone_android_outlined,
                      value: 'Perangkat terdaftar',
                      sub: me.serverPush == false
                          ? 'Server belum dikonfigurasi push (SOS hanya muncul saat app dibuka)'
                          : state.receivesSos
                          ? 'HP ini aktif menerima SOS'
                          : 'Notifikasi belum aktif di HP ini',
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const _DevicesScreen())),
                    ),
                    if (me.isDemo) _Row(icon: Icons.science_outlined, value: 'Simulasi SOS masuk', onTap: _simulate),
                  ],
                ),
                const SizedBox(height: 10),
                _List(
                  children: [
                    _Row(
                      icon: Icons.help_outline_rounded,
                      value: 'Bantuan & kontak admin',
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const _HelpScreen())),
                    ),
                    _Row(
                      icon: Icons.info_outline_rounded,
                      value: 'Tentang aplikasi',
                      trailingText: 'v2.0',
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const _AboutScreen())),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Material(
                  color: context.isDark ? const Color(0x22D92D20) : const Color(0xFFFFF5F4),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Color(0xFFFBC8C3), width: 1.5)),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: _logout,
                    child: SizedBox(
                      height: 48,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.logout_rounded, size: 19, color: context.dangerText),
                          const SizedBox(width: 8),
                          Text('Keluar', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: context.dangerText)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Center(child: Text('Polmas Digital v2.0 · Didukung SiagaSOS', style: TextStyle(fontSize: 11, color: context.ink2))),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, {this.on = false});
  final String text;
  final bool on;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: on ? const Color(0x2E12B76A) : Colors.white.withValues(alpha: 0.1),
      border: Border.all(color: on ? const Color(0x6612B76A) : Colors.white.withValues(alpha: 0.16)),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (on) ...[
          Container(width: 7, height: 7, decoration: const BoxDecoration(color: PK.green, shape: BoxShape.circle)),
          const SizedBox(width: 5),
        ],
        Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: on ? const Color(0xFFA6F4C5) : Colors.white)),
      ],
    ),
  );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.divider = false});
  final String value, label;
  final bool divider;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      decoration: BoxDecoration(border: divider ? Border(left: BorderSide(color: context.isDark ? context.hairline : const Color(0xFFEEF2F8))) : null),
      child: Column(
        children: [
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: context.ink, fontFeatures: const [FontFeature.tabularFigures()])),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: context.ink2)),
        ],
      ),
    ),
  );
}

class _List extends StatelessWidget {
  const _List({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
    decoration: BoxDecoration(
      color: context.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: context.isDark ? context.hairline : const Color(0xFFE8EDF5)),
    ),
    child: Column(
      children: [
        for (final (i, c) in children.indexed)
          DecoratedBox(
            decoration: BoxDecoration(
              border: i == children.length - 1 ? null : Border(bottom: BorderSide(color: context.isDark ? context.hairline : const Color(0xFFF1F4F9))),
            ),
            child: c,
          ),
      ],
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    this.label,
    this.value,
    this.valueWidget,
    this.sub,
    this.locked = false,
    this.onTap,
    this.toggle,
    this.onToggle,
    this.trailingText,
    this.iconBg,
    this.iconFg,
  });
  final IconData icon;
  final String? label, value, sub, trailingText;
  final Widget? valueWidget;
  final bool locked;
  final VoidCallback? onTap;
  final bool? toggle;
  final ValueChanged<bool>? onToggle;
  final Color? iconBg, iconFg;

  @override
  Widget build(BuildContext context) {
    final tap = onTap ?? (toggle != null ? () => onToggle!(!toggle!) : null);
    return InkWell(
      onTap: tap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: iconBg ?? (context.isDark ? context.hairline : const Color(0xFFEEF2FB)), borderRadius: BorderRadius.circular(11)),
              child: Icon(icon, size: 17, color: iconFg ?? context.brand),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (label != null) Text(label!, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: context.ink2)),
                  if (value != null) Text(value!, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.ink)),
                  ?valueWidget,
                  if (sub != null) Text(sub!, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: context.ink2)),
                ],
              ),
            ),
            if (toggle != null)
              Switch(value: toggle!, onChanged: onToggle, activeTrackColor: PK.green)
            else if (locked)
              const Icon(Icons.lock_outline_rounded, size: 16, color: Color(0xFFA0AEC4))
            else if (trailingText != null)
              Text(trailingText!, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: onTap != null && label != null ? context.brand : context.ink2))
            else if (onTap != null)
              const Icon(Icons.chevron_right_rounded, size: 20, color: Color(0xFFA0AEC4)),
          ],
        ),
      ),
    );
  }
}

class _PasswordSheet extends StatefulWidget {
  const _PasswordSheet();
  @override
  State<_PasswordSheet> createState() => _PasswordSheetState();
}

class _PasswordSheetState extends State<_PasswordSheet> {
  final _cur = TextEditingController(), _new = TextEditingController(), _rep = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _cur.dispose();
    _new.dispose();
    _rep.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_new.text.length < 8) return setState(() => _error = 'Kata sandi baru minimal 8 karakter.');
    if (_new.text != _rep.text) return setState(() => _error = 'Ulangi kata sandi baru belum sama.');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AppScope.read(context).changePassword(_cur.text, _new.text);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(TextEditingController c, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(controller: c, obscureText: true, decoration: InputDecoration(labelText: label)),
  );

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Ubah kata sandi', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: context.ink)),
        const SizedBox(height: 4),
        Text('Perangkat lain yang memakai nomor ini akan diminta masuk ulang.', style: TextStyle(fontSize: 13, color: context.ink2)),
        const SizedBox(height: 16),
        _field(_cur, 'Kata sandi sekarang'),
        _field(_new, 'Kata sandi baru (min. 8 karakter)'),
        _field(_rep, 'Ulangi kata sandi baru'),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(_error!, style: TextStyle(fontSize: 13, color: context.dangerText)),
          ),
        PrimaryButton(label: 'Simpan', color: PK.navy, loading: _busy, onPressed: _save),
      ],
    ),
  );
}

/// Perangkat yang menerima push SOS untuk nomor ini; perangkat lain bisa dilepas.
class _DevicesScreen extends StatefulWidget {
  const _DevicesScreen();
  @override
  State<_DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<_DevicesScreen> {
  List<Map>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await AppScope.read(context).api.get('/me/devices') as Map;
      if (mounted) setState(() => _items = (r['items'] as List).cast<Map>());
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _remove(Map d) async {
    final ok = await showConfirmDialog(
      context,
      icon: Icons.phone_android_outlined,
      title: 'Lepas perangkat ini?',
      message: '${d['device_name'] ?? 'Perangkat'} tidak akan menerima SOS lagi untuk nomor Anda.',
      confirmLabel: 'Lepas',
    );
    if (!ok || !mounted) return;
    try {
      await AppScope.read(context).api.post('/me/devices/${d['id']}/remove');
      await _load();
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tail = AppScope.of(context).deviceTokenTail;
    return Scaffold(
      backgroundColor: context.pageBg,
      appBar: AppBar(title: const Text('Perangkat terdaftar')),
      body: _items == null
          ? (_error != null ? ErrorState(message: _error!, onRetry: _load) : const Center(child: CircularProgressIndicator()))
          : _items!.isEmpty
          ? const EmptyState(icon: Icons.phone_android_outlined, title: 'Belum ada perangkat', body: 'Izinkan notifikasi agar HP ini menerima SOS.')
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _List(
                  children: [
                    for (final d in _items!)
                      _Row(
                        icon: d['platform'] == 'ios' ? Icons.phone_iphone_rounded : Icons.phone_android_rounded,
                        value: d['device_name'] as String? ?? (d['platform'] == 'ios' ? 'iPhone' : 'Android'),
                        sub: d['token_tail'] == tail
                            ? 'Perangkat ini · aktif'
                            : 'Terakhir aktif ${fmtRelative(DateTime.parse(d['updated_at'] as String).toLocal())}',
                        trailingText: d['token_tail'] == tail ? null : 'Lepas',
                        label: null,
                        onTap: d['token_tail'] == tail ? null : () => _remove(d),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text('SOS yang memanggil nomor Anda dikirim ke semua perangkat di atas.', style: TextStyle(fontSize: 12, color: context.ink2)),
              ],
            ),
    );
  }
}

class _HelpScreen extends StatelessWidget {
  const _HelpScreen();
  @override
  Widget build(BuildContext context) {
    const faq = [
      (
        'Siapa yang bisa masuk?',
        'Nomor yang dimasukkan di menu Nomor Darurat aplikasi toko, kantor, sekolah, atau warga (mis. pemilik toko, satpam, ketua RT/RW, Bhabinkamtibmas). Login pertama: buat password sendiri.',
      ),
      (
        'Kapan panggilan SOS muncul?',
        'Saat kios/warga yang mencantumkan nomor Anda menekan SOS. Bhabinkamtibmas juga menerima SOS di kecamatannya. Biarkan aplikasi terbuka agar panggilan langsung muncul.',
      ),
      (
        'Apa yang terjadi saat saya menanggapi?',
        'Status (Diterima, Diverifikasi, Ditangani, Selesai) dan catatan Anda langsung terlihat oleh pelapor di aplikasinya.',
      ),
      ('Nomor saya tidak terdaftar?', 'Minta pemilik toko / warga yang Anda jaga menambahkan nomor Anda di menu Nomor Darurat aplikasinya, lalu coba lagi.'),
      ('HP dipakai orang lain?', 'Di layar masuk, ketuk "Lupakan perangkat ini" agar nomor dan password tidak tersimpan lagi.'),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Bantuan')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          for (final (q, a) in faq)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppCard(
                padding: EdgeInsets.zero,
                child: ExpansionTile(
                  shape: const Border(),
                  title: Text(q, style: Theme.of(context).textTheme.titleSmall),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [Text(a, style: Theme.of(context).textTheme.bodyMedium)],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AboutScreen extends StatelessWidget {
  const _AboutScreen();
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Tentang')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Polmas Keamanan', style: t.headlineSmall),
          Text('Versi 2.0 · Polmas Digital', style: t.bodySmall),
          const SizedBox(height: 12),
          Text(
            'Aplikasi penerima SOS dan laporan dari aplikasi Polmas Digital (Warga, Kantor, UMKM, Sekolah, Komunitas). '
            'Semua komunikasi lewat internet, tanpa WhatsApp/SMS.',
            style: t.bodyLarge,
          ),
          const SizedBox(height: 16),
          Text('Privasi', style: t.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Lokasi dan bukti hanya untuk penerima yang berwenang. Identitas pelapor disamarkan bagi pengguna yang tidak dipanggil. '
            'Setiap akses bukti dan perubahan status tercatat.',
            style: t.bodyMedium,
          ),
          const SizedBox(height: 16),
          Text('Server', style: t.titleMedium),
          Text(apiUrl, style: t.bodySmall),
          const SizedBox(height: 8),
          Text('Peta © OpenStreetMap', style: t.bodySmall),
        ],
      ),
    );
  }
}
