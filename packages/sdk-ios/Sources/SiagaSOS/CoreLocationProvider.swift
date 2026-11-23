#if canImport(CoreLocation)
import CoreLocation
import Foundation

/// Lokasi via CoreLocation. Meminta izin "When In Use" bila belum ditentukan; nil bila ditolak atau melewati batas waktu.
/// Tambahkan `NSLocationWhenInUseUsageDescription` di Info.plist (jelaskan bahwa lokasi dibagikan ke tim responder).
public final class CoreLocationProvider: NSObject, LocationProvider, CLLocationManagerDelegate, @unchecked Sendable {
    private var manager: CLLocationManager?
    private var continuation: CheckedContinuation<SosLocation?, Never>?
    private let lock = NSLock()

    public override init() { super.init() }

    public func currentLocation(timeout: TimeInterval) async -> SosLocation? {
        await withCheckedContinuation { (c: CheckedContinuation<SosLocation?, Never>) in
            lock.lock(); continuation = c; lock.unlock()
            DispatchQueue.main.async {
                let m = CLLocationManager()
                m.delegate = self
                m.desiredAccuracy = kCLLocationAccuracyBest
                self.manager = m
                switch m.authorizationStatus {
                case .denied, .restricted: self.finish(nil)
                case .notDetermined:
                    #if os(iOS)
                    m.requestWhenInUseAuthorization()
                    #endif
                    m.requestLocation()
                default: m.requestLocation()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { self.finish(m.location.map(Self.sos)) }
            }
        }
    }

    private static func sos(_ l: CLLocation) -> SosLocation {
        SosLocation(lat: l.coordinate.latitude, lng: l.coordinate.longitude, accuracyM: l.horizontalAccuracy >= 0 ? l.horizontalAccuracy : nil)
    }

    private func finish(_ v: SosLocation?) {
        lock.lock(); let c = continuation; continuation = nil; lock.unlock()
        c?.resume(returning: v)
        manager?.stopUpdatingLocation()
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) { finish(locations.last.map(Self.sos)) }
    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { finish(manager.location.map(Self.sos)) }
}
#endif
