import Foundation
import SwiftData

/// The SwiftData stack shared by the app and its widget extension.
///
/// The store lives in the App Group container so the widget can read the saved
/// locations written by the app. Platforms or builds without the App Group
/// entitlement (e.g. macOS, previews) fall back to the target's private store,
/// which keeps the app usable even though the widget then sees no data.
public enum TidesModelContainer {
    /// App Group shared by the app and the widget extension.
    public static let appGroupID = "group.io.ngs.Tides"

    /// Models persisted by the app.
    public static let schema = Schema([SavedLocation.self])

    /// Shared container, created once per process.
    public static let shared: ModelContainer = make()

    /// Creates the shared container, falling back to a private store when the
    /// App Group container is unavailable.
    public static func make() -> ModelContainer {
        let groupConfiguration = ModelConfiguration(
            groupContainer: .identifier(appGroupID)
        )
        if let container = try? ModelContainer(for: schema, configurations: groupConfiguration) {
            return container
        }

        let localConfiguration = ModelConfiguration()
        if let container = try? ModelContainer(for: schema, configurations: localConfiguration) {
            return container
        }

        // Last resort: an in-memory store keeps the UI functional instead of
        // crashing at launch when no store can be opened at all.
        let memoryConfiguration = ModelConfiguration(isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: schema, configurations: memoryConfiguration)
        } catch {
            fatalError("Unable to create any SwiftData container: \(error)")
        }
    }
}
