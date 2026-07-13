// MapKit's search APIs (MKLocalSearch) are unavailable on watchOS, and the
// watch app never adds locations: it only reads the ones synced from the
// phone. Excluding the file keeps TidesPlatform buildable for watchOS.
#if !os(watchOS)
import CoreLocation
import Foundation
import MapKit

/// A place returned by a search, ready to be shown in a result list and
/// turned into a map selection.
public struct PlaceSuggestion: Identifiable, Equatable, Sendable {
    public let id: UUID
    /// Primary name, e.g. "Enoshima".
    public let name: String
    /// Secondary line, e.g. the address.
    public let subtitle: String
    public let latitude: Double
    public let longitude: Double

    public init(
        id: UUID = UUID(),
        name: String,
        subtitle: String,
        latitude: Double,
        longitude: Double
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.latitude = latitude
        self.longitude = longitude
    }

    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// Abstraction over place search so view models can be unit tested.
public protocol PlaceSearching: Sendable {
    /// Searches for places matching an address or name, biased towards
    /// `region` when one is supplied.
    func search(query: String, near region: MKCoordinateRegion?) async throws -> [PlaceSuggestion]
}

/// `MKLocalSearch`-backed implementation.
public struct MKPlaceSearchService: PlaceSearching {
    public init() {}

    public func search(
        query: String,
        near region: MKCoordinateRegion?
    ) async throws -> [PlaceSuggestion] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        if let region {
            request.region = region
        }

        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.compactMap { item in
            let coordinate = item.placemark.coordinate
            guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }
            return PlaceSuggestion(
                name: item.name ?? item.placemark.title ?? trimmed,
                subtitle: Self.subtitle(for: item.placemark),
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
        }
    }

    /// Address line under the place name, without repeating the name itself.
    private static func subtitle(for placemark: MKPlacemark) -> String {
        let parts = [
            placemark.subLocality,
            placemark.locality,
            placemark.administrativeArea,
            placemark.country
        ]
        .compactMap { $0 }
        return parts.isEmpty ? (placemark.title ?? "") : parts.joined(separator: ", ")
    }
}
#endif
