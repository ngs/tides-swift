import AppIntents
import Foundation
import SwiftData
import TidesPlatform

/// A saved location, exposed to the widget configuration UI.
struct SavedLocationEntity: AppEntity {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Location")
    static let defaultQuery = SavedLocationQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(String(format: "%.4f, %.4f", latitude, longitude))"
        )
    }

    /// Stable identifier derived from the SwiftData persistent identifier.
    static func id(for location: SavedLocation) -> String {
        String(describing: location.persistentModelID)
    }

    init(location: SavedLocation) {
        self.id = Self.id(for: location)
        self.name = location.name
        self.latitude = location.latitude
        self.longitude = location.longitude
    }
}

/// Lists the saved locations for the widget's location picker.
struct SavedLocationQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [SavedLocationEntity] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [SavedLocationEntity] {
        let context = ModelContext(TidesModelContainer.shared)
        let descriptor = FetchDescriptor<SavedLocation>(sortBy: SavedLocation.listSortDescriptors)
        let locations = try context.fetch(descriptor)
        return locations.map(SavedLocationEntity.init(location:))
    }

    func defaultResult() async -> SavedLocationEntity? {
        try? await suggestedEntities().first
    }
}

/// Widget configuration: which saved location to show.
struct SelectLocationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Select Location"
    // Read by the system when presenting the widget configuration UI.
    // periphery:ignore
    static let description = IntentDescription("Choose which saved location the widget shows.")

    @Parameter(title: "Location")
    var location: SavedLocationEntity?

    init() {}
}
