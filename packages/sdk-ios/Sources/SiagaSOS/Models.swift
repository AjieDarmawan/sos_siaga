import Foundation

/// Status laporan dari sisi perangkat. `.queued` = belum terkirim (tidak ada sinyal).
public enum SosStatus: String, Sendable, Codable {
    case queued, open, acknowledged, inProgress = "in_progress", resolved, cancelled, falseAlarm = "false_alarm"
    public var isTerminal: Bool { self == .resolved || self == .cancelled || self == .falseAlarm }
}

public enum SosMode: String, Sendable { case live, test }

public struct SosLocation: Sendable, Equatable {
    public let lat: Double, lng: Double, accuracyM: Double?
    public init(lat: Double, lng: Double, accuracyM: Double? = nil) { self.lat = lat; self.lng = lng; self.accuracyM = accuracyM }
    var json: [String: Any] { var j: [String: Any] = ["lat": lat, "lng": lng]; if let a = accuracyM { j["accuracy_m"] = a }; return j }
}

/// `ref` = ID pengguna di sistem Anda (juga dipakai untuk rate limit per pengguna).
public struct SosUser: Sendable {
    public let ref: String?, name: String?, phone: String?
    public init(ref: String? = nil, name: String? = nil, phone: String? = nil) { self.ref = ref; self.name = name; self.phone = phone }
    var json: [String: Any] { var j: [String: Any] = [:]; j["ref"] = ref; j["name"] = name; j["phone"] = phone; return j.compactMapValues { $0 } }
}

/// Laporan dari sudut pandang perangkat. `id` nil selama masih di antrian offline.
public struct ActiveReport: Sendable, Equatable {
    public let localId: String
    public internal(set) var id: String?
    public internal(set) var status: SosStatus
    public internal(set) var statusMessage: String?
    public let mode: SosMode
    public let category: String
    public let createdAt: Date
}

public struct SdkConfig: Sendable {
    public let appName: String
    public let categories: [String]
    public let buttonText: String
    public let holdSeconds: Int
    public let recipientText: String
    public let fallbackPhone: String
    public let liveLocationIntervalS: Int

    init(_ j: [String: Any]) {
        appName = j["app_name"] as? String ?? ""
        categories = j["categories"] as? [String] ?? []
        buttonText = j["button_text"] as? String ?? "SOS"
        holdSeconds = j["hold_seconds"] as? Int ?? 3
        recipientText = j["recipient_text"] as? String ?? ""
        fallbackPhone = j["fallback_phone"] as? String ?? "110"
        liveLocationIntervalS = j["live_location_interval_s"] as? Int ?? 15
    }
}

public enum MediaKind: String, Sendable { case image, video, audio }

public struct MediaPublic: Sendable {
    public let id: String, kind: MediaKind, contentType: String, sizeBytes: Int, ready: Bool
    init(_ j: [String: Any]) {
        id = j["id"] as? String ?? ""
        kind = MediaKind(rawValue: j["kind"] as? String ?? "") ?? .image
        contentType = j["content_type"] as? String ?? ""
        sizeBytes = j["size_bytes"] as? Int ?? 0
        ready = (j["status"] as? String) == "ready"
    }
}

/// `status` = HTTP status, 0 = jaringan.
public struct SiagaSOSError: Error, Sendable, CustomStringConvertible {
    public let status: Int, code: String, message: String
    /// Gagal sementara (jaringan, 5xx, rate limit) → layak diulang.
    public var isRetryable: Bool { status == 0 || status >= 500 || status == 429 }
    public var description: String { "SiagaSOSError(\(status), \(code)): \(message)" }
}

/// Mengambil lokasi saat SOS ditekan & selama laporan aktif. Boleh nil.
public protocol LocationProvider: Sendable {
    func currentLocation(timeout: TimeInterval) async -> SosLocation?
}

/// Event laporan. Semua closure opsional; dipanggil di main actor.
public struct SosListener: Sendable {
    public var onStatus: (@MainActor @Sendable (ActiveReport) -> Void)?
    public var onQueued: (@MainActor @Sendable (ActiveReport) -> Void)?
    public var onSent: (@MainActor @Sendable (ActiveReport) -> Void)?
    public var onError: (@MainActor @Sendable (SiagaSOSError) -> Void)?
    public init(onStatus: (@MainActor @Sendable (ActiveReport) -> Void)? = nil, onQueued: (@MainActor @Sendable (ActiveReport) -> Void)? = nil,
                onSent: (@MainActor @Sendable (ActiveReport) -> Void)? = nil, onError: (@MainActor @Sendable (SiagaSOSError) -> Void)? = nil) {
        self.onStatus = onStatus; self.onQueued = onQueued; self.onSent = onSent; self.onError = onError
    }
}
