import Foundation
import SwiftData
import TidesCore

/// Saved locations injected into the process at launch, in place of the real
/// store.
///
/// The App Store screenshot run (`Scripts/screenshots.sh`) needs the app to
/// come up with the same handful of locations on every simulator, in every
/// language, without a network round-trip, an iCloud account or whatever the
/// developer happens to have saved. It passes them in as base64-encoded JSON in
/// the environment; `TidesModelContainer` then opens an in-memory store holding
/// exactly those locations and nothing else.
///
/// The fixtures live with the screenshot tests (`Tests/Screenshots/Fixtures`),
/// not in the app bundle: nothing here ships to users, and an app launched
/// without the variable behaves exactly as before.
public enum ScreenshotSeed {
    /// Environment variable holding the base64 of a `Payload` JSON document.
    ///
    /// Base64 rather than raw JSON because the value travels through
    /// `xcodebuild` and `simctl` command lines, where quoting a nested JSON
    /// document is a foot-gun.
    public static let environmentKey = "TIDES_SCREENSHOT_SEED"

    /// The locations to seed, as encoded on the wire.
    public struct Payload: Codable, Sendable {
        public struct Location: Codable, Sendable {
            public var name: String
            public var latitude: Double
            public var longitude: Double
            /// The harmonic parameters, verbatim as tides-api serves them.
            public var parameters: HarmonicParameters

            public init(
                name: String,
                latitude: Double,
                longitude: Double,
                parameters: HarmonicParameters
            ) {
                self.name = name
                self.latitude = latitude
                self.longitude = longitude
                self.parameters = parameters
            }
        }

        public var locations: [Location]

        public init(locations: [Location]) {
            self.locations = locations
        }
    }

    /// The seed this process was launched with, if any. Decoded once: a failure
    /// to decode is reported rather than silently ignored, because a screenshot
    /// run that quietly falls back to an empty store would photograph the empty
    /// state in every language.
    public static let current: Payload? = {
        guard let encoded = ProcessInfo.processInfo.environment[environmentKey],
              !encoded.isEmpty else { return nil }
        guard let data = Data(base64Encoded: encoded) else {
            fatalError("\(environmentKey) is not valid base64")
        }
        do {
            return try HarmonicParameters.decoder().decode(Payload.self, from: data)
        } catch {
            fatalError("\(environmentKey) could not be decoded: \(error)")
        }
    }()

    /// An in-memory container holding exactly the seeded locations.
    ///
    /// Inserted through a plain `ModelContext` rather than `mainContext` so the
    /// container can be built off the main actor, as `TidesModelContainer.shared`
    /// is. Both contexts read the same in-memory store, so the app's `@Query`
    /// sees the rows.
    static func container(_ payload: Payload, schema: Schema) throws -> ModelContainer {
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        for (index, location) in payload.locations.enumerated() {
            context.insert(
                try SavedLocation(
                    name: location.name,
                    latitude: location.latitude,
                    longitude: location.longitude,
                    parameters: location.parameters,
                    fetchedAt: TideClock.now,
                    sortOrder: index
                )
            )
        }
        try context.save()
        return container
    }
}
