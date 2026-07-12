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

    public init(
        name: String,
        latitude: Double,
        longitude: Double,
        parametersJSON: Data,
        fetchedAt: Date = .now,
        createdAt: Date = .now
    ) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.parametersJSON = parametersJSON
        self.fetchedAt = fetchedAt
        self.createdAt = createdAt
    }

    public convenience init(
        name: String,
        latitude: Double,
        longitude: Double,
        parameters: HarmonicParameters,
        fetchedAt: Date = .now
    ) throws {
        self.init(
            name: name,
            latitude: latitude,
            longitude: longitude,
            parametersJSON: try Self.encode(parameters),
            fetchedAt: fetchedAt
        )
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
