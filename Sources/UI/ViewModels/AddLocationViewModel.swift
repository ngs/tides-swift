import CoreLocation
import Foundation
import Observation
import TidesCore
import TidesPlatform

/// View model for the "add location" flow: pick a coordinate on the map,
/// download its harmonic parameters, suggest a name and save.
@MainActor
@Observable
public final class AddLocationViewModel {
    public enum Phase: Equatable {
        /// Waiting for the user to tap the map.
        case selecting
        /// Downloading parameters from the API.
        case fetching
        /// Parameters downloaded; waiting for a name to save.
        case naming
    }

    public private(set) var phase: Phase = .selecting
    public var selectedCoordinate: CLLocationCoordinate2D?
    public private(set) var fetchedParameters: HarmonicParameters?
    public var locationName = ""
    public var errorMessage: String?

    private let client: any TidesAPIClientProtocol
    private let geocoder: any ReverseGeocoding

    public init(
        client: any TidesAPIClientProtocol = TidesAPIClient(),
        geocoder: any ReverseGeocoding = CLReverseGeocoder()
    ) {
        self.client = client
        self.geocoder = geocoder
    }

    public var canFetch: Bool {
        selectedCoordinate != nil && phase != .fetching
    }

    public var canSave: Bool {
        phase == .naming
            && fetchedParameters != nil
            && !locationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Called when the user taps the map: moves the pin and resets any
    /// previously fetched parameters.
    public func select(coordinate: CLLocationCoordinate2D) {
        guard phase != .fetching else { return }
        selectedCoordinate = coordinate
        fetchedParameters = nil
        phase = .selecting
    }

    /// Downloads harmonic parameters for the selected coordinate and suggests
    /// a name via reverse geocoding.
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
            if let suggested = await geocoder.suggestedName(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            ) {
                locationName = suggested
            } else if locationName.isEmpty {
                locationName = String(localized: "New Location")
            }
            phase = .naming
        } catch {
            errorMessage = error.localizedDescription
            phase = .selecting
        }
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
