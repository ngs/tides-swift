import CoreLocation
import Foundation
import MapKit

/// Abstraction over reverse geocoding so view models can be unit tested.
public protocol ReverseGeocoding: Sendable {
    /// Returns a human-readable place name for a coordinate, or `nil` if
    /// geocoding fails (e.g. open ocean or no network).
    func suggestedName(latitude: Double, longitude: Double) async -> String?
}

/// Suggests a name for a coordinate, preferring nearby landmarks over the
/// coarse names reverse geocoding returns offshore.
///
/// Tide points usually sit on the water, where `CLGeocoder` only knows island-
/// or region-scale names (e.g. "Honshu"). To keep suggestions useful this
/// first looks for a point of interest near the coordinate (harbours, beaches,
/// marinas…), and only then falls back to reverse geocoding, from the most
/// specific component to the least. Region-scale components (administrative
/// area, country) are never used: no suggestion is better than "Honshu".
public struct CLReverseGeocoder: ReverseGeocoding {
    /// Radius of the nearby point-of-interest search, in meters.
    private let poiSearchRadius: CLLocationDistance

    public init(poiSearchRadius: CLLocationDistance = 3_000) {
        self.poiSearchRadius = poiSearchRadius
    }

    public func suggestedName(latitude: Double, longitude: Double) async -> String? {
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }

        if let pointOfInterest = await nearestPointOfInterest(at: coordinate) {
            return pointOfInterest
        }
        return await reverseGeocodedName(at: coordinate)
    }

    /// Nearest named place within `poiSearchRadius` of the coordinate.
    private func nearestPointOfInterest(at coordinate: CLLocationCoordinate2D) async -> String? {
        let request = MKLocalPointsOfInterestRequest(
            center: coordinate,
            radius: poiSearchRadius
        )
        guard let response = try? await MKLocalSearch(request: request).start() else {
            return nil
        }

        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let nearest = response.mapItems
            .compactMap { item -> (name: String, distance: CLLocationDistance)? in
                guard let name = item.name else { return nil }
                let itemCoordinate = item.placemark.coordinate
                guard CLLocationCoordinate2DIsValid(itemCoordinate) else { return nil }
                let distance = origin.distance(
                    from: CLLocation(
                        latitude: itemCoordinate.latitude,
                        longitude: itemCoordinate.longitude
                    )
                )
                return (name, distance)
            }
            .min { $0.distance < $1.distance }
        return nearest?.name
    }

    /// Reverse geocoded name, from the most specific component to the least.
    private func reverseGeocodedName(at coordinate: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard
            let placemark = try? await CLGeocoder()
                .reverseGeocodeLocation(location)
                .first
        else {
            return nil
        }

        let candidates: [String?] = [
            placemark.areasOfInterest?.first,
            placemark.subLocality,
            placemark.locality,
            placemark.inlandWater,
            placemark.subAdministrativeArea
        ]
        return candidates.compactMap { $0 }.first
    }
}
