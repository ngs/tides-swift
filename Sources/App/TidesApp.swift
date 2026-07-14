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
        // Wide enough for the sidebar and a day of the chart side by side, and
        // 16:10 — the aspect ratio the Mac App Store wants its screenshots in.
        .defaultSize(width: 1_440, height: 900)
        #endif

        #if os(macOS)
        // The Mac convention: Tides > Settings… (⌘,). The container is attached
        // here too: this scene is not inside the WindowGroup, and settings query
        // the saved locations to refresh their parameters.
        Settings {
            SettingsView()
        }
        .modelContainer(TidesModelContainer.shared)
        #endif
    }
}
