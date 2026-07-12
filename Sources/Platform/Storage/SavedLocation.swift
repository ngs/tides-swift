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
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(parameters)
        self.init(
            name: name,
            latitude: latitude,
            longitude: longitude,
            parametersJSON: data,
            fetchedAt: fetchedAt
        )
    }

    /// Decoded harmonic parameters, or `nil` if the stored JSON is corrupt.
    public var parameters: HarmonicParameters? {
        try? HarmonicParameters.decoder().decode(HarmonicParameters.self, from: parametersJSON)
    }
}
