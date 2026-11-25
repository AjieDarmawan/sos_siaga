import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../core/api.dart';
import '../core/app_state.dart';
import '../core/models.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/map_widgets.dart';
import 'home_shell.dart';

/// Konfirmasi wilayah (FR-03): setengah atas peta dengan penanda berdenyut di posisi pengguna, setengah bawah kartu
/// Provinsi → Kelurahan yang terisi otomatis dari GPS (bertahap, 150 ms per kolom) dan bisa diubah. Izin lokasi
/// ditolak → pilih manual.
class AreaScreen extends StatefulWidget {
  const AreaScreen({super.key, this.fromLogin = false});
  final bool fromLogin;
  @override
  State<AreaScreen> createState() => _AreaScreenState();
}

enum _Gps { locating, found, denied, failed }

class _AreaScreenState extends State<AreaScreen> with TickerProviderStateMixin {
  final _map = MapController();
  final _mapReady = Completer<void>();
  Area _area = Area();
  int _visible = 4; // jumlah kolom yang sudah "terisi" (untuk animasi bertahap)
  LatLng? _pos;
  _Gps _gps = _Gps.locating;
  bool _saving = false;
  String? _note;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final me = AppScope.read(context).me!;
      if (me.area.complete) setState(() => _area = me.area);
      _locate();
    });
  }

  Future<void> _locate() async {
    setState(() {
      _gps = _Gps.locating;
      _note = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) throw const _Denied('GPS perangkat mati. Nyalakan lokasi atau pilih wilayah manual.');
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        throw const _Denied('Izin lokasi ditolak. Pilih wilayah Anda secara manual.');
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
      );
      if (!mounted) return;
      final pos = LatLng(p.latitude, p.longitude);
      setState(() {
        _pos = pos;
        _gps = _Gps.found;
      });
      await _mapReady.future;
      if (!mounted) return;
      unawaited(animateMapTo(_map, this, pos, 15, reduce: context.reduceMotion));
      final r = await AppScope.read(context).api.get('/me/area', {'lat': '${p.latitude}', 'lng': '${p.longitude}'}) as Map;
      final s = r['suggestion'];
      if (!mounted) return;
      if (s is Map && s['district'] != null) {
        await _fillSequential(Area.from(s));
      } else {
        setState(() => _note = 'Wilayah belum bisa dibaca dari lokasi. Periksa atau pilih manual.');
      }
    } on _Denied catch (e) {
      if (mounted) {
        setState(() {
          _gps = _Gps.denied;
          _note = e.message;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _gps = _Gps.failed;
          _note = e.isNetwork ? e.message : 'Wilayah belum bisa dibaca otomatis. Pilih manual.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _gps = _Gps.failed;
          _note = 'Lokasi belum didapat. Coba lagi atau pilih manual.';
        });
      }
    }
  }

  /// Kolom terisi berurutan dari atas ke bawah (150 ms per kolom).
  Future<void> _fillSequential(Area a) async {
    final reduce = context.reduceMotion;
    setState(() {
      _area = a;
      _visible = reduce ? 4 : 0;
    });
    for (var i = 1; i <= 4 && !reduce; i++) {
      await Future.delayed(PK.fieldFill);
      if (!mounted) return;
      setState(() => _visible = i);
    }
  }

  Future<void> _pick(int level) async {
    final parent = switch (level) {
      0 => null,
      1 => _area.province?.code,
      2 => _area.regency?.code,
      _ => _area.district?.code,
    };
    if (level > 0 && parent == null) return;
    final title = ['Provinsi', 'Kabupaten/Kota', 'Kecamatan', 'Kelurahan/Desa'][level];
    final picked = await showModalBottomSheet<Region>(
      context: context,
      isScrollControlled: true,
      builder: (_) => RegionPicker(title: title, parent: parent),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _visible = 4;
      switch (level) {
        case 0:
          _area = Area(province: picked);
        case 1:
          _area = Area(province: _area.province, regency: picked);
        case 2:
          _area = Area(province: _area.province, regency: _area.regency, district: picked);
        default:
          _area.village = picked;
      }
    });
  }

  void _useDemo() {
    _fillSequential(
      Area(
        province: const Region('32', 'Jawa Barat'),
        regency: const Region('32.71', 'Kota Bogor'),
        district: const Region('32.71.03', 'Bogor Tengah'),
        village: const Region('32.71.03.1002', 'Paledang'),
      ),
    );
    if (_mapReady.isCompleted) animateMapTo(_map, this, const LatLng(-6.5971, 106.7973), 14.5, reduce: context.reduceMotion);
  }

  Future<void> _confirm() async {
    setState(() => _saving = true);
    final state = AppScope.read(context);
    try {
      await state.confirmArea(_area, lat: _pos?.latitude, lng: _pos?.longitude);
      if (!mounted) return;
      if (widget.fromLogin) {
        Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const HomeShell()), (_) => false);
      } else {
        showToast(context, 'Wilayah diperbarui');
        Navigator.of(context).pop();
      }
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = AppScope.of(context).me!;
    final t = Theme.of(context).textTheme;
    final h = MediaQuery.of(context).size.height;
    final officerScope = me.roles.where((r) => r.id == me.roleId).firstOrNull?.kecamatan;
    final fields = [
      ('Provinsi', _area.province, Icons.location_on_outlined),
      ('Kota', _area.regency, Icons.location_city_rounded),
      ('Kecamatan', _area.district, Icons.layers_outlined),
      ('Kelurahan', _area.village, Icons.home_outlined),
    ];
    return Scaffold(
      backgroundColor: context.pageBg,
      body: Stack(
        children: [
          SizedBox(
            height: h * 0.5,
            child: FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: indonesiaCenter,
                initialZoom: 4.2,
                onMapReady: () => _mapReady.complete(),
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag),
              ),
              children: [
                osmTiles(context),
                if (_pos != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _pos!,
                        width: 90,
                        height: 90,
                        child: Semantics(
                          label: 'Posisi Anda',
                          child: const PulseMarker(color: Color(0xFF2A78D6)),
                        ),
                      ),
                    ],
                  ),
                osmAttribution(),
              ],
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            child: !widget.fromLogin
                ? _RoundButton(icon: Icons.arrow_back_rounded, label: 'Kembali', onTap: () => Navigator.pop(context))
                : const SizedBox.shrink(),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 12,
            child: _RoundButton(icon: Icons.my_location_rounded, label: 'Baca lokasi lagi', onTap: _gps == _Gps.locating ? null : _locate),
          ),
          DraggableScrollableSheet(
            initialChildSize: 0.56,
            minChildSize: 0.56,
            maxChildSize: 0.92,
            builder: (context, scroll) => Container(
              decoration: BoxDecoration(
                color: context.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 20, offset: Offset(0, -4))],
              ),
              child: ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(color: context.hairline, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text('Konfirmasi Wilayah', style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                      ),
                      if (me.isDemo) const DemoTag(),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    officerScope != null
                        ? 'Pastikan wilayah kamu sudah sesuai. Wilayah tugas: Kec. ${officerScope.name}.'
                        : 'Pastikan wilayah kamu sudah sesuai.',
                    style: t.bodyMedium?.copyWith(color: context.ink2),
                  ),
                  // Status GPS hanya muncul saat membaca lokasi atau perlu pilih manual.
                  if (_gps != _Gps.found || _note != null) ...[const SizedBox(height: 12), _GpsLine(gps: _gps, note: _note)],
                  const SizedBox(height: 4),
                  for (final (i, f) in fields.indexed)
                    AnimatedOpacity(
                      duration: PK.fieldFill,
                      curve: Curves.easeOut,
                      opacity: i < _visible ? 1 : 0.35,
                      child: _AreaField(
                        label: f.$1,
                        value: i < _visible ? f.$2?.name : null,
                        icon: f.$3,
                        optional: i == 3,
                        enabled: i == 0 || fields[i - 1].$2 != null,
                        onTap: () => _pick(i),
                      ),
                    ),
                  if (me.isDemo && _area.district?.code != '32.71.03') ...[
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: ActionChip(
                        avatar: const Icon(Icons.science_rounded, size: 18),
                        label: const Text('Pakai wilayah demo: Bogor Tengah'),
                        onPressed: _useDemo,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  PrimaryButton(
                    label: 'Konfirmasi wilayah',
                    icon: Icons.check_rounded,
                    color: PK.red,
                    loading: _saving,
                    onPressed: _area.complete ? _confirm : null,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Denied implements Exception {
  const _Denied(this.message);
  final String message;
}

class _GpsLine extends StatelessWidget {
  const _GpsLine({required this.gps, this.note});
  final _Gps gps;
  final String? note;
  @override
  Widget build(BuildContext context) {
    final (icon, text, color) = switch (gps) {
      _Gps.locating => (Icons.gps_not_fixed_rounded, 'Membaca lokasi Anda…', context.brand),
      _Gps.found => (Icons.gps_fixed_rounded, note ?? 'Wilayah terisi otomatis dari GPS. Ketuk kolom untuk mengubah.', note == null ? PK.green : PK.gold),
      _ => (Icons.edit_location_alt_rounded, note ?? 'Pilih wilayah manual.', PK.gold),
    };
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            if (gps == _Gps.locating)
              SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: color))
            else
              Icon(icon, size: 20, color: color),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
          ],
        ),
      ),
    );
  }
}

class _AreaField extends StatelessWidget {
  const _AreaField({required this.label, required this.value, required this.icon, required this.onTap, this.optional = false, this.enabled = true});
  final String label;
  final String? value;
  final IconData icon;
  final VoidCallback onTap;
  final bool optional, enabled;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Semantics(
        button: true,
        label: '$label: ${value ?? 'belum dipilih'}. Ketuk untuk mengubah',
        excludeSemantics: true,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(PK.rField),
          // Satu baris "Provinsi: Jawa Barat" dalam kotak abu muda (gaya mockup); ketuk untuk memilih ulang.
          child: Container(
            constraints: const BoxConstraints(minHeight: 50),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: context.isDark ? PK.darkBg : const Color(0xFFF7F8FA),
              borderRadius: BorderRadius.circular(PK.rField),
              border: Border.all(color: context.hairline),
            ),
            child: Row(
              children: [
                Icon(icon, color: context.ink2, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${optional && value == null ? '$label (opsional)' : label}: ',
                          style: t.bodyMedium?.copyWith(color: context.ink2),
                        ),
                        TextSpan(
                          text: value ?? 'Pilih',
                          style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: value == null ? context.ink2 : context.ink),
                        ),
                      ],
                    ),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: context.ink2, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.label, this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: context.surface,
    shape: const CircleBorder(),
    elevation: 3,
    child: IconButton(
      tooltip: label,
      onPressed: onTap,
      icon: Icon(icon, color: context.ink),
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
    ),
  );
}

/// Lembar pilih wilayah dengan pencarian (dipakai juga di filter kelurahan).
class RegionPicker extends StatefulWidget {
  const RegionPicker({super.key, required this.title, required this.parent});
  final String title;
  final String? parent;
  @override
  State<RegionPicker> createState() => _RegionPickerState();
}

class _RegionPickerState extends State<RegionPicker> {
  List<Region>? _all;
  String _q = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await AppScope.read(context).api.get('/regions', {'parent': widget.parent}) as Map;
      setState(() => _all = (r['regions'] as List).map((e) => Region.from(e)!).toList());
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = (_all ?? []).where((r) => r.name.toLowerCase().contains(_q.toLowerCase())).toList();
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Pilih ${widget.title}', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                TextField(
                  autofocus: false,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Cari nama'),
                  onChanged: (v) => setState(() => _q = v),
                ),
              ],
            ),
          ),
          Expanded(
            child: _error != null
                ? ErrorState(
                    message: _error!,
                    onRetry: () {
                      setState(() => _error = null);
                      _load();
                    },
                  )
                : _all == null
                ? const Center(child: CircularProgressIndicator())
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Divider(indent: 20, endIndent: 20),
                    itemBuilder: (_, i) => ListTile(
                      minTileHeight: 52,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                      title: Text(items[i].name),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.pop(context, items[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
