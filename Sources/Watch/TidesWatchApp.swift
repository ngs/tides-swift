import SwiftUI
import TidesCore
import TidesPlatform

@main
struct TidesWatchApp: App {
    /// Follows the datum picked on the phone through iCloud's key-value
    /// store; the watch has no datum UI of its own.
    private let datumSync = TideDatumSync()

    init() {
        datumSync.start()
    }

    var body: some Scene {
        WindowGroup {
            WatchContentView()
        }
        // The same SwiftData store as the phone and the Mac, kept in sync
        // through the private CloudKit database.
        .modelContainer(TidesModelContainer.shared)
    }
}
