/// Status laporan dari sisi perangkat. `queued` = belum terkirim (offline).
enum SosStatus { queued, open, acknowledged, inProgress, resolved, cancelled, falseAlarm }

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
  bool get isTerminal => this == SosStatus.resolved || this == SosStatus.cancelled || this == SosStatus.falseAlarm;
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
    complaintCategoryLabels[slug] ?? (slug.isEmpty ? slug : slug[0].toUpperCase() + slug.substring(1).replaceAll('_', ' '));

class SosLocation {
  const SosLocation({required this.lat, required this.lng, this.accuracyM});
  final double lat;
  final double lng;
  final double? accuracyM;
  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng, if (accuracyM != null) 'accuracy_m': accuracyM};
}

class SosUser {
  const SosUser({this.ref, this.name, this.phone});
  /// ID pengguna di sistem Anda (juga dipakai untuk rate limit per pengguna).
  final String? ref;
  final String? name;
  final String? phone;
  Map<String, dynamic> toJson() => {if (ref != null) 'ref': ref, if (name != null) 'name': name, if (phone != null) 'phone': phone};
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

  ActiveReport copyWith({String? id, SosStatus? status, String? statusMessage}) => ActiveReport(
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
        if (acknowledgedAt != null) 'acknowledged_at': acknowledgedAt!.toUtc().toIso8601String(),
        if (resolvedAt != null) 'resolved_at': resolvedAt!.toUtc().toIso8601String(),
      };

  factory ReportRecord.fromJson(Map<String, dynamic> j) => ReportRecord(
        id: j['id'] as String,
        kind: j['kind'] == 'pengaduan' ? ReportKind.pengaduan : ReportKind.sos,
        category: j['category'] as String? ?? '',
        message: j['message'] as String?,
        status: SosStatus.values.where((s) => s.name == j['status']).firstOrNull ?? SosStatus.open,
        statusMessage: j['status_message'] as String?,
        createdAt: _date(j['created_at']) ?? DateTime.now(),
        acknowledgedAt: _date(j['acknowledged_at']),
        resolvedAt: _date(j['resolved_at']),
      );

  static DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;
}

class SdkConfig {
  const SdkConfig({
    required this.appName,
    required this.categories,
    this.complaintCategories = const ['ketertiban', 'kebisingan', 'parkir_liar', 'pungli', 'kehilangan', 'patroli', 'lainnya'],
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
        complaintCategories: (j['complaint_categories'] as List?)?.cast<String>() ??
            const ['ketertiban', 'kebisingan', 'parkir_liar', 'pungli', 'kehilangan', 'patroli', 'lainnya'],
        buttonText: j['button_text'] as String? ?? 'SOS',
        holdSeconds: (j['hold_seconds'] as num? ?? 3).toInt(),
        recipientText: j['recipient_text'] as String? ?? '',
        fallbackPhone: j['fallback_phone'] as String? ?? '110',
        liveLocationIntervalS: (j['live_location_interval_s'] as num? ?? 15).toInt(),
      );
}

enum MediaKind { image, video, audio }

class MediaPublic {
  const MediaPublic({required this.id, required this.kind, required this.contentType, required this.sizeBytes, required this.ready});
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
