import Foundation

public let siagaSOSVersion = "0.1.0"

/// Klien SiagaSOS untuk iOS (async/await). Satu instance per aplikasi; panggil `shutdown()` saat logout.
///
/// ```swift
/// let sos = try SiagaSOS(apiKey: "pk_test_...", user: SosUser(ref: uid, name: nama), locationProvider: CoreLocationProvider())
/// sos.addListener(SosListener(onStatus: { r in render(r) }))
/// let r = try await sos.trigger(category: "kriminal")
/// _ = try await sos.attach(r.localId, data: jpeg, contentType: "image/jpeg")
/// ```
/// Kontrak lintas platform: docs/SDK_PROTOCOL.md.
public final class SiagaSOS: @unchecked Sendable {
    public let apiKey: String
    /// Bundle identifier aplikasi; harus terdaftar di allowed_bundle_ids app di portal.
    public let bundleId: String
    public let mode: SosMode
    let baseURL: String
    let sourceKey: String?
    let user: SosUser?
    let liveLocation: Bool
    let pollInterval: TimeInterval
    let locationTimeout: TimeInterval
    let locationProvider: LocationProvider?
    let queue: QueueStore
    let session: URLSession

    private let lock = NSLock()
    private var reports: [String: ActiveReport] = [:]
    private var trackers: [String: Task<Void, Never>] = [:]
    private var listeners: [UUID: SosListener] = [:]
    private var config: SdkConfig?
    private var retryTask: Task<Void, Never>?
    private var retryDelay: TimeInterval = 2
    private var flushing = false
    private var closed = false
    private let queueLock = NSLock()

    public init(apiKey: String, bundleId: String = Bundle.main.bundleIdentifier ?? "unknown", sourceKey: String? = nil, user: SosUser? = nil,
                baseURL: String = "https://api.siagasos.id", liveLocation: Bool = true, pollInterval: TimeInterval = 4,
                locationTimeout: TimeInterval = 8, locationProvider: LocationProvider? = nil, queueStore: QueueStore? = nil,
                session: URLSession = .shared) throws {
        guard let m = apiKey.range(of: "^pk_(live|test)_", options: .regularExpression) else {
            throw SiagaSOSError(status: 0, code: "invalid_api_key", message: "apiKey harus publishable key (pk_live_... / pk_test_...)")
        }
        self.apiKey = apiKey
        self.bundleId = bundleId
        self.mode = apiKey[m].hasPrefix("pk_live") ? .live : .test
        self.baseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        self.sourceKey = sourceKey
        self.user = user
        self.liveLocation = liveLocation
        self.pollInterval = pollInterval
        self.locationTimeout = locationTimeout
        self.locationProvider = locationProvider
        self.queue = queueStore ?? UserDefaultsQueueStore(key: "siagasos.queue.\(apiKey.prefix(16))")
        self.session = session
        Task { await self.flush() } // kirim sisa antrian dari sesi sebelumnya
    }

    // MARK: listener
    @discardableResult
    public func addListener(_ l: SosListener) -> UUID { let id = UUID(); locked { listeners[id] = l }; return id }
    public func removeListener(_ id: UUID) { locked { listeners[id] = nil } }
    public var activeReports: [ActiveReport] { locked { reports.values.filter { !$0.status.isTerminal } } }

    private func locked<T>(_ f: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return f() }
    private func emit(_ f: @escaping @MainActor @Sendable (SosListener) -> Void) {
        let ls = locked { Array(listeners.values) }
        Task { @MainActor in ls.forEach(f) }
    }

    // MARK: HTTP
    func request(_ method: String, _ path: String, body: [String: Any]? = nil, idempotencyKey: String? = nil) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: baseURL + path)!, timeoutInterval: 20)
        req.httpMethod = method
        req.setValue(apiKey, forHTTPHeaderField: "X-SOS-Key")
        req.setValue(bundleId, forHTTPHeaderField: "X-SOS-Bundle")
        if let k = idempotencyKey { req.setValue(k, forHTTPHeaderField: "Idempotency-Key") }
        if let b = body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: b)
        }
        let data: Data, res: URLResponse
        do { (data, res) = try await session.data(for: req) } catch {
            throw SiagaSOSError(status: 0, code: "network_error", message: "Tidak ada koneksi: \(error.localizedDescription)")
        }
        let code = (res as? HTTPURLResponse)?.statusCode ?? 0
        let json = (data.isEmpty ? nil : try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if code >= 400 {
            let e = json["error"] as? [String: Any]
            throw SiagaSOSError(status: code, code: e?["code"] as? String ?? "http_error", message: e?["message"] as? String ?? "HTTP \(code)")
        }
        return json
    }

    /// Konfigurasi tombol dari portal (di-cache).
    public func getConfig() async throws -> SdkConfig {
        if let c = locked({ config }) { return c }
        let c = SdkConfig(try await request("GET", "/v1/sdk/config"))
        locked { config = c }
        return c
    }

    // MARK: trigger + antrian offline
    /// Kirim SOS. Bila offline, laporan masuk antrian persisten (status `.queued`) dan dikirim otomatis.
    /// Error permanen (kunci/bundle salah) dilempar.
    @discardableResult
    public func trigger(category: String = "general", message: String? = nil, metadata: [String: Any]? = nil) async throws -> ActiveReport {
        var loc: SosLocation?
        if let p = locationProvider { loc = await p.currentLocation(timeout: locationTimeout) }
        var body: [String: Any] = [
            "category": category,
            "device": ["platform": "ios", "sdk_version": "ios-\(siagaSOSVersion)", "os": ProcessInfo.processInfo.operatingSystemVersionString],
            "client_created_at": ISO8601DateFormatter().string(from: Date()),
        ]
        body["message"] = message
        body["source_key"] = sourceKey
        body["location"] = loc?.json
        body["reporter"] = user?.json
        body["metadata"] = metadata
        let item: [String: Any] = ["localId": UUID().uuidString.lowercased(), "idem": UUID().uuidString.lowercased(),
                                   "createdAt": Date().timeIntervalSince1970, "body": body]
        let queued = ActiveReport(localId: item["localId"] as! String, id: nil, status: .queued,
                                  statusMessage: "Menunggu sinyal, laporan akan dikirim otomatis.", mode: mode, category: category, createdAt: Date())
        locked { reports[queued.localId] = queued }
        queueLock.lock(); queue.save(queue.load() + [item]); queueLock.unlock()
        do {
            return try await send(item)
        } catch let e as SiagaSOSError {
            if !e.isRetryable {
                removeFromQueue(queued.localId)
                locked { reports[queued.localId] = nil }
                emit { $0.onError?(e) }
                throw e
            }
            emit { $0.onQueued?(queued) }
            emit { $0.onStatus?(queued) }
            scheduleRetry()
            return queued
        }
    }

    private func send(_ item: [String: Any]) async throws -> ActiveReport {
        let data = try await request("POST", "/v1/sdk/reports", body: item["body"] as? [String: Any], idempotencyKey: item["idem"] as? String)
        let localId = item["localId"] as! String
        removeFromQueue(localId)
        let prev = locked { reports[localId] }
        let r = ActiveReport(localId: localId, id: data["id"] as? String, status: SosStatus(rawValue: data["status"] as? String ?? "open") ?? .open,
                             statusMessage: data["status_message"] as? String, mode: mode,
                             category: (item["body"] as? [String: Any])?["category"] as? String ?? "general",
                             createdAt: prev?.createdAt ?? Date(timeIntervalSince1970: item["createdAt"] as? Double ?? Date().timeIntervalSince1970))
        locked { reports[localId] = r }
        emit { $0.onSent?(r) }
        emit { $0.onStatus?(r) }
        track(r)
        return r
    }

    private func removeFromQueue(_ localId: String) {
        queueLock.lock(); defer { queueLock.unlock() }
        queue.save(queue.load().filter { ($0["localId"] as? String) != localId })
    }

    /// Kirim ulang antrian sekarang. Otomatis dengan backoff; panggil juga saat app kembali ke foreground.
    public func flush() async {
        let go = locked { () -> Bool in if flushing || closed { return false }; flushing = true; return true }
        guard go else { return }
        defer { locked { flushing = false } }
        queueLock.lock(); let items = queue.load(); queueLock.unlock()
        for item in items {
            let localId = item["localId"] as? String ?? ""
            locked {
                if reports[localId] == nil {
                    reports[localId] = ActiveReport(localId: localId, id: nil, status: .queued, statusMessage: nil, mode: mode,
                                                    category: (item["body"] as? [String: Any])?["category"] as? String ?? "general", createdAt: Date())
                }
            }
            do {
                _ = try await send(item)
                locked { retryDelay = 2 }
            } catch let e as SiagaSOSError {
                if e.isRetryable { scheduleRetry(); return }
                removeFromQueue(localId)
                locked { reports[localId] = nil }
                emit { $0.onError?(e) }
            } catch {}
        }
    }

    private func scheduleRetry() {
        let delay: TimeInterval? = locked {
            if closed || retryTask != nil { return nil }
            let d = retryDelay
            retryDelay = min(retryDelay * 2, 60)
            return d
        }
        guard let d = delay else { return }
        let t = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(d * 1e9))
            self?.locked { self?.retryTask = nil }
            await self?.flush()
        }
        locked { retryTask = t }
    }

    // MARK: status + lokasi live
    private func track(_ r: ActiveReport) {
        guard !r.status.isTerminal, let id = r.id else { return }
        let started = locked { () -> Bool in if closed || trackers[r.localId] != nil { return false }; return true }
        guard started else { return }
        let t = Task { [weak self] in
            guard let self else { return }
            var lastLocation = Date.distantPast
            let interval = TimeInterval((try? await self.getConfig().liveLocationIntervalS) ?? 15)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(self.pollInterval * 1e9))
                if Task.isCancelled { break }
                if let data = try? await self.request("GET", "/v1/sdk/reports/\(id)"), self.update(r.localId, data).status.isTerminal { break }
                if self.liveLocation, let p = self.locationProvider, Date().timeIntervalSince(lastLocation) >= interval {
                    lastLocation = Date()
                    if let loc = await p.currentLocation(timeout: self.locationTimeout) {
                        var b = loc.json
                        b["recorded_at"] = ISO8601DateFormatter().string(from: Date())
                        if let res = try? await self.request("POST", "/v1/sdk/reports/\(id)/locations", body: b), (res["accepted"] as? Bool) == false { break }
                    }
                }
            }
            self.locked { _ = self.trackers.removeValue(forKey: r.localId) }
        }
        locked { trackers[r.localId] = t }
    }

    @discardableResult
    private func update(_ localId: String, _ data: [String: Any]) -> ActiveReport {
        let (cur, next) = locked { () -> (ActiveReport, ActiveReport) in
            let cur = reports[localId]!
            var n = cur
            n.id = data["id"] as? String ?? cur.id
            n.status = SosStatus(rawValue: data["status"] as? String ?? "") ?? cur.status
            n.statusMessage = data["status_message"] as? String
            reports[localId] = n
            return (cur, n)
        }
        if next.status != cur.status || next.statusMessage != cur.statusMessage { emit { $0.onStatus?(next) } }
        return next
    }

    private func find(_ idOrLocalId: String) -> ActiveReport? {
        locked { reports[idOrLocalId] ?? reports.values.first { $0.id == idOrLocalId } }
    }

    // MARK: batal
    /// Batalkan (salah tekan). Hanya saat status `open`; error `cannot_cancel` bila sudah diterima petugas.
    @discardableResult
    public func cancel(_ idOrLocalId: String, reason: String? = nil) async throws -> ActiveReport? {
        let entry = find(idOrLocalId)
        if let e = entry, e.id == nil {
            removeFromQueue(e.localId)
            var c = e
            c.status = .cancelled
            c.statusMessage = "Laporan dibatalkan."
            locked { reports[e.localId] = c }
            emit { $0.onStatus?(c) }
            return c
        }
        var b: [String: Any] = [:]
        b["reason"] = reason
        let data = try await request("POST", "/v1/sdk/reports/\(entry?.id ?? idOrLocalId)/cancel", body: b)
        guard let e = entry else { return nil }
        let n = update(e.localId, data)
        if n.status.isTerminal { locked { trackers.removeValue(forKey: e.localId)?.cancel() } }
        return n
    }

    // MARK: lampiran
    /// Lampirkan foto/video/suara. File diunggah langsung ke storage (URL bertanda tangan), lalu tampil realtime di dashboard.
    /// Bila laporan masih di antrian offline, menunggu sampai terkirim (maks. `waitTimeout`).
    public func attach(_ idOrLocalId: String, data: Data, contentType: String, durationS: Double? = nil,
                       waitTimeout: TimeInterval = 120) async throws -> MediaPublic {
        let id = try await waitForServerId(idOrLocalId, timeout: waitTimeout)
        var b: [String: Any] = ["content_type": contentType, "size_bytes": data.count]
        b["duration_s"] = durationS
        let out = try await request("POST", "/v1/sdk/reports/\(id)/media", body: b)
        guard let up = out["upload"] as? [String: Any], let url = URL(string: up["url"] as? String ?? ""),
              let mediaId = (out["media"] as? [String: Any])?["id"] as? String else {
            throw SiagaSOSError(status: 0, code: "bad_response", message: "Balasan upload tidak valid")
        }
        var put = URLRequest(url: url, timeoutInterval: 300)
        put.httpMethod = "PUT"
        (up["headers"] as? [String: String] ?? [:]).forEach { put.setValue($0.value, forHTTPHeaderField: $0.key) }
        let res: URLResponse
        do { (_, res) = try await session.upload(for: put, from: data) } catch {
            throw SiagaSOSError(status: 0, code: "network_error", message: "Upload gagal: \(error.localizedDescription)")
        }
        let code = (res as? HTTPURLResponse)?.statusCode ?? 0
        if code >= 300 { throw SiagaSOSError(status: code, code: "upload_failed", message: "Upload gagal (\(code))") }
        return MediaPublic(try await request("POST", "/v1/sdk/reports/\(id)/media/\(mediaId)/complete"))
    }

    private func waitForServerId(_ idOrLocalId: String, timeout: TimeInterval) async throws -> String {
        guard let r = find(idOrLocalId) else { return idOrLocalId } // id server dari sesi lain
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let id = find(r.localId)?.id { return id }
            try await Task.sleep(nanoseconds: 300_000_000)
        }
        throw SiagaSOSError(status: 0, code: "not_sent", message: "Laporan belum terkirim; lampiran dibatalkan")
    }

    /// Hentikan polling, lokasi live, dan retry. Antrian tetap tersimpan untuk sesi berikutnya.
    public func shutdown() {
        let ts: [Task<Void, Never>] = locked {
            closed = true
            let all = Array(trackers.values) + [retryTask].compactMap { $0 }
            trackers.removeAll(); retryTask = nil; listeners.removeAll()
            return all
        }
        ts.forEach { $0.cancel() }
    }
}
