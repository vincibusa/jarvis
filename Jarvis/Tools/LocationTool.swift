import Foundation
import CoreLocation

final class LocationTool: NSObject, CLLocationManagerDelegate {

    private let locationManager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    // MARK: - Public

    func getCurrentLocation() async throws -> String {
        let location = try await fetchLocation()
        return try await reverseGeocode(location)
    }

    // MARK: - Private

    private func fetchLocation() async throws -> CLLocation {
        try await withCheckedThrowingContinuation { [weak self] cont in
            guard let self else {
                cont.resume(throwing: LocationError.unavailable)
                return
            }
            self.continuation = cont
            let status = self.locationManager.authorizationStatus
            switch status {
            case .notDetermined:
                self.locationManager.requestWhenInUseAuthorization()
            case .authorizedWhenInUse, .authorizedAlways:
                self.locationManager.requestLocation()
            case .denied, .restricted:
                cont.resume(throwing: LocationError.denied)
                self.continuation = nil
            @unknown default:
                cont.resume(throwing: LocationError.unavailable)
                self.continuation = nil
            }
        }
    }

    private func reverseGeocode(_ location: CLLocation) async throws -> String {
        let geocoder = CLGeocoder()
        let placemarks = try await geocoder.reverseGeocodeLocation(location)
        guard let placemark = placemarks.first else {
            return "Posizione ottenuta: \(location.coordinate.latitude), \(location.coordinate.longitude)"
        }

        var parts: [String] = []
        if let city = placemark.locality { parts.append(city) }
        if let street = placemark.thoroughfare {
            var streetPart = street
            if let number = placemark.subThoroughfare {
                streetPart += " \(number)"
            }
            parts.append(streetPart)
        }
        if let postalCode = placemark.postalCode { parts.append(postalCode) }

        let address = parts.joined(separator: ", ")
        return "Ti trovi a \(address)."
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        continuation?.resume(returning: location)
        continuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            continuation?.resume(throwing: LocationError.denied)
            continuation = nil
        default:
            break
        }
    }

    // MARK: - Errors

    enum LocationError: LocalizedError {
        case denied
        case unavailable

        var errorDescription: String? {
            switch self {
            case .denied:    return "Accesso alla posizione negato. Abilitalo nelle Impostazioni."
            case .unavailable: return "Posizione non disponibile al momento."
            }
        }
    }
}
