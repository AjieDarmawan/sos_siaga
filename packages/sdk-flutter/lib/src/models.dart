/// Status laporan dari sisi perangkat. `queued` = belum terkirim (offline).
enum SosStatus {
  queued,
  open,
  acknowledged,
  inProgress,
  resolved,
  cancelled,
  falseAlarm
}

SosStatus sosStatusFromApi(String s) => switch (s) {
      'open' => SosStatus.open,
      'acknowledged' => SosStatus.acknowledged,
      'in_progress' => SosStatus.inProgress,
      'resolved' => SosStatus.resolved,
      'cancelled' => SosStatus.cancelled,
      'false_alarm' => SosStatus.falseAlarm,
      _ => SosStatus.open,
    };

extension SosStatusX on SosStatus {
  bool get isTerminal =>
      this == SosStatus.resolved ||
      this == SosStatus.cancelled ||
      this == SosStatus.falseAlarm;
}

enum SosMode { live, test }

/// Jenis laporan. [pengaduan] = non-darurat: tanpa lokasi live, tanpa notifikasi darurat ke responder.
enum ReportKind { sos, pengaduan }

/// Label bawaan kategori pengaduan (slug dari `complaint_categories` di /v1/sdk/config).
const complaintCategoryLabels = <String, String>{
  'ketertiban': 'Gangguan ketertiban',
  'kebisingan': 'Kebisingan',
  'parkir_liar': 'Parkir liar',
  'pungli': 'Pungutan liar',
  'kehilangan': 'Kehilangan barang/dokumen',
  'patroli': 'Minta patroli',
  'lainnya': 'Lainnya',
};
String complaintCategoryLabel(String slug) =>
    complaintCategoryLabels[slug] ??
    (slug.isEmpty
        ? slug
        : slug[0].toUpperCase() + slug.substring(1).replaceAll('_', ' '));

class SosLocation {
  const SosLocation({required this.lat, required this.lng, this.accuracyM});
  final double lat;
  final double lng;
  final double? accuracyM;
  Map<String, dynamic> toJson() =>
      {'lat': lat, 'lng': lng, if (accuracyM != null) 'accuracy_m': accuracyM};
}

class SosUser {
  const SosUser({this.ref, this.name, this.phone});

  /// ID pengguna di sistem Anda (juga dipakai untuk rate limit per pengguna).
  final String? ref;
  final String? name;
  final String? phone;
  Map<String, dynamic> toJson() => {
        if (ref != null) 'ref': ref,
        if (name != null) 'name': name,
        if (phone != null) 'phone': phone
      };
}

/// Laporan dari sudut pandang perangkat. [id] null selama masih di antrian offline.
class ActiveReport {
  const ActiveReport({
    required this.localId,
    required this.id,
    required this.status,
    required this.mode,
    required this.category,
    required this.createdAt,
    this.statusMessage,
    this.kind = ReportKind.sos,
  });
  final String localId;
  final ReportKind kind;
  final String? id;
  final SosStatus status;
  final String? statusMessage;
  final SosMode mode;
  final String category;
  final DateTime createdAt;

  ActiveReport copyWith(
          {String? id, SosStatus? status, String? statusMessage}) =>
      ActiveReport(
        localId: localId,
        id: id ?? this.id,
        status: status ?? this.status,
        statusMessage: statusMessage ?? this.statusMessage,
        mode: mode,
        category: category,
        createdAt: createdAt,
        kind: kind,
      );

  @override
  String toString() => 'ActiveReport($localId, id=$id, $status)';
}

/// Kontak darurat pribadi pelapor (gaya "Nomor Darurat" tata-warga): yang [active] dikabari WhatsApp oleh server
/// setiap SOS (maks. [maxActiveEmergencyContacts] aktif). Disimpan di perangkat per pengguna
/// ([SiagaSOS.setEmergencyContacts]); app host bisa membuat halaman CRUD sendiri di atas API ini.
class EmergencyContact {
  const EmergencyContact(
      {required this.name, required this.phone, this.role, this.active = true});
  final String name;

  /// Nomor WhatsApp ternormalisasi 62xxxxxxxxxx.
  final String phone;

  /// Jabatan / hubungan, opsional (mis. Satpam, Pemilik toko, Keluarga).
  final String? role;

  /// Hanya kontak aktif yang menerima SOS.
  final bool active;

  EmergencyContact copyWith(
          {String? name,
          String? phone,
          String? role,
          bool? active,
          bool clearRole = false}) =>
      EmergencyContact(
        name: name ?? this.name,
        phone: phone ?? this.phone,
        role: clearRole ? null : (role ?? this.role),
        active: active ?? this.active,
      );

  /// Bentuk yang disimpan di perangkat.
  Map<String, dynamic> toJson() => {
        'name': name,
        'phone': phone,
        if (role != null) 'role': role,
        'active': active
      };

  /// Bentuk yang dikirim ke server bersama SOS (`emergency_contacts[]`).
  Map<String, dynamic> toReportJson() => {
        'name': role == null || role!.isEmpty ? name : '$name ($role)',
        'phone': phone
      };

  factory EmergencyContact.fromJson(Map<String, dynamic> j) => EmergencyContact(
        name: j['name'] as String? ?? '',
        phone: j['phone'] as String? ?? '',
        role: (j['role'] as String?)?.trim().isEmpty ?? true
            ? null
            : (j['role'] as String).trim(),
        active: j['active'] as bool? ?? true,
      );

  @override
  bool operator ==(Object other) =>
      other is EmergencyContact &&
      other.name == name &&
      other.phone == phone &&
      other.role == role &&
      other.active == active;
  @override
  int get hashCode => Object.hash(name, phone, role, active);
}

/// Maks. kontak aktif yang dikabari per SOS (sama dengan batas server & tata-warga).
const maxActiveEmergencyContacts = 5;

/// Maks. kontak tersimpan (aktif + nonaktif).
const maxEmergencyContacts = 10;

/// 08xx / +62xx / 62xx / 8xx → 62xx. Null bila bukan nomor Indonesia yang masuk akal (sama dengan server).
String? toWhatsAppNumber(String phone) {
  var d = phone.replaceAll(RegExp(r'\D'), '');
  if (d.startsWith('0')) {
    d = '62${d.substring(1)}';
  } else if (d.startsWith('8')) {
    d = '62$d';
  }
  return RegExp(r'^62[0-9]{8,13}$').hasMatch(d) ? d : null;
}

/// Satu laporan di riwayat perangkat ([SiagaSOS.history]): yang pernah terkirim dari perangkat ini
/// oleh pengguna yang sama. Status diperbarui dari server saat riwayat dibuka.
class ReportRecord {
  const ReportRecord({
    required this.id,
    required this.kind,
    required this.category,
    required this.status,
    required this.createdAt,
    this.message,
    this.statusMessage,
    this.acknowledgedAt,
    this.resolvedAt,
  });
  final String id;
  final ReportKind kind;
  final String category;
  final String? message;
  final SosStatus status;
  final String? statusMessage;
  final DateTime createdAt;
  final DateTime? acknowledgedAt;
  final DateTime? resolvedAt;

  /// Gabungkan jawaban `GET /v1/sdk/reports/:id`.
  ReportRecord withServer(Map<String, dynamic> j) => ReportRecord(
        id: id,
        kind: kind,
        category: category,
        message: message,
        createdAt: createdAt,
        status: sosStatusFromApi(j['status'] as String? ?? 'open'),
        statusMessage: j['status_message'] as String?,
        acknowledgedAt: _date(j['acknowledged_at']),
        resolvedAt: _date(j['resolved_at']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'category': category,
        if (message != null) 'message': message,
        'status': status.name,
        if (statusMessage != null) 'status_message': statusMessage,
        'created_at': createdAt.toUtc().toIso8601String(),
        if (acknowledgedAt != null)
          'acknowledged_at': acknowledgedAt!.toUtc().toIso8601String(),
        if (resolvedAt != null)
          'resolved_at': resolvedAt!.toUtc().toIso8601String(),
      };

  factory ReportRecord.fromJson(Map<String, dynamic> j) => ReportRecord(
        id: j['id'] as String,
        kind: j['kind'] == 'pengaduan' ? ReportKind.pengaduan : ReportKind.sos,
        category: j['category'] as String? ?? '',
        message: j['message'] as String?,
        status:
            SosStatus.values.where((s) => s.name == j['status']).firstOrNull ??
                SosStatus.open,
        statusMessage: j['status_message'] as String?,
        createdAt: _date(j['created_at']) ?? DateTime.now(),
        acknowledgedAt: _date(j['acknowledged_at']),
        resolvedAt: _date(j['resolved_at']),
      );

  static DateTime? _date(Object? v) =>
      v is String ? DateTime.tryParse(v)?.toLocal() : null;
}

/// Satu baris riwayat status di detail laporan ([SiagaSOS.reportDetail]).
class ReportTimelineEntry {
  const ReportTimelineEntry(
      {required this.type,
      required this.actor,
      required this.createdAt,
      this.toStatus,
      this.note});

  /// created | status_changed | cancelled | note | media | whatsapp
  final String type;

  /// "Anda", nama petugas, "Petugas", atau "Sistem".
  final String actor;
  final SosStatus? toStatus;
  final String? note;
  final DateTime createdAt;

  factory ReportTimelineEntry.fromJson(Map<String, dynamic> j) =>
      ReportTimelineEntry(
        type: j['type'] as String? ?? '',
        actor: j['actor'] as String? ?? 'Sistem',
        toStatus: j['to_status'] == null
            ? null
            : sosStatusFromApi(j['to_status'] as String),
        note: j['note'] as String?,
        createdAt:
            DateTime.tryParse(j['created_at'] as String? ?? '')?.toLocal() ??
                DateTime.now(),
      );
}

/// Lampiran di detail laporan. [url] = URL baca sementara (± 15 menit); minta ulang detail bila kedaluwarsa.
class ReportMediaItem {
  const ReportMediaItem(
      {required this.id,
      required this.kind,
      required this.contentType,
      required this.uploadedBy,
      this.url,
      this.durationS});
  final String id;
  final MediaKind kind;
  final String contentType;

  /// reporter (pelapor) | user (petugas) | server
  final String uploadedBy;
  final String? url;
  final double? durationS;

  factory ReportMediaItem.fromJson(Map<String, dynamic> j) => ReportMediaItem(
        id: j['id'] as String,
        kind: MediaKind.values.firstWhere((k) => k.name == j['kind'],
            orElse: () => MediaKind.image),
        contentType: j['content_type'] as String? ?? '',
        uploadedBy: j['uploaded_by'] as String? ?? 'reporter',
        url: j['url'] as String?,
        durationS: (j['duration_s'] as num?)?.toDouble(),
      );
}

/// Detail laporan untuk halaman "Riwayat laporan": status, uraian, lokasi, riwayat status, dan lampiran.
class ReportDetail {
  const ReportDetail({
    required this.id,
    required this.kind,
    required this.category,
    required this.status,
    required this.createdAt,
    this.statusMessage,
    this.message,
    this.location,
    this.acknowledgedAt,
    this.resolvedAt,
    this.timeline = const [],
    this.media = const [],
  });
  final String id;
  final ReportKind kind;
  final String category;
  final SosStatus status;
  final String? statusMessage;
  final String? message;
  final SosLocation? location;
  final DateTime createdAt;
  final DateTime? acknowledgedAt;
  final DateTime? resolvedAt;
  final List<ReportTimelineEntry> timeline;
  final List<ReportMediaItem> media;

  static DateTime? _d(Object? v) =>
      v is String ? DateTime.tryParse(v)?.toLocal() : null;

  factory ReportDetail.fromJson(Map<String, dynamic> j) {
    final loc = j['location'] as Map<String, dynamic>?;
    return ReportDetail(
      id: j['id'] as String,
      kind: j['kind'] == 'pengaduan' ? ReportKind.pengaduan : ReportKind.sos,
      category: j['category'] as String? ?? '',
      status: sosStatusFromApi(j['status'] as String? ?? 'open'),
      statusMessage: j['status_message'] as String?,
      message: j['message'] as String?,
      location: loc == null
          ? null
          : SosLocation(
              lat: (loc['lat'] as num).toDouble(),
              lng: (loc['lng'] as num).toDouble(),
              accuracyM: (loc['accuracy_m'] as num?)?.toDouble()),
      createdAt: _d(j['created_at']) ?? DateTime.now(),
      acknowledgedAt: _d(j['acknowledged_at']),
      resolvedAt: _d(j['resolved_at']),
      timeline: [
        for (final e in (j['timeline'] as List? ?? const []))
          ReportTimelineEntry.fromJson(e as Map<String, dynamic>)
      ],
      media: [
        for (final m in (j['media'] as List? ?? const []))
          ReportMediaItem.fromJson(m as Map<String, dynamic>)
      ],
    );
  }
}

class SdkConfig {
  const SdkConfig({
    required this.appName,
    required this.categories,
    this.complaintCategories = const [
      'ketertiban',
      'kebisingan',
      'parkir_liar',
      'pungli',
      'kehilangan',
      'patroli',
      'lainnya'
    ],
    required this.buttonText,
    required this.holdSeconds,
    required this.recipientText,
    required this.fallbackPhone,
    required this.liveLocationIntervalS,
  });
  final String appName;
  final List<String> categories;
  final List<String> complaintCategories;
  final String buttonText;
  final int holdSeconds;
  final String recipientText;
  final String fallbackPhone;
  final int liveLocationIntervalS;

  factory SdkConfig.fromJson(Map<String, dynamic> j) => SdkConfig(
        appName: j['app_name'] as String? ?? '',
        categories: (j['categories'] as List? ?? const []).cast<String>(),
        complaintCategories:
            (j['complaint_categories'] as List?)?.cast<String>() ??
                const [
                  'ketertiban',
                  'kebisingan',
                  'parkir_liar',
                  'pungli',
                  'kehilangan',
                  'patroli',
                  'lainnya'
                ],
        buttonText: j['button_text'] as String? ?? 'SOS',
        holdSeconds: (j['hold_seconds'] as num? ?? 3).toInt(),
        recipientText: j['recipient_text'] as String? ?? '',
        fallbackPhone: j['fallback_phone'] as String? ?? '110',
        liveLocationIntervalS:
            (j['live_location_interval_s'] as num? ?? 15).toInt(),
      );
}

enum MediaKind { image, video, audio }

class MediaPublic {
  const MediaPublic(
      {required this.id,
      required this.kind,
      required this.contentType,
      required this.sizeBytes,
      required this.ready});
  final String id;
  final MediaKind kind;
  final String contentType;
  final int sizeBytes;
  final bool ready;
  factory MediaPublic.fromJson(Map<String, dynamic> j) => MediaPublic(
        id: j['id'] as String,
        kind: MediaKind.values.byName(j['kind'] as String),
        contentType: j['content_type'] as String,
        sizeBytes: (j['size_bytes'] as num).toInt(),
        ready: j['status'] == 'ready',
      );
}

class SiagaSOSError implements Exception {
  const SiagaSOSError(this.status, this.code, this.message);

  /// HTTP status; 0 = jaringan.
  final int status;
  final String code;
  final String message;

  /// Gagal sementara (jaringan, 5xx, rate limit) → layak diulang.
  bool get isRetryable => status == 0 || status >= 500 || status == 429;
  @override
  String toString() => 'SiagaSOSError($status, $code): $message';
}

/// Detail pengaduan (gaya Lapor Keamanan): dikirim bersama uraian. Semua opsional.
class ComplaintDetails {
  const ComplaintDetails(
      {this.title,
      this.description,
      this.locationText,
      this.occurredAt,
      this.suspect,
      this.witness});

  final String? title;
  final String? description;
  final String? locationText;

  /// Waktu kejadian; null = saat laporan dikirim.
  final DateTime? occurredAt;
  final String? suspect;
  final String? witness;

  static bool _filled(String? s) => s != null && s.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
        if (_filled(title)) 'title': title!.trim(),
        if (_filled(description)) 'description': description!.trim(),
        if (_filled(locationText)) 'location_text': locationText!.trim(),
        if (occurredAt != null)
          'occurred_at': occurredAt!.toUtc().toIso8601String(),
        if (_filled(suspect)) 'suspect': suspect!.trim(),
        if (_filled(witness)) 'witness': witness!.trim(),
      };
}
