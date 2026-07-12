import Foundation
import Observation
import TidesCore

/// Local store for the watch app's tide location.
///
/// The watch keeps its own copy of a single location's harmonic parameters,
/// independent of the iOS app. Until synchronization is implemented the store
/// is normally empty and the app shows guidance instead.
///
/// Syncing saved locations from the iPhone app via WatchConnectivity is
/// planned but not implemented yet.
@MainActor
@Observable
final class WatchTideStore {
    /// A location with downloaded parameters, ready for offline prediction.
    struct StoredLocation: Codable {
        var name: String
        var parameters: HarmonicParameters
    }

    private(set) var location: StoredLocation?

    private let defaults: UserDefaults
    private static let storageKey = "watch.storedLocation"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func load() {
        guard let data = defaults.data(forKey: Self.storageKey) else {
            location = nil
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        location = try? decoder.decode(StoredLocation.self, from: data)
    }
}
