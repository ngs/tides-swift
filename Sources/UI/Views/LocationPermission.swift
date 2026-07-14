import CoreLocation

/// `MapUserLocationButton` locates the user only once the app is authorized:
/// while the status is still `.notDetermined` the button shows its progress
/// indicator forever without ever posing the system prompt itself. Holding a
/// `CLLocationManager` and asking once when the map appears fills that gap.
@MainActor
final class LocationPermission {
    private let manager = CLLocationManager()

    /// Poses the when-in-use authorization prompt if the user has not been
    /// asked yet. Any other status — granted, denied or restricted — is left
    /// alone; re-requesting would be a no-op anyway.
    func requestIfNeeded() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }
}
