import Foundation

/// Penyimpanan antrian laporan offline.
public protocol QueueStore: Sendable {
    func load() -> [[String: Any]]
    func save(_ items: [[String: Any]])
}

/// Default: UserDefaults (bertahan saat app ditutup).
public final class UserDefaultsQueueStore: QueueStore, @unchecked Sendable {
    private let key: String
    private let defaults: UserDefaults
    private let lock = NSLock()
    public init(key: String, defaults: UserDefaults = .standard) { self.key = key; self.defaults = defaults }
    public func load() -> [[String: Any]] {
        lock.lock(); defer { lock.unlock() }
        guard let d = defaults.data(forKey: key), let a = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] else { return [] }
        return a
    }
    public func save(_ items: [[String: Any]]) {
        lock.lock(); defer { lock.unlock() }
        if items.isEmpty { defaults.removeObject(forKey: key) } else if let d = try? JSONSerialization.data(withJSONObject: items) { defaults.set(d, forKey: key) }
    }
}

public final class MemoryQueueStore: QueueStore, @unchecked Sendable {
    private var items: [[String: Any]] = []
    private let lock = NSLock()
    public init() {}
    public func load() -> [[String: Any]] { lock.lock(); defer { lock.unlock() }; return items }
    public func save(_ items: [[String: Any]]) { lock.lock(); self.items = items; lock.unlock() }
}
