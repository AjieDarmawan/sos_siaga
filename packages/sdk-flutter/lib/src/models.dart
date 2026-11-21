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
  });
  final String localId;
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
      );

  @override
  String toString() => 'ActiveReport($localId, id=$id, $status)';
}

class SdkConfig {
  const SdkConfig({
    required this.appName,
    required this.categories,
    required this.buttonText,
    required this.holdSeconds,
    required this.recipientText,
    required this.fallbackPhone,
    required this.liveLocationIntervalS,
  });
  final String appName;
  final List<String> categories;
  final String buttonText;
  final int holdSeconds;
  final String recipientText;
  final String fallbackPhone;
  final int liveLocationIntervalS;

  factory SdkConfig.fromJson(Map<String, dynamic> j) => SdkConfig(
        appName: j['app_name'] as String? ?? '',
        categories: (j['categories'] as List? ?? const []).cast<String>(),
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
