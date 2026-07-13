import SwiftUI
import TidesCore
import TidesPlatform
import TidesUI

@main
struct TidesApp: App {
    /// Mirrors the datum preference with iCloud for the app's lifetime.
    private let datumSync = TideDatumSync()

    init() {
        datumSync.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        // Shared with the widget extension through the App Group container.
        .modelContainer(TidesModelContainer.shared)

        #if os(macOS)
        // The Mac convention: Tides > Settings… (⌘,).
        Settings {
            SettingsView()
        }
        #endif
    }
}
