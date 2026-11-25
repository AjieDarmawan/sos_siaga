import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'format.dart';

/// Wilayah (kode Kemendagri bertitik).
class Region {
  const Region(this.code, this.name);
  final String code;
  final String name;
  static Region? from(dynamic j) => j is Map ? Region(j['code'] as String, j['name'] as String) : null;
  Map<String, dynamic> toJson() => {'code': code, 'name': name};
}

class Area {
  Area({this.province, this.regency, this.district, this.village});
  Region? province, regency, district, village;
  factory Area.from(dynamic j) => j is Map
      ? Area(province: Region.from(j['province']), regency: Region.from(j['regency']), district: Region.from(j['district']), village: Region.from(j['village']))
      : Area();
  bool get complete => province != null && regency != null && district != null;
}

class RoleInfo {
  RoleInfo(this.id, this.role, this.label, this.unit, this.kecamatan);
  final String id, role, label;
  final String? unit;
  final Region? kecamatan;
  factory RoleInfo.from(Map j) =>
      RoleInfo(j['id'] as String, j['role'] as String, j['label'] as String? ?? j['role'] as String, j['unit'] as String?, Region.from(j['kecamatan']));
}

class Me {
  Me(this.raw);
  final Map raw;
  Map get user => raw['user'] as Map;
  String get name => user['name'] as String;
  String get phone => user['phone'] as String;
  bool get isDemo => user['is_demo'] == true;
  Map get role => raw['role'] as Map;
  String get roleId => role['id'] as String;
  String get roleKey => role['role'] as String;
  String get roleLabel => role['label'] as String? ?? roleKey;
  String? get unit => role['unit'] as String?;
  List<RoleInfo> get roles => (raw['roles'] as List).map((e) => RoleInfo.from(e as Map)).toList();
  Area get area => Area.from(raw['area']);
  Region? get scope => Region.from(raw['scope']);
  bool get needsArea => raw['needs_area'] == true;

  /// Ekosistem yang dilayani (Profil): pilar + nama app, dari Nomor Darurat (+ app di kecamatan untuk Bhabinkamtibmas).
  List<({String source, String label, String app})> get ecosystems => ((raw['ecosystems'] as List?) ?? const [])
      .cast<Map>()
      .map((e) => (source: e['source'] as String, label: e['label'] as String, app: e['app_name'] as String))
      .toList();

  /// Siapa penerima ini menurut Nomor Darurat, mis. "Satpam · Toko Roti Sinar Jaya (UMKM)" atau
  /// "Bhabinkamtibmas · Kec. Bogor Tengah". Bukan dari GPS.
  String get identity {
    final kec = roles.where((r) => r.id == roleId).firstOrNull?.kecamatan;
    return switch (roleKey) {
      'penerima' => unit ?? roleLabel,
      'bhabinkamtibmas' => ['Bhabinkamtibmas', if (kec != null) 'Kec. ${kec.name}' else ?unit].join(' · '),
      _ => [roleLabel, ?unit, if (scope != null) 'Kec. ${scope!.name}'].join(' · '),
    };
  }

  /// Penerima darurat & Bhabinkamtibmas bisa menanggapi; aksi per laporan tetap ditentukan server (`actions`).
  bool get canRespond => raw['can_respond'] == true;
  bool get isOfficer => raw['is_officer'] == true;
  ({double lat, double lng})? get areaLocation {
    final l = raw['area_location'];
    return l is Map ? (lat: (l['lat'] as num).toDouble(), lng: (l['lng'] as num).toDouble()) : null;
  }
}

/// Hasil `/auth/check`: dari Nomor Darurat mana nomor ini dikenal.
class PhoneCheck {
  PhoneCheck(this.raw);
  final Map raw;
  String get phone => raw['phone'] as String;
  String get name => raw['name'] as String? ?? '';
  bool get hasPassword => raw['has_password'] == true;

  /// Mis. ["Satpam · Toko Roti Sinar Jaya", "Ketua RT 03 · Keluarga Siti"].
  List<String> get contactLines => ((raw['contacts'] as List?) ?? const [])
      .cast<Map>()
      .map((c) => [c['role'], c['place']].whereType<String>().where((s) => s.isNotEmpty).join(' · '))
      .where((s) => s.isNotEmpty)
      .toList();
}

/// Status tampilan (PRD): Darurat/Baru → Diterima → Diverifikasi → Ditangani → Selesai.
enum PkStatus { baru, diterima, diverifikasi, ditangani, selesai, tidakValid, dibatalkan }

PkStatus parseStatus(String? s) => switch (s) {
  'diterima' => PkStatus.diterima,
  'diverifikasi' => PkStatus.diverifikasi,
  'ditangani' => PkStatus.ditangani,
  'selesai' => PkStatus.selesai,
  'tidak_valid' => PkStatus.tidakValid,
  'dibatalkan' => PkStatus.dibatalkan,
  _ => PkStatus.baru,
};

class StatusStyle {
  const StatusStyle(this.label, this.color, this.icon);
  final String label;
  final Color color;
  final IconData icon;
}

/// Lencana status: Darurat (merah), Diproses (emas), Selesai (hijau). Selalu teks + ikon, bukan warna saja.
StatusStyle statusStyle(PkStatus s, {required bool sos}) => switch (s) {
  PkStatus.baru => sos ? const StatusStyle('Darurat', PK.red, Icons.warning_rounded) : const StatusStyle('Baru', PK.navy, Icons.fiber_new_rounded),
  PkStatus.diterima => const StatusStyle('Diterima', PK.gold, Icons.mark_email_read_rounded),
  PkStatus.diverifikasi => const StatusStyle('Diverifikasi', PK.gold, Icons.verified_rounded),
  PkStatus.ditangani => const StatusStyle('Ditangani', PK.gold, Icons.directions_run_rounded),
  PkStatus.selesai => const StatusStyle('Selesai', PK.green, Icons.check_circle_rounded),
  PkStatus.tidakValid => const StatusStyle('Tidak valid', PK.grey, Icons.block_rounded),
  PkStatus.dibatalkan => const StatusStyle('Dibatalkan', PK.grey, Icons.cancel_rounded),
};

class Report {
  Report(this.raw);
  final Map raw;
  String get id => raw['id'] as String;
  bool get isSos => raw['kind'] == 'sos';
  String get category => raw['category'] as String? ?? 'umum';
  String? get title => raw['title'] as String?;
  String? get message => raw['message'] as String?;
  PkStatus get status => parseStatus(raw['status'] as String?);
  String get source => raw['source'] as String? ?? 'warga';
  String get sourceLabel => raw['source_label'] as String? ?? 'Polmas';
  String? get sourcePlace => raw['source_place'] as String?;
  String? get locationText => raw['location_text'] as String?;
  Region? get kecamatan => Region.from(raw['kecamatan']);
  Region? get kelurahan => Region.from(raw['kelurahan']);
  ({double lat, double lng})? get location {
    final l = raw['location'];
    return l is Map ? (lat: (l['lat'] as num).toDouble(), lng: (l['lng'] as num).toDouble()) : null;
  }

  String get reporterName => (raw['reporter'] as Map?)?['name'] as String? ?? 'Warga';
  String? get reporterPhone => (raw['reporter'] as Map?)?['phone'] as String?;
  bool get isMine => (raw['reporter'] as Map?)?['is_me'] == true;
  DateTime get createdAt => DateTime.parse(raw['created_at'] as String).toLocal();
  DateTime? get acknowledgedAt => _dt(raw['acknowledged_at']);
  DateTime? get resolvedAt => _dt(raw['resolved_at']);
  int get videoCount => ((raw['media'] as Map?)?['video'] as num?)?.toInt() ?? 0;
  int get imageCount => ((raw['media'] as Map?)?['image'] as num?)?.toInt() ?? 0;
  Map? get lastResponse => raw['last_response'] as Map?;
  bool get isDemo => raw['is_demo'] == true;

  /// Foto bukti pertama (URL baca 15 menit) untuk gambar mini kartu; null bila tidak ada foto.
  String? get thumbUrl => raw['thumb_url'] as String?;

  /// Sampai 3 foto untuk deretan gambar mini kartu (hanya di daftar).
  List<String> get thumbUrls => ((raw['thumb_urls'] as List?) ?? [?thumbUrl]).cast<String>();
  int get audioCount => ((raw['media'] as Map?)?['audio'] as num?)?.toInt() ?? 0;
  num? get videoSeconds => raw['video_s'] as num?;
  num? get audioSeconds => raw['audio_s'] as num?;

  /// Nomor tiket pendek, mis. "SOS-2511-3F9A".
  String get code => raw['code'] as String? ?? id.substring(0, 8).toUpperCase();
  String? get appName => raw['app_name'] as String?;

  /// Kolom Ekosistem: pilar (UMKM, Lingkungan, …) + nama app sumber (commerceOS, tata-warga, …).
  String get ecosystemLabel => sourceLabel;
  String? get ecosystemApp => appName == sourceLabel ? null : appName;

  /// Jarak dari titik pengguna (lokasi saat konfirmasi wilayah), mis. "± 350 m".
  String? distanceFrom(({double lat, double lng})? me) {
    final l = location;
    if (me == null || l == null) return null;
    return fmtDistance(distanceM(me.lat, me.lng, l.lat, l.lng));
  }

  /// Kelompok status di kartu (PRD): Darurat/Baru, Diproses, Selesai.
  PkStatus get group => switch (status) {
    PkStatus.diterima || PkStatus.diverifikasi || PkStatus.ditangani => PkStatus.ditangani,
    final s => s,
  };

  String get headline => title ?? (isSos ? 'SOS ${categoryLabel(category)}' : categoryLabel(category));
  String get placeLine => [if (kelurahan != null) 'Kel. ${kelurahan!.name}', ?locationText ?? sourcePlace].join(' · ');
}

DateTime? _dt(dynamic v) => v is String ? DateTime.parse(v).toLocal() : null;

const _categoryLabels = {
  'darurat': 'Darurat',
  'pencurian': 'Pencurian',
  'mencurigakan': 'Orang mencurigakan',
  'tawuran': 'Tawuran',
  'kecelakaan': 'Kecelakaan',
  'gangguan': 'Gangguan ketertiban',
  'penipuan': 'Penipuan',
  'kebakaran': 'Kebakaran',
  'narkoba': 'Narkoba',
  'general': 'Umum',
  'medical': 'Medis',
  'fire': 'Kebakaran',
  'crime': 'Kriminal',
};

String categoryLabel(String c) => _categoryLabels[c] ?? (c.isEmpty ? 'Umum' : c[0].toUpperCase() + c.substring(1).replaceAll('_', ' '));

IconData categoryIcon(String c) => switch (c) {
  'pencurian' || 'crime' => Icons.lock_open_rounded,
  'mencurigakan' => Icons.visibility_rounded,
  'tawuran' => Icons.groups_rounded,
  'kecelakaan' => Icons.car_crash_rounded,
  'gangguan' => Icons.campaign_rounded,
  'penipuan' => Icons.phishing_rounded,
  'kebakaran' || 'fire' => Icons.local_fire_department_rounded,
  'narkoba' => Icons.medication_rounded,
  'medical' => Icons.medical_services_rounded,
  _ => Icons.sos_rounded,
};

IconData sourceIcon(String s) => switch (s) {
  'kantor' => Icons.business_rounded,
  'umkm' => Icons.storefront_rounded,
  'sekolah' => Icons.school_rounded,
  'komunitas' => Icons.diversity_3_rounded,
  _ => Icons.home_rounded,
};
