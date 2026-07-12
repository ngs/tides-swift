import CoreLocation
import Foundation
import MapKit
import Observation
import TidesCore
import TidesPlatform

/// View model for editing a saved location: rename it, and/or move it to a new
/// coordinate. Moving re-downloads the harmonic parameters, because they are
/// specific to the coordinate.
@MainActor
@Observable
public final class EditLocationViewModel {
    public let location: SavedLocation

    public var name: String
    public var latitudeText: String
    public var longitudeText: String
    public private(set) var isSaving = false
    public var errorMessage: String?

    private let client: any TidesAPIClientProtocol

    public init(
        location: SavedLocation,
        client: any TidesAPIClientProtocol = TidesAPIClient()
    ) {
        self.location = location
        self.client = client
        self.name = location.name
        self.latitudeText = String(format: "%.5f", location.latitude)
        self.longitudeText = String(format: "%.5f", location.longitude)
    }

    /// Parsed coordinate, or `nil` when the text fields are not a valid
    /// latitude/longitude pair.
    public var enteredCoordinate: CLLocationCoordinate2D? {
        guard
            let latitude = Double(latitudeText.trimmingCharacters(in: .whitespaces)),
            let longitude = Double(longitudeText.trimmingCharacters(in: .whitespaces)),
            latitude.isFinite, longitude.isFinite,
            (-90...90).contains(latitude),
            (-180...180).contains(longitude)
        else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Precision the coordinate fields are displayed with (about 1 m). Changes
    /// smaller than this are round-trip noise from formatting the stored value,
    /// not an edit, and must not trigger a re-download.
    static let coordinateTolerance = 1e-5

    /// True when the entered coordinate differs from the stored one and thus
    /// requires new parameters.
    public var coordinateChanged: Bool {
        guard let coordinate = enteredCoordinate else { return false }
        return abs(coordinate.latitude - location.latitude) > Self.coordinateTolerance
            || abs(coordinate.longitude - location.longitude) > Self.coordinateTolerance
    }

    public var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var canSave: Bool {
        !isSaving && !trimmedName.isEmpty && enteredCoordinate != nil
    }

    /// Region to show the edited coordinate on a map.
    public var region: MKCoordinateRegion {
        let center = enteredCoordinate
            ?? CLLocationCoordinate2D(
                latitude: location.latitude,
                longitude: location.longitude
            )
        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
    }

    /// Sets the coordinate fields from a map tap.
    public func select(coordinate: CLLocationCoordinate2D) {
        latitudeText = String(format: "%.5f", coordinate.latitude)
        longitudeText = String(format: "%.5f", coordinate.longitude)
    }

    /// Applies the edits. When the coordinate changed, new harmonic parameters
    /// are downloaded first, so the location is never left with parameters that
    /// belong to a different point.
    ///
    /// Returns `true` when the location was updated.
    @discardableResult
    public func save() async -> Bool {
        guard canSave, let coordinate = enteredCoordinate else { return false }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        if coordinateChanged {
            do {
                let parameters = try await client.fetchParameters(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude
                )
                try location.move(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                    parameters: parameters
                )
            } catch {
                errorMessage = error.localizedDescription
                return false
            }
        }

        location.rename(to: trimmedName)
        return true
    }
}
