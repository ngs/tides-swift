import SwiftUI
import TidesPlatform

@main
struct TidesWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchContentView()
        }
        // The same SwiftData store as the phone and the Mac, kept in sync
        // through the private CloudKit database.
        .modelContainer(TidesModelContainer.shared)
    }
}
