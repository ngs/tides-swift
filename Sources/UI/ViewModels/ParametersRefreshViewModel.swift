import Foundation
import Observation
import TidesCore
import TidesPlatform

/// Re-downloads the harmonic parameters of saved locations, in place.
///
/// Parameters are fetched once when a location is added and then used offline
/// forever, so a location keeps predicting from whatever the server knew that
/// day. This view model is how the user picks up a later server-side
/// improvement — a new tidal model, a nearby harmonic station, the redesigned
/// datum contract — without deleting and re-adding the location.
///
/// Locations are refreshed one at a time: the fetch is cheap, the list is
/// short, and a serial walk keeps the progress count honest and the API calls
/// gentle. A location that fails is left with the parameters it already had —
/// stale data still predicts, missing data does not.
@MainActor
@Observable
public final class ParametersRefreshViewModel {
    /// How far a running refresh has got.
    public struct Progress: Equatable, Sendable {
        public var completed: Int
        public var total: Int

        public init(completed: Int, total: Int) {
            self.completed = completed
            self.total = total
        }
    }

    /// Progress of the refresh in flight, or `nil` when idle.
    public private(set) var progress: Progress?
    /// Names of the locations the last refresh could not update.
    public private(set) var failedNames: [String] = []
    /// Set when the last refresh updated nothing or only part of the list.
    public var errorMessage: String?

    private let client: any TidesAPIClientProtocol

    public init(client: any TidesAPIClientProtocol = TidesAPIClient()) {
        self.client = client
    }

    public var isRefreshing: Bool { progress != nil }

    /// Re-downloads the parameters of every location, keeping each coordinate.
    ///
    /// Returns the number of locations that were updated. Failures do not stop
    /// the walk — they are collected into `failedNames` and reported through
    /// `errorMessage` at the end, so one unreachable point cannot deny the
    /// others their refresh.
    @discardableResult
    public func refresh(_ locations: [SavedLocation]) async -> Int {
        guard !isRefreshing, !locations.isEmpty else { return 0 }
        progress = Progress(completed: 0, total: locations.count)
        failedNames = []
        errorMessage = nil
        defer { progress = nil }

        var updated = 0
        var failures: [String] = []
        for location in locations {
            do {
                let parameters = try await client.fetchParameters(
                    latitude: location.latitude,
                    longitude: location.longitude
                )
                try location.updateParameters(parameters)
                updated += 1
            } catch {
                failures.append(location.name)
            }
            progress?.completed += 1
        }

        failedNames = failures
        if !failures.isEmpty {
            errorMessage = String(
                localized: "These locations could not be updated: \(failures.formatted())"
            )
        }
        return updated
    }
}
