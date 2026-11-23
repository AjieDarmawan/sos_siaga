import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import SiagaSOS

// Uji SDK tanpa XCTest. `swift run siagasos-selftest` (unit, server palsu)
// `SIAGASOS_IT=1 swift run siagasos-selftest` (+ integrasi ke API lokal & MinIO; butuh pnpm dev:api + seed:demo)

nonisolated(unsafe) var passed = 0
nonisolated(unsafe) var failed = 0
func check(_ cond: Bool, _ name: String) {
    if cond { passed += 1; print("✔ \(name)") } else { failed += 1; print("✘ \(name)") }
}

// ------------------------------------------------------------------ server palsu via URLProtocol
struct Rec { let method: String; let path: String; let headers: [String: String]; let body: Data }
final class Fake: @unchecked Sendable {
    static let shared = Fake()
    let lock = NSLock()
    var reqs: [Rec] = []
    var failReports = 0
    var status = "open"
    func reset() { lock.lock(); reqs = []; failReports = 0; status = "open"; lock.unlock() }
    func count(_ path: String) -> Int { lock.lock(); defer { lock.unlock() }; return reqs.filter { $0.path == path }.count }
}

final class FakeProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let f = Fake.shared
        var body = request.httpBody ?? Data()
        if body.isEmpty, let s = request.httpBodyStream {
            s.open(); var buf = [UInt8](repeating: 0, count: 4096)
            while s.hasBytesAvailable { let n = s.read(&buf, maxLength: buf.count); if n <= 0 { break }; body.append(buf, count: n) }
            s.close()
        }
        let path = request.url!.path
        f.lock.lock()
        f.reqs.append(Rec(method: request.httpMethod ?? "GET", path: path, headers: request.allHTTPHeaderFields ?? [:], body: body))
        var code = 404, out = "{}"
        switch path {
        case "/v1/sdk/config": code = 200; out = #"{"app_name":"Demo","categories":["general"],"button_text":"SOS","hold_seconds":2,"recipient_text":"x","fallback_phone":"110","live_location_interval_s":15}"#
        case "/v1/sdk/reports" where f.failReports > 0: f.failReports -= 1; code = 503; out = #"{"error":{"code":"unavailable","message":"down"}}"#
        case "/v1/sdk/reports" where request.value(forHTTPHeaderField: "X-SOS-Bundle") == "com.jahat.app": code = 403; out = #"{"error":{"code":"bundle_not_allowed","message":"no"}}"#
        case "/v1/sdk/reports": code = 201; out = #"{"id":"rep-1","status":"open","mode":"test","category":"medis","status_message":null}"#
        case "/v1/sdk/reports/rep-1": code = 200; out = "{\"id\":\"rep-1\",\"status\":\"\(f.status)\",\"status_message\":null}"
        case "/v1/sdk/reports/rep-1/media": code = 201; out = #"{"media":{"id":"m-1"},"upload":{"method":"PUT","url":"https://storage.test/put?sig=1","headers":{"Content-Type":"image/jpeg"}}}"#
        case "/put": code = 200; out = ""
        case "/v1/sdk/reports/rep-1/media/m-1/complete": code = 200; out = #"{"id":"m-1","kind":"image","content_type":"image/jpeg","size_bytes":3,"status":"ready"}"#
        default: break
        }
        f.lock.unlock()
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(out.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

struct FixedLocation: LocationProvider { func currentLocation(timeout: TimeInterval) async -> SosLocation? { SosLocation(lat: -6.2, lng: 106.8, accuracyM: 10) } }

let cfg = URLSessionConfiguration.ephemeral
cfg.protocolClasses = [FakeProtocol.self]
let fakeSession = URLSession(configuration: cfg)
func make(_ store: QueueStore = MemoryQueueStore(), bundle: String = "com.demo.app") throws -> SiagaSOS {
    try SiagaSOS(apiKey: "pk_test_abcdefghijklmnop", bundleId: bundle, user: SosUser(ref: "u1", name: "Budi"), baseURL: "https://api.test",
                 pollInterval: 0.05, locationProvider: FixedLocation(), queueStore: store, session: fakeSession)
}
func sleep(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1e9)) }

do { _ = try SiagaSOS(apiKey: "sk_test_x", bundleId: "a.b"); check(false, "menolak secret key") } catch { check((error as? SiagaSOSError)?.code == "invalid_api_key", "menolak secret key") }

// trigger: header mobile & body
Fake.shared.reset()
do {
    let sos = try make()
    check(sos.mode == .test, "mode dari prefix kunci")
    let r = try await sos.trigger(category: "medis", message: "pingsan")
    check(r.id == "rep-1" && r.status == .open, "trigger → open")
    let post = Fake.shared.reqs.first { $0.path == "/v1/sdk/reports" }!
    check(post.headers["X-SOS-Bundle"] == "com.demo.app" && post.headers["X-SOS-Key"] == "pk_test_abcdefghijklmnop", "header X-SOS-Key + X-SOS-Bundle")
    check((post.headers["Idempotency-Key"] ?? "").count == 36, "Idempotency-Key UUID")
    let body = try JSONSerialization.jsonObject(with: post.body) as! [String: Any]
    check((body["location"] as? [String: Any])?["lat"] as? Double == -6.2 && (body["device"] as? [String: Any])?["platform"] as? String == "ios", "body: lokasi + device ios")
    sos.shutdown()
}

// offline → antrian → retry idempotency key sama
Fake.shared.reset(); Fake.shared.failReports = 1
do {
    let store = MemoryQueueStore()
    let sos = try make(store)
    let r = try await sos.trigger(category: "kriminal")
    check(r.status == .queued && r.id == nil && store.load().count == 1, "offline → masuk antrian")
    for _ in 0..<40 where !store.load().isEmpty { await sleep(0.1) }
    check(store.load().isEmpty, "terkirim ulang otomatis")
    let keys = Set(Fake.shared.reqs.filter { $0.path == "/v1/sdk/reports" }.compactMap { $0.headers["Idempotency-Key"] })
    check(keys.count == 1, "retry memakai Idempotency-Key yang sama")
    sos.shutdown()
}

// error permanen
Fake.shared.reset()
do {
    let store = MemoryQueueStore()
    let sos = try make(store, bundle: "com.jahat.app")
    do { _ = try await sos.trigger(); check(false, "bundle salah dilempar") } catch { check((error as? SiagaSOSError)?.code == "bundle_not_allowed" && store.load().isEmpty, "bundle salah dilempar, tidak diantrikan") }
    sos.shutdown()
}

// polling berhenti di status akhir
Fake.shared.reset()
do {
    let sos = try make()
    let seen = NSMutableArray()
    _ = sos.addListener(SosListener(onStatus: { r in seen.add(r.status.rawValue) }))
    _ = try await sos.trigger()
    Fake.shared.lock.lock(); Fake.shared.status = "acknowledged"; Fake.shared.lock.unlock(); await sleep(0.3)
    Fake.shared.lock.lock(); Fake.shared.status = "resolved"; Fake.shared.lock.unlock(); await sleep(0.3)
    let n = Fake.shared.count("/v1/sdk/reports/rep-1")
    await sleep(0.3)
    let s = seen.compactMap { $0 as? String }
    check(s.contains("acknowledged") && s.contains("resolved"), "status realtime: open → acknowledged → resolved")
    check(Fake.shared.count("/v1/sdk/reports/rep-1") == n, "polling berhenti di status akhir")
    sos.shutdown()
}

// attach
Fake.shared.reset()
do {
    let sos = try make()
    let r = try await sos.trigger()
    let m = try await sos.attach(r.localId, data: Data([1, 2, 3]), contentType: "image/jpeg")
    check(m.ready && m.kind == .image, "attach → ready")
    let put = Fake.shared.reqs.first { $0.path == "/put" }
    check(put?.method == "PUT" && put?.headers["X-SOS-Key"] == nil, "PUT ke storage tanpa X-SOS-Key")
    sos.shutdown()
}

// batal saat antrian
Fake.shared.reset(); Fake.shared.failReports = 99
do {
    let store = MemoryQueueStore()
    let sos = try make(store)
    let r = try await sos.trigger()
    let c = try await sos.cancel(r.localId)
    check(c?.status == .cancelled && store.load().isEmpty, "batal saat masih di antrian")
    sos.shutdown()
}

// ------------------------------------------------------------------ integrasi
if ProcessInfo.processInfo.environment["SIAGASOS_IT"] == "1" {
    print("— integrasi ke API lokal + MinIO")
    let api = "http://localhost:4000"
    func http(_ m: String, _ p: String, _ body: String? = nil, token: String? = nil) async throws -> [String: Any] {
        var r = URLRequest(url: URL(string: api + p)!); r.httpMethod = m
        if let t = token { r.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        if let b = body { r.httpBody = Data(b.utf8); r.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return try JSONSerialization.jsonObject(with: try await URLSession.shared.data(for: r).0) as! [String: Any]
    }
    let token = try await http("POST", "/portal/auth/login", #"{"email":"demo@siagasos.test","password":"demo12345"}"#)["token"] as! String
    let apps = try await http("GET", "/portal/apps", token: token)["data"] as! [[String: Any]]
    let android = apps.first { ($0["name"] as! String).contains("Android") }!
    let pk = (android["keys"] as! [[String: Any]]).first { $0["kind"] as? String == "publishable" && $0["mode"] as? String == "live" && $0["active"] as? Bool == true }!["key"] as! String
    let sos = try SiagaSOS(apiKey: pk, bundleId: "id.demosiaga.kurir", user: SosUser(ref: "ios-it", name: "Uji iOS SDK"), baseURL: api,
                           locationProvider: FixedLocation(), queueStore: MemoryQueueStore())
    check(try await sos.getConfig().appName.contains("Android"), "IT: config")
    let r = try await sos.trigger(category: "bencana", message: "Integrasi iOS SDK")
    check(r.id != nil, "IT: laporan live terkirim")
    let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
    check(try await sos.attach(r.localId, data: png, contentType: "image/png").ready, "IT: lampiran ke MinIO ready")
    let d = try await http("GET", "/portal/reports/\(r.id!)", token: token)
    let media = d["media"] as! [[String: Any]]
    let (_, res) = try await URLSession.shared.data(from: URL(string: media[0]["url"] as! String)!)
    check(media.count == 1 && (res as! HTTPURLResponse).statusCode == 200 && (d["device"] as? [String: Any])?["platform"] as? String == "ios", "IT: tampil di portal + file terbaca")
    check(try await sos.cancel(r.localId, reason: "uji selesai")?.status == .cancelled, "IT: batal")
    sos.shutdown()
}

print("\n\(passed) lolos, \(failed) gagal")
exit(failed == 0 ? 0 : 1)
