import Foundation
import SwiftData
import TidesCore

/// The SwiftData stack shared by the app, its widget extension and the watch
/// app.
///
/// Two sharing channels are stacked on top of each other:
///
/// * **App Group container** — the widget extension runs in a different process
///   than the app, so both open the same store file inside the App Group.
/// * **CloudKit private database** — mirrors the store across the user's
///   devices, which is how the watch (no App Group entitlement) and the Mac see
///   the locations saved on the iPhone.
///
/// Environments where either channel is unavailable (no entitlement, signed out
/// of iCloud, previews, tests) walk down a fallback ladder instead of failing:
/// CloudKit + App Group → CloudKit only → App Group only → local store →
/// in-memory store. Every rung keeps the app fully usable offline; only sharing
/// degrades.
public enum TidesModelContainer {
    /// App Group shared by the app and the widget extension. Defined in
    /// `TidesCore` (`TidesAppGroup`) because the preferences suite used by the
    /// tide engine lives in the same container.
    public static let appGroupID = TidesAppGroup.identifier

    /// Models persisted by the app.
    public static let schema = Schema([SavedLocation.self])

    /// Shared container, created once per process.
    public static let shared: ModelContainer = make()

    /// Creates the shared container, walking down the fallback ladder until one
    /// configuration opens.
    ///
    /// - Parameter cloudKit: Whether to attempt CloudKit mirroring. Defaults to
    ///   `TidesCloudKit.isAvailable`; tests pass an explicit value.
    public static func make(cloudKit: Bool = TidesCloudKit.isAvailable) -> ModelContainer {
        for configuration in configurations(cloudKit: cloudKit) {
            if let container = try? ModelContainer(for: schema, configurations: configuration) {
                return container
            }
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

    /// Whether the App Group container can be resolved by this process.
    ///
    /// Merely constructing a group-backed `ModelConfiguration` traps (on
    /// visionOS at least) when the process lacks the App Group entitlement,
    /// as unit test runners do — so unentitled processes must skip those
    /// rungs up front instead of relying on the open to fail gracefully.
    private static var hasAppGroupContainer: Bool {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) != nil
    }

    /// Store configurations to try, best first.
    public static func configurations(cloudKit: Bool) -> [ModelConfiguration] {
        var configurations: [ModelConfiguration] = []
        if cloudKit {
            #if !os(watchOS)
            if hasAppGroupContainer {
                configurations.append(
                    ModelConfiguration(
                        groupContainer: .identifier(appGroupID),
                        cloudKitDatabase: .private(TidesCloudKit.containerIdentifier)
                    )
                )
            }
            #endif
            // The watch has no App Group entitlement: CloudKit is its only link
            // to the locations saved on the phone.
            configurations.append(
                ModelConfiguration(
                    groupContainer: .none,
                    cloudKitDatabase: .private(TidesCloudKit.containerIdentifier)
                )
            )
        }
        #if !os(watchOS)
        if hasAppGroupContainer {
            configurations.append(ModelConfiguration(groupContainer: .identifier(appGroupID)))
        }
        #endif
        configurations.append(ModelConfiguration())
        return configurations
    }
}
