import CoreLocation
import Foundation

/// 获取当前位置（供天气等服务使用）
/// @author jiali.qiu
@MainActor
final class LocationService: NSObject, ObservableObject {
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var lastLocation: CLLocation?
    @Published var lastError: String?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        authorizationStatus = manager.authorizationStatus
    }

    func requestAuthorizationIfNeeded() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            break
        }
    }

    func fetchCurrentLocation() async -> CLLocation? {
        requestAuthorizationIfNeeded()
        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            lastError = "需要位置权限以获取本地天气"
            return nil
        }

        if let cached = lastLocation,
           abs(cached.timestamp.timeIntervalSinceNow) < 900 {
            return cached
        }

        return await withCheckedContinuation { continuation in
            var resumed = false
            resumeFetch = { location in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: location)
            }
            manager.requestLocation()
        }
    }

    private var resumeFetch: ((CLLocation?) -> Void)?
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            lastLocation = locations.last
            lastError = nil
            resumeFetch?(locations.last)
            resumeFetch = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            lastError = error.localizedDescription
            resumeFetch?(lastLocation)
            resumeFetch = nil
        }
    }
}
