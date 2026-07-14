import Foundation
import SwiftData
import TidesCore

/// A tide location saved by the user. The harmonic parameters downloaded from
/// tides-api are persisted as JSON so all tide predictions work fully offline.
///
/// The model is mirrored to CloudKit (see `TidesCloudKit`), which imposes two
/// rules on the schema: every persisted property must be optional or carry a
/// default value, and neither `@Attribute(.unique)` nor required relationships
/// are allowed. Every property below therefore has a default; the real values
/// always come from the initializers, the defaults only exist so CloudKit can
/// materialize a record whose fields have not arrived yet.
@Model
public final class SavedLocation {
    public var name: String = ""
    public var latitude: Double = 0
    public var longitude: Double = 0
    /// Raw JSON of `HarmonicParameters` as returned by the API.
    public var parametersJSON = Data()
    /// When the parameters were downloaded. The Unix-epoch sentinel (rather
    /// than `.distantPast`, year 1) stays within the date range CloudKit
    /// accepts when a record is materialized before its fields arrive.
    public var fetchedAt = Date(timeIntervalSince1970: 0)
    public var createdAt = Date(timeIntervalSince1970: 0)
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
    ///
    /// The reordering is spelled out rather than using SwiftUI's
    /// `move(fromOffsets:toOffset:)` so that `TidesPlatform` keeps building on
    /// watchOS, where that extension is not visible without importing SwiftUI.
    public static func move(
        _ locations: [SavedLocation],
        fromOffsets source: IndexSet,
        toOffset destination: Int
    ) {
        let moving = source.map { locations[$0] }
        var reordered = locations
        for index in source.sorted(by: >) {
            reordered.remove(at: index)
        }
        // Removing the moved rows shifts everything before `destination` down.
        let insertionIndex = destination - source.count(in: 0 ..< destination)
        reordered.insert(contentsOf: moving, at: insertionIndex)
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
    ///
    /// Parameters saved under the pre-redesign API contract are normalized on
    /// read (`migratedToCurrentDatumContract`), so every consumer — the detail
    /// screen, the widget and the watch app — sees a consistent datum without a
    /// persisted schema change or a CloudKit-synced rewrite. Fresh fetches
    /// (adding or moving a location) already carry the current contract and
    /// pass through untouched.
    public var parameters: HarmonicParameters? {
        try? HarmonicParameters.decoder()
            .decode(HarmonicParameters.self, from: parametersJSON)
            .migratedToCurrentDatumContract()
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
        try updateParameters(newParameters, fetchedAt: newFetchedAt)
        latitude = newLatitude
        longitude = newLongitude
    }

    /// Replaces the parameters with a freshly downloaded copy for the same
    /// coordinate. Used to pick up server-side improvements — a new tidal
    /// model, a nearby harmonic station — without moving or re-adding the
    /// location.
    public func updateParameters(
        _ newParameters: HarmonicParameters,
        fetchedAt newFetchedAt: Date = .now
    ) throws {
        parametersJSON = try Self.encode(newParameters)
        fetchedAt = newFetchedAt
    }
}
