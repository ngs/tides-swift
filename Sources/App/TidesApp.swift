import SwiftUI
import TidesPlatform
import TidesUI

@main
struct TidesApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        // Shared with the widget extension through the App Group container.
        .modelContainer(TidesModelContainer.shared)
    }
}
