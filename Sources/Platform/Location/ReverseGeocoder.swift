import CoreLocation
import Foundation

/// Abstraction over reverse geocoding so view models can be unit tested.
public protocol ReverseGeocoding: Sendable {
    /// Returns a human-readable place name for a coordinate, or `nil` if
    /// geocoding fails (e.g. open ocean or no network).
    func suggestedName(latitude: Double, longitude: Double) async -> String?
}

/// CLGeocoder-backed implementation.
public struct CLReverseGeocoder: ReverseGeocoding {
    public init() {}

    public func suggestedName(latitude: Double, longitude: Double) async -> String? {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        guard
            let placemark = try? await CLGeocoder()
                .reverseGeocodeLocation(location)
                .first
        else {
            return nil
        }
        return placemark.name
            ?? placemark.locality
            ?? placemark.subAdministrativeArea
            ?? placemark.administrativeArea
    }
}
