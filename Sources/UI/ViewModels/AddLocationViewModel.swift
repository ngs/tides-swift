import CoreLocation
import Foundation
import MapKit
import Observation
import TidesCore
import TidesPlatform

/// View model for the "add location" flow: find a place by name or address (or
/// tap the map), download its harmonic parameters, name it and save.
@MainActor
@Observable
public final class AddLocationViewModel {
    public enum Phase: Equatable {
        /// Waiting for the user to pick a point.
        case selecting
        /// Downloading parameters from the API.
        case fetching
        /// Parameters downloaded; waiting for a name to save.
        case naming
    }

    /// Span used when zooming to a searched or selected point: close enough to
    /// place a tide point precisely, instead of the region-wide default.
    public static let selectionSpanDegrees = 0.05
    /// Span limits for the zoom controls.
    public static let minimumSpanDegrees = 0.002
    public static let maximumSpanDegrees = 120.0

    public private(set) var phase: Phase = .selecting
    public var selectedCoordinate: CLLocationCoordinate2D?
    public private(set) var fetchedParameters: HarmonicParameters?
    public var locationName = ""
    public var errorMessage: String?

    // MARK: Search

    public var searchQuery = ""
    public private(set) var searchResults: [PlaceSuggestion] = []
    public private(set) var isSearching = false

    // MARK: Map camera

    /// Region the map currently shows; kept in sync by the view so searches are
    /// biased towards it and the zoom controls can adjust it.
    public private(set) var visibleRegion: MKCoordinateRegion?

    /// A request to move the map camera to a region.
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
    /// Region the map should move to, consumed by the view. `MKCoordinateRegion`
    /// is not `Equatable`, so requests carry an identity SwiftUI can observe.
    public private(set) var pendingCamera: CameraTarget?

    private let client: any TidesAPIClientProtocol
    private let geocoder: any ReverseGeocoding
    private let placeSearch: any PlaceSearching

    public init(
        client: any TidesAPIClientProtocol = TidesAPIClient(),
        geocoder: any ReverseGeocoding = CLReverseGeocoder(),
        placeSearch: any PlaceSearching = MKPlaceSearchService()
    ) {
        self.client = client
        self.geocoder = geocoder
        self.placeSearch = placeSearch
    }

    public var canFetch: Bool {
        selectedCoordinate != nil && phase != .fetching
    }

    public var canSave: Bool {
        phase == .naming
            && fetchedParameters != nil
            && !locationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Selection

    /// Called when the user picks a point: moves the pin and resets any
    /// previously fetched parameters.
    public func select(coordinate: CLLocationCoordinate2D, zoomIn: Bool = false) {
        guard phase != .fetching else { return }
        selectedCoordinate = coordinate
        fetchedParameters = nil
        phase = .selecting
        if zoomIn {
            zoom(to: coordinate)
        }
    }

    /// Moves the pin to a search result and zooms the map to it.
    public func select(suggestion: PlaceSuggestion) {
        select(coordinate: suggestion.coordinate, zoomIn: true)
        locationName = suggestion.name
        searchQuery = suggestion.name
        searchResults = []
    }

    // MARK: - Search

    /// Searches for places matching `searchQuery`, biased towards the visible
    /// region.
    public func search() async {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        isSearching = true
        defer { isSearching = false }
        do {
            let results = try await placeSearch.search(query: query, near: visibleRegion)
            searchResults = results
            if results.isEmpty {
                errorMessage = String(localized: "No places found for this search.")
            } else {
                errorMessage = nil
            }
        } catch {
            searchResults = []
            errorMessage = error.localizedDescription
        }
    }

    public func clearSearch() {
        searchQuery = ""
        searchResults = []
        errorMessage = nil
    }

    // MARK: - Camera

    public func mapCameraChanged(to region: MKCoordinateRegion) {
        visibleRegion = region
    }

    /// Consumes `pendingCamera` after the view has applied it.
    public func consumePendingCamera() {
        pendingCamera = nil
    }

    /// Centers the map on a coordinate at a close-up zoom level.
    public func zoom(to coordinate: CLLocationCoordinate2D) {
        let span = visibleRegion.map { current in
            min(
                max(current.span.latitudeDelta, Self.minimumSpanDegrees),
                Self.selectionSpanDegrees
            )
        } ?? Self.selectionSpanDegrees
        setRegion(center: coordinate, spanDegrees: span)
    }

    public func zoomIn() {
        scaleZoom(by: 0.5)
    }

    public func zoomOut() {
        scaleZoom(by: 2.0)
    }

    /// Multiplies the visible span, clamped to the supported zoom range.
    private func scaleZoom(by factor: Double) {
        guard let region = visibleRegion ?? pendingCamera?.region else { return }
        let scaled = region.span.latitudeDelta * factor
        let span = min(max(scaled, Self.minimumSpanDegrees), Self.maximumSpanDegrees)
        setRegion(center: region.center, spanDegrees: span)
    }

    private func setRegion(center: CLLocationCoordinate2D, spanDegrees: Double) {
        let target = CameraTarget(
            latitude: center.latitude,
            longitude: center.longitude,
            spanDegrees: spanDegrees
        )
        pendingCamera = target
        visibleRegion = target.region
    }

    // MARK: - Fetch and save

    /// Downloads harmonic parameters for the selected coordinate and suggests
    /// a name for it.
    public func fetchParameters() async {
        guard let coordinate = selectedCoordinate, phase != .fetching else { return }
        phase = .fetching
        errorMessage = nil
        do {
            let parameters = try await client.fetchParameters(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
            fetchedParameters = parameters
            if locationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                locationName = await suggestedName(for: coordinate)
            }
            phase = .naming
        } catch {
            errorMessage = error.localizedDescription
            phase = .selecting
        }
    }

    /// Name proposed for a coordinate: a nearby landmark, or the coordinate
    /// itself when nothing specific is known — a region-wide name such as
    /// "Honshu" would be worse than a precise pair of numbers.
    private func suggestedName(for coordinate: CLLocationCoordinate2D) async -> String {
        if let suggested = await geocoder.suggestedName(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        ) {
            return suggested
        }
        return String(format: "%.3f, %.3f", coordinate.latitude, coordinate.longitude)
    }

    /// Builds the persistent model from the fetched parameters.
    /// Returns `nil` unless a fetch succeeded and a name was entered.
    public func makeSavedLocation() -> SavedLocation? {
        guard
            canSave,
            let coordinate = selectedCoordinate,
            let parameters = fetchedParameters
        else {
            return nil
        }
        return try? SavedLocation(
            name: locationName.trimmingCharacters(in: .whitespacesAndNewlines),
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            parameters: parameters
        )
    }
}
