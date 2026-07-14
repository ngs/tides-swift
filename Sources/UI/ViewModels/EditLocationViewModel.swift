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
            let latitude = Self.parseCoordinate(latitudeText),
            let longitude = Self.parseCoordinate(longitudeText),
            latitude.isFinite, longitude.isFinite,
            (-90...90).contains(latitude),
            (-180...180).contains(longitude)
        else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Parses a coordinate component, accepting both "." and "," as the
    /// decimal separator: decimal-pad keyboards insert "," in many locales.
    /// Plain `Double(_:)` runs first so a "." value can never be re-read
    /// through a locale that treats "." as a grouping separator.
    private static func parseCoordinate(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let value = Double(trimmed) { return value }
        return Double(trimmed.replacingOccurrences(of: ",", with: "."))
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
        !isSaving && !isRefreshing && !trimmedName.isEmpty && enteredCoordinate != nil
    }

    /// True while the parameters are being re-downloaded for the saved
    /// coordinate (`refreshParameters()`), as opposed to the download a move
    /// triggers on save.
    public private(set) var isRefreshing = false

    /// A refresh re-downloads the parameters of the location *as saved*, so it
    /// is offered only while the pin has not been moved: saving a moved pin
    /// downloads parameters for the new coordinate anyway.
    public var canRefreshParameters: Bool {
        !isSaving && !isRefreshing && !coordinateChanged
    }

    /// Span limits for the zoom controls, matching the add-location map.
    public static let defaultSpanDegrees = 0.05
    public static let minimumSpanDegrees = 0.002
    public static let maximumSpanDegrees = 120.0

    /// Region the map currently shows, kept in sync by the view.
    public private(set) var visibleRegion: MKCoordinateRegion?
    /// Region the map should move to, consumed by the view. `MKCoordinateRegion`
    /// is not `Equatable`, so requests carry an identity SwiftUI can observe.
    public private(set) var pendingCamera: CameraTarget?

    /// A request to move the map camera.
    public struct CameraTarget: Equatable, Identifiable, Sendable {
        public let id: UUID
        public let latitude: Double
        public let longitude: Double
        public let spanDegrees: Double

        public init(
            id: UUID = UUID(),
            latitude: Double,
            longitude: Double,
            spanDegrees: Double
        ) {
            self.id = id
            self.latitude = latitude
            self.longitude = longitude
            self.spanDegrees = spanDegrees
        }

        public var region: MKCoordinateRegion {
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                span: MKCoordinateSpan(
                    latitudeDelta: spanDegrees,
                    longitudeDelta: spanDegrees
                )
            )
        }
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
            span: MKCoordinateSpan(
                latitudeDelta: Self.defaultSpanDegrees,
                longitudeDelta: Self.defaultSpanDegrees
            )
        )
    }

    /// Sets the coordinate fields from a map tap.
    public func select(coordinate: CLLocationCoordinate2D) {
        latitudeText = String(format: "%.5f", coordinate.latitude)
        longitudeText = String(format: "%.5f", coordinate.longitude)
    }

    // MARK: - Camera

    public func mapCameraChanged(to region: MKCoordinateRegion) {
        visibleRegion = region
    }

    /// Consumes `pendingCamera` after the view has applied it.
    public func consumePendingCamera() {
        pendingCamera = nil
    }

    public func zoomIn() {
        scaleZoom(by: 0.5)
    }

    public func zoomOut() {
        scaleZoom(by: 2.0)
    }

    /// Multiplies the visible span, clamped to the supported zoom range.
    private func scaleZoom(by factor: Double) {
        let current = visibleRegion ?? pendingCamera?.region ?? region
        let scaled = current.span.latitudeDelta * factor
        let span = min(max(scaled, Self.minimumSpanDegrees), Self.maximumSpanDegrees)
        let target = CameraTarget(
            latitude: current.center.latitude,
            longitude: current.center.longitude,
            spanDegrees: span
        )
        pendingCamera = target
        visibleRegion = target.region
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

    /// Re-downloads the harmonic parameters for the coordinate the location is
    /// saved at, without moving or renaming it. The point of it is to pick up a
    /// server-side improvement — a new tidal model, a nearby harmonic station —
    /// for a location that was added long ago.
    ///
    /// A failed fetch leaves the stored parameters alone: they are what keeps
    /// the location predicting offline.
    ///
    /// Returns `true` when the parameters were replaced.
    @discardableResult
    public func refreshParameters() async -> Bool {
        guard canRefreshParameters else { return false }
        isRefreshing = true
        errorMessage = nil
        defer { isRefreshing = false }

        do {
            let parameters = try await client.fetchParameters(
                latitude: location.latitude,
                longitude: location.longitude
            )
            try location.updateParameters(parameters)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
