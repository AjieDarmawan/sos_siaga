import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';
import '../widgets/search_filter.dart';

/// Profil: avatar inisial di atas pita gelombang merah, nama, nomor, peran (ketuk untuk beralih, FR-12), wilayah,
/// pengaturan (Notifikasi, Mode gelap, Kurangi gerakan), Bantuan, Tentang, dan Keluar.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _busy = false;

  String _initials(String name) {
    final parts = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    // Lewati pangkat umum di depan nama (Aiptu, Bripka, …) supaya inisial = nama orangnya.
    const ranks = {'aiptu', 'aipda', 'bripka', 'brigpol', 'briptu', 'bripda', 'ipda', 'iptu', 'akp', 'kompol', 'pak', 'bu'};
    final p = parts.length > 2 && ranks.contains(parts.first.toLowerCase()) ? parts.sublist(1) : parts;
    return (p.first[0] + (p.length > 1 ? p[1][0] : '')).toUpperCase();
  }

  Future<void> _editName(Me me) async {
    final c = TextEditingController(text: me.name);
    final name = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ubah nama', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('Nama ini terlihat oleh pelapor saat Anda menanggapi.', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            TextField(controller: c, autofocus: true, textCapitalization: TextCapitalization.words, maxLength: 100),
            const SizedBox(height: 8),
            PrimaryButton(label: 'Simpan', color: PK.red, onPressed: () => Navigator.pop(context, c.text.trim())),
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
    if (me.roles.length < 2) return;
    final r = await showModalBottomSheet<RoleInfo>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Pilih peran aktif', style: Theme.of(context).textTheme.titleLarge),
            ),
            for (final r in me.roles)
              ListTile(
                minTileHeight: 60,
                leading: Icon(_roleIcon(r.role), color: context.brand),
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
    setState(() => _busy = true);
    try {
      await AppScope.read(context).switchRole(r.id);
      if (mounted) showToast(context, 'Peran aktif: ${r.label}');
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _simulate() async {
    final source = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text('Simulasi SOS masuk', style: Theme.of(context).textTheme.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'SOS fiktif dari aplikasi sumber demo dengan nomor Anda sebagai Nomor Darurat. Layar panggilan muncul dalam ±5 detik.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            for (final (k, l) in const [
              ('umkm', 'Kios / UMKM (mis. commerceOS)'),
              ('warga', 'Warga (mis. tata-warga)'),
              ('kantor', 'Kantor'),
              ('sekolah', 'Sekolah'),
              ('komunitas', 'Komunitas'),
            ])
              ListTile(minTileHeight: 52, leading: Icon(sourceIcon(k)), title: Text(l), onTap: () => Navigator.pop(context, k)),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    final state = AppScope.read(context);
    try {
      await state.api.post('/demo/sos', {'source': source});
      if (mounted) showToast(context, 'SOS demo dikirim. Tunggu panggilan masuk…');
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
      message: 'Nomor dan password akan diingat di perangkat ini agar kamu bisa masuk lebih cepat.',
      confirmLabel: 'Keluar',
    );
    if (!ok || !mounted) return;
    // PolmasApp mengarahkan ke login (+ toast "Berhasil keluar") saat sesi selesai.
    await AppScope.read(context).logout();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final me = state.me!;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        top: false,
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            const PageHeader(title: 'Profil'),
            // pita gelombang merah di belakang avatar
            SizedBox(
              height: 128,
              child: Stack(
                alignment: Alignment.topCenter,
                children: [
                  Positioned(
                    top: 18,
                    child: Semantics(
                      label: 'Foto profil ${me.name}',
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 104,
                            height: 104,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFE53935), PK.redDark]),
                              border: Border.all(color: context.surface, width: 4),
                              boxShadow: const [BoxShadow(color: Color(0x33A80F15), blurRadius: 16, offset: Offset(0, 6))],
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              _initials(me.name),
                              style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w800, letterSpacing: 1),
                            ),
                          ),
                          Positioned(
                            right: -4,
                            bottom: 2,
                            child: Material(
                              color: context.surface,
                              shape: const CircleBorder(),
                              elevation: 3,
                              child: IconButton(
                                tooltip: 'Ubah nama',
                                onPressed: () => _editName(me),
                                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                                icon: Icon(Icons.edit_rounded, size: 20, color: context.ink),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Center(
              child: Text(
                me.name,
                textAlign: TextAlign.center,
                style: t.headlineSmall?.copyWith(fontSize: 26, fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(height: 2),
            Center(
              child: Text(fmtPhoneIntl(me.phone), style: t.bodyLarge?.copyWith(fontSize: 17, color: context.ink2)),
            ),
            const SizedBox(height: 10),
            Center(
              child: Semantics(
                button: me.roles.length > 1,
                label: 'Peran: ${me.roleLabel}${me.roles.length > 1 ? '. Ketuk untuk beralih peran' : ''}',
                excludeSemantics: true,
                child: Material(
                  color: PK.gold.withValues(alpha: context.isDark ? 0.25 : 0.18),
                  shape: const StadiumBorder(),
                  child: InkWell(
                    customBorder: const StadiumBorder(),
                    onTap: _busy ? null : () => _pickRole(me),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_roleIcon(me.roleKey), size: 18, color: const Color(0xFF8A5A00)),
                          const SizedBox(width: 6),
                          Text(
                            me.roleLabel,
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: context.isDark ? PK.gold : const Color(0xFF6B4500)),
                          ),
                          if (me.roles.length > 1) ...[
                            const SizedBox(width: 2),
                            Icon(Icons.expand_more_rounded, size: 18, color: context.isDark ? PK.gold : const Color(0xFF6B4500)),
                          ],
                          if (me.isDemo) ...[const SizedBox(width: 8), const DemoTag()],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (me.unit != null) ...[
              const SizedBox(height: 6),
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(me.unit!, textAlign: TextAlign.center, style: t.bodySmall),
                ),
              ),
            ],
            const SizedBox(height: 6),
            Center(
              // Wilayah & jabatan dari Nomor Darurat yang didaftarkan app klien (tidak diubah di sini).
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.badge_outlined, color: context.ink2, size: 20),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(me.identity, textAlign: TextAlign.center, style: t.bodyLarge?.copyWith(fontSize: 15)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _Group(
              children: [
                _SwitchRow(icon: Icons.notifications_none_rounded, label: 'Notifikasi', value: state.notifSound, onChanged: state.setNotifSound),
                _SwitchRow(
                  icon: Icons.dark_mode_outlined,
                  label: 'Mode gelap',
                  value: context.isDark,
                  onChanged: (v) => state.setTheme(v ? ThemeMode.dark : ThemeMode.light),
                ),
                _SwitchRow(icon: Icons.motion_photos_off_outlined, label: 'Kurangi gerakan', value: context.reduceMotion, onChanged: state.setReduceMotion),
              ],
            ),
            const SizedBox(height: 14),
            _Group(
              children: [
                if (me.isDemo) _NavRow(icon: Icons.campaign_outlined, label: 'Simulasi SOS masuk (demo)', onTap: _simulate),
                _NavRow(
                  icon: Icons.help_outline_rounded,
                  label: 'Bantuan',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const _HelpScreen())),
                ),
                _NavRow(
                  icon: Icons.info_outline_rounded,
                  label: 'Tentang',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const _AboutScreen())),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Semantics(
                button: true,
                label: 'Keluar',
                excludeSemantics: true,
                child: Material(
                  color: context.isDark ? PK.darkSurface : const Color(0xFFFFF5F5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(PK.rCard),
                    side: BorderSide(color: context.danger, width: 1.5),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(PK.rCard),
                    onTap: _logout,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                      child: Row(
                        children: [
                          Icon(Icons.logout_rounded, color: context.danger),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              'Keluar',
                              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: context.dangerText),
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded, color: context.danger),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

IconData _roleIcon(String role) => switch (role) {
  'bhabinkamtibmas' => Icons.local_police_rounded,
  'penerima' => Icons.security_rounded,
  'kantor' => Icons.business_rounded,
  'umkm' => Icons.storefront_rounded,
  'sekolah' => Icons.school_rounded,
  'komunitas' => Icons.diversity_3_rounded,
  _ => Icons.person_rounded,
};

class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (final (i, c) in children.indexed) ...[if (i > 0) Divider(indent: 56, color: context.hairline), c],
        ],
      ),
    ),
  );
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({required this.icon, required this.label, required this.value, required this.onChanged});
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: ListTile(
      minTileHeight: 58,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18),
      leading: Icon(icon, color: context.ink),
      title: Text(label, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontSize: 17)),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeThumbColor: Colors.white,
        activeTrackColor: context.danger,
        inactiveThumbColor: Colors.white,
        inactiveTrackColor: context.isDark ? PK.darkLine : const Color(0xFFDDE1E7),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      onTap: () => onChanged(!value),
    ),
  );
}

class _NavRow extends StatelessWidget {
  const _NavRow({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ListTile(
    minTileHeight: 58,
    contentPadding: const EdgeInsets.symmetric(horizontal: 18),
    leading: Icon(icon, color: context.ink),
    title: Text(label, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontSize: 17)),
    trailing: Icon(Icons.chevron_right_rounded, color: context.ink),
    onTap: onTap,
  );
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
          Text('Versi 0.1.0 · fase 1', style: t.bodySmall),
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
