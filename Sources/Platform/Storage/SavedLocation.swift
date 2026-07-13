import Foundation
import SwiftData
import TidesCore

/// A tide location saved by the user. The harmonic parameters downloaded from
/// tides-api are persisted as JSON so all tide predictions work fully offline.
@Model
public final class SavedLocation {
    public var name: String
    public var latitude: Double
    public var longitude: Double
    /// Raw JSON of `HarmonicParameters` as returned by the API.
    public var parametersJSON: Data
    /// When the parameters were downloaded.
    public var fetchedAt: Date
    public var createdAt: Date
    /// Position in the user-ordered list. Has a default so stores written
    /// before reordering existed migrate without a version bump; ties are
    /// broken by `createdAt`.
    public var sortOrder: Int = 0

    public init(
        name: String,
        latitude: Double,
        longitude: Double,
        parametersJSON: Data,
        fetchedAt: Date = .now,
        createdAt: Date = .now,
        sortOrder: Int = 0
    ) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.parametersJSON = parametersJSON
        self.fetchedAt = fetchedAt
        self.createdAt = createdAt
        self.sortOrder = sortOrder
    }

    public convenience init(
        name: String,
        latitude: Double,
        longitude: Double,
        parameters: HarmonicParameters,
        fetchedAt: Date = .now,
        sortOrder: Int = 0
    ) throws {
        self.init(
            name: name,
            latitude: latitude,
            longitude: longitude,
            parametersJSON: try Self.encode(parameters),
            fetchedAt: fetchedAt,
            sortOrder: sortOrder
        )
    }

    /// Sort used everywhere the saved locations are listed.
    public static var listSortDescriptors: [SortDescriptor<SavedLocation>] {
        [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
    }

    /// Applies a drag-and-drop move to an ordered list and renumbers
    /// `sortOrder` so the new order survives a relaunch.
    ///
    /// `locations` must already be in display order, and `destination` is the
    /// index the rows are dropped *before*, as SwiftUI's `onMove` reports it.
    public static func move(
        _ locations: [SavedLocation],
        fromOffsets source: IndexSet,
        toOffset destination: Int
    ) {
        var reordered = locations
        reordered.move(fromOffsets: source, toOffset: destination)
        renumber(reordered)
    }

    /// Assigns a contiguous `sortOrder` following the array order.
    public static func renumber(_ locations: [SavedLocation]) {
        for (index, location) in locations.enumerated() where location.sortOrder != index {
            location.sortOrder = index
        }
    }

    /// Position a newly saved location takes: after everything already saved.
    public static func nextSortOrder(after locations: [SavedLocation]) -> Int {
        (locations.map(\.sortOrder).max() ?? -1) + 1
    }

    /// Decoded harmonic parameters, or `nil` if the stored JSON is corrupt.
    public var parameters: HarmonicParameters? {
        try? HarmonicParameters.decoder().decode(HarmonicParameters.self, from: parametersJSON)
    }

    /// Encodes harmonic parameters for storage in `parametersJSON`.
    public static func encode(_ parameters: HarmonicParameters) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(parameters)
    }

    /// Renames the location. Blank names are ignored.
    public func rename(to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        name = trimmed
    }

    /// Moves the location to a new coordinate, replacing its parameters with
    /// the ones freshly downloaded for that coordinate.
    public func move(
        latitude newLatitude: Double,
        longitude newLongitude: Double,
        parameters newParameters: HarmonicParameters,
        fetchedAt newFetchedAt: Date = .now
    ) throws {
        parametersJSON = try Self.encode(newParameters)
        latitude = newLatitude
        longitude = newLongitude
        fetchedAt = newFetchedAt
    }
}
